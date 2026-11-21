(() => {
  "use strict";

  const sequence = document.getElementById("sequence");
  const pin = sequence?.querySelector(".sequence-pin");
  const canvas = document.getElementById("sequence-canvas");
  const poster = document.getElementById("sequence-poster");
  const slider = document.getElementById("sequence-scrub");
  const percent = document.getElementById("sequence-percent");
  const context = canvas?.getContext("2d");
  if (!pin || !poster || !slider || !context || !window.Image.prototype.decode) return;

  const labelLayer = document.getElementById("sequence-labels");
  const labelGroups = Array.from(labelLayer?.querySelectorAll("[data-label-group]") || [], layer => {
    const labels = Array.from(layer.querySelectorAll("[data-part]"), group => {
      const text = group.querySelector("text");
      return {
        part: group.dataset.part, group, path: group.querySelector("path"), dot: group.querySelector("circle"),
        x: Number(text.getAttribute("x")), y: Number(text.getAttribute("y")) + 8,
        elbow: text.getAttribute("text-anchor") === "end" ? -26 : 26,
      };
    });
    return {layer, labels};
  });
  const chapters = Array.from(sequence.querySelectorAll("[data-chapter-at]"), button => ({
    button, at: Number(button.dataset.chapterAt), title: button.textContent.trim(),
  }));
  const copies = sequence.querySelectorAll("[data-chapter-copy]");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  const saveData = navigator.connection?.saveData === true;
  const endFrame = 72;
  const cacheLimit = saveData ? 3 : 7;
  const decoded = new Map();
  const loading = new Set();
  const failed = new Map();
  const clamp = value => Math.min(1, Math.max(0, value));
  const descriptions = [
    "Rotating view of the assembled Nultra wall switch.",
    "The faceplate lifts away first. The AA cell, carrier, populated circuit board and rear shell then separate.",
    "Close-up of the circuit board showing the printed antenna, Bluetooth microcontroller and test point.",
  ];

  let anchors;
  let fetchingAnchors = false;
  let retryAnchorsAfter = 0;
  let target = 0;
  let displayed = 0;
  let direction = 1;
  let activeChapter = -1;
  let nearScene = false;
  let lookAheadUntil = 0;
  let queued = false;
  let needsMeasurement = true;
  let scrollStart = 0;
  let scrollSpan = 0;
  let sceneTop = 0;
  let sceneBottom = 0;
  let lastPercent = -1;

  function chapterAt(frame) {
    if (frame >= 56) return 2;
    return frame >= 18 ? 1 : 0;
  }

  function showChapter(frame) {
    const index = chapterAt(frame);
    if (index === activeChapter) return;
    activeChapter = index;
    sequence.dataset.chapter = String(index);
    chapters.forEach(({button}, i) => button.setAttribute("aria-pressed", String(i === index)));
    copies.forEach((copy, i) => { copy.hidden = i !== index; });
    poster.alt = descriptions[Math.min(index, descriptions.length - 1)];
  }

  function placeLabels(frame) {
    if (!labelLayer) return;
    const positions = anchors?.[frame];
    labelLayer.style.opacity = positions ? "1" : "0";
    if (!positions) return;
    const bounds = labelLayer.viewBox.baseVal;
    for (const {layer, labels} of labelGroups) {
      // Separate the assembly callouts before the camera pushes into the PCB.
      const opacity = layer.dataset.labelGroup === "board"
        ? clamp((frame - 58) / 6)
        : Math.min(clamp((frame - 33) / 5), clamp((53 - frame) / 5));
      layer.style.opacity = String(opacity);
      if (!opacity) continue;
      for (const {part, group, path, dot, x, y, elbow} of labels) {
        const anchor = positions[part];
        const visible = Array.isArray(anchor) && anchor.length === 2 &&
          anchor.every(coordinate => Number.isFinite(coordinate) && coordinate >= 0 && coordinate <= 1);
        group.style.visibility = visible ? "visible" : "hidden";
        if (!visible) continue;
        const ax = anchor[0] * bounds.width;
        const ay = anchor[1] * bounds.height;
        path.setAttribute("d", `M ${x} ${y} h ${elbow} L ${ax} ${ay}`);
        dot.setAttribute("cx", ax);
        dot.setAttribute("cy", ay);
      }
    }
  }

  async function loadAnchors() {
    if (!labelLayer || anchors || fetchingAnchors || performance.now() < retryAnchorsAfter) return;
    fetchingAnchors = true;
    try {
      const response = await fetch("assets/product/anchors.json");
      if (!response.ok) throw new Error();
      anchors = await response.json();
      placeLabels(displayed);
    } catch {
      retryAnchorsAfter = performance.now() + 5000;
    } finally {
      fetchingAnchors = false;
    }
  }

  function draw(frame) {
    if (frame === displayed) return;
    if (frame > 0) {
      const image = decoded.get(frame);
      context.clearRect(0, 0, canvas.width, canvas.height);
      context.drawImage(image, 0, 0, canvas.width, canvas.height);
    }
    // Keep the HTML poster in place until a complete frame has been painted.
    canvas.style.opacity = frame > 0 ? "1" : "0";
    poster.style.opacity = frame > 0 ? "0" : "1";
    displayed = frame;
    showChapter(frame);
    placeLabels(frame);
  }

  function drawClosest() {
    if (target === 0 || decoded.has(target)) {
      draw(target);
      return;
    }
    let nearest = displayed;
    const low = Math.min(displayed, target);
    const high = Math.max(displayed, target);
    for (const frame of decoded.keys()) {
      if (frame < low || frame > high) continue;
      if (Math.abs(frame - target) < Math.abs(nearest - target)) nearest = frame;
    }
    draw(nearest);
  }

  function trimCache() {
    if (decoded.size <= cacheLimit) return;
    let farthest;
    for (const frame of decoded.keys()) {
      if (frame === displayed) continue;
      if (farthest === undefined || Math.abs(frame - target) > Math.abs(farthest - target)) farthest = frame;
    }
    decoded.delete(farthest);
  }

  async function loadFrame(frame) {
    loading.add(frame);
    try {
      const image = new Image();
      image.decoding = "async";
      image.src = "assets/product/frames/" + String(frame).padStart(3, "0") + ".webp";
      await image.decode();
      decoded.set(frame, image);
      if (nearScene) drawClosest();
      trimCache();
    } catch {
      // Keep the last complete image if a connection drops while scrolling.
      failed.set(frame, performance.now() + 5000);
    } finally {
      loading.delete(frame);
      pump();
    }
  }

  function pump() {
    if (!nearScene || document.hidden || target === 0) return;
    const now = performance.now();
    const limit = reduced.matches || saveData ? 1 : 2;
    const candidates = [target];
    if (limit > 1 && now < lookAheadUntil) candidates.push(target + direction);
    for (const frame of candidates) {
      if (loading.size >= limit) break;
      if (frame < 1 || frame > endFrame || decoded.has(frame) || loading.has(frame) || failed.get(frame) > now) continue;
      loadFrame(frame);
    }
  }

  function select(value, predict) {
    const progress = clamp(value);
    const frame = Math.round(progress * endFrame);
    if (frame !== target) {
      direction = Math.sign(frame - target);
      target = frame;
      lookAheadUntil = predict ? performance.now() + 100 : 0;
    }
    const number = Math.round(progress * 100);
    if (lastPercent !== number) {
      lastPercent = number;
      slider.value = String(number);
      const chapter = chapters[chapterAt(frame)];
      slider.setAttribute("aria-valuetext", (chapter ? chapter.title + ", " : "") + number + "%");
      if (percent) percent.value = number + "%";
      sequence.style.setProperty("--sequence-progress", String(progress));
    }
    drawClosest();
    if (target >= 28) loadAnchors();
    pump();
  }

  function measure() {
    needsMeasurement = false;
    const top = window.scrollY;
    const rect = sequence.getBoundingClientRect();
    sceneTop = top + rect.top;
    sceneBottom = top + rect.bottom;
    const style = getComputedStyle(pin);
    scrollStart = sceneTop - (parseFloat(style.top) || 0);
    scrollSpan = style.position === "sticky" ? Math.max(0, rect.height - pin.offsetHeight) : 0;
  }

  function syncScroll() {
    queued = false;
    if (needsMeasurement) measure();
    const y = window.scrollY;
    nearScene = y + window.innerHeight >= sceneTop && y <= sceneBottom;
    if (nearScene && scrollSpan > 0 && !reduced.matches) select((y - scrollStart) / scrollSpan, true);
    else if (nearScene) pump();
  }

  function schedule() {
    if (!queued) {
      queued = true;
      requestAnimationFrame(syncScroll);
    }
  }

  function remeasure() {
    needsMeasurement = true;
    schedule();
  }

  function seek(progress) {
    if (needsMeasurement) measure();
    nearScene = true;
    if (!reduced.matches && scrollSpan > 0) {
      window.scrollTo({top: scrollStart + scrollSpan * progress, behavior: "instant"});
    }
    select(progress, false);
  }

  slider.addEventListener("input", () => seek(Number(slider.value) / 100));
  chapters.forEach(({button, at}) => button.addEventListener("click", () => seek(at)));
  window.addEventListener("scroll", schedule, {passive: true});
  window.addEventListener("resize", remeasure);
  window.addEventListener("pageshow", remeasure);
  document.addEventListener("visibilitychange", schedule);
  reduced.addEventListener("change", remeasure);
  if ("ResizeObserver" in window) {
    const observer = new ResizeObserver(remeasure);
    for (const element of [document.body, sequence, pin]) observer.observe(element);
  }

  sequence.classList.add("motion-ready");
  showChapter(0);
  placeLabels(0);
  select(0, false);
  syncScroll();
})();
