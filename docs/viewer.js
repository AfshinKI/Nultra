(() => {
  "use strict";

  const sequence = document.getElementById("sequence");
  const pin = sequence?.querySelector(".sequence-pin");
  const room = document.getElementById("room-stage");
  const hardware = sequence?.querySelector(".hardware-stage");
  const canvas = document.getElementById("sequence-canvas");
  const poster = document.getElementById("sequence-poster");
  const slider = document.getElementById("sequence-scrub");
  const percent = document.getElementById("sequence-percent");
  const context = canvas?.getContext("2d");
  if (!pin || !room || !hardware || !slider || !poster || !context || !window.Image.prototype.decode) return;

  const clamp = value => Math.max(0, Math.min(1, value));
  const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const saveData = navigator.connection?.saveData === true;
  const hardwareStart = .37;
  const handoffStart = .346;
  const lastFrame = 232;
  const atlasVersion = "?v=233b";
  const framesPerSheet = 4;
  const tileWidth = 1056;
  const tileHeight = 864;
  const sheetOf = frame => Math.floor(frame / framesPerSheet);
  // The separated AA gets time on screen before the camera turns toward the board.
  const beats = [
    [hardwareStart, 0], [.50, 36], [.583, 60], [.62, 78], [.665, 89], [.714, 92],
    [.777, 132], [.80, 140], [.815, 146], [.868, 164], [.933, 204], [.962, 216], [1, lastFrame],
  ];
  function frameAt(progress) {
    if (progress <= hardwareStart) return 0;
    for (let i = 1; i < beats.length; i++) {
      const [end, final] = beats[i];
      if (progress <= end) {
        const [begin, initial] = beats[i - 1];
        return initial + (final - initial) * ((progress - begin) / (end - begin));
      }
    }
    return lastFrame;
  }
  const sheets = new Map();
  const pending = new Set();
  const retryAfter = new Map();
  const retried = new Set();
  const labels = document.getElementById("sequence-labels");
  const labelGroups = Array.from(labels?.querySelectorAll("[data-label-group]") || [], element => ({
    element,
    parts: Array.from(element.querySelectorAll("[data-part]"), part => {
      const text = part.querySelector("text");
      return {part, key: part.dataset.part, line: part.querySelector("path"), dot: part.querySelector("circle"),
        x: Number(text.getAttribute("x")), y: Number(text.getAttribute("y")) + 8,
        elbow: text.getAttribute("text-anchor") === "end" ? -26 : 26};
    }),
  }));
  const tabs = Array.from(sequence.querySelectorAll("[data-chapter-at]"));
  const copies = sequence.querySelectorAll("[data-chapter-copy]");
  const lampButton = sequence.querySelector("[data-room-lamp]");
  const roomIntro = room.querySelector(".room-intro");
  const lampText = lampButton?.querySelector("[data-room-action-text]");
  const mast = document.querySelector(".mast");
  const descriptions = [
    "Assembled Nultra wall switch at a three-quarter angle.",
    "Assembled Nultra wall switch turning to reveal its side profile.",
    "The faceplate lifts first, then the AA cell, carrier, circuit board and rear shell separate.",
    "Both sides of the populated circuit board.",
  ];
  const inspectionDescriptions = {
    debug: "The ten exposed debug pads connect the programming and diagnostic interface.",
    board: "The front of the board carries the printed antenna and Bluetooth microcontroller.",
    turn: "The circuit board turns to show its reverse side.",
    power: "The rear-side DC/DC converter raises the AA cell voltage for the electronics.",
    relay: "The latching relay sits on the reverse of the board.",
  };

  let target = 0, position = 0, drawnFrame = 0;
  let chapter = -1, lastPercent = -1, lastRoomProgress = -1;
  let lampOverride, lampAt = 0, lastLampState, lastOverride;
  let anchors, anchorsPending = false, anchorRetry = 0, anchorRetried = false;
  let wantedSheets = [];
  let start = 0, span = 0, bottom = 0, inView = true;
  let measureNeeded = true, scrollChanged = true, resetPosition = true;
  let raf = 0, previousTime = 0, direction = 1, backingWidth = canvas.width;
  const historyReturn = performance.getEntriesByType?.("navigation")[0]?.type === "back_forward";
  let introState = motion.matches || location.hash || historyReturn ? "done" : "waiting";
  let introElapsed = 0, introTime = 0, introOrigin = 0;
  let holdTimer = 0, holdSince = 0, holdRemaining = 0;

  function smooth(value) {
    const t = clamp(value);
    return t * t * (3 - 2 * t);
  }

  function windowOpacity(value, from, to, endFrom, endTo) {
    return Math.min(smooth((value - from) / (to - from)), 1 - smooth((value - endFrom) / (endTo - endFrom)));
  }

  function renderLabels(frame) {
    if (!labels) return;
    const lo = Math.floor(frame), hi = Math.ceil(frame), fraction = frame - lo;
    const current = anchors?.[lo], next = anchors?.[hi];
    labels.style.opacity = current ? "1" : "0";
    if (!current) return;
    const area = labels.viewBox.baseVal;
    for (const {element, parts} of labelGroups) {
      let opacity;
      switch (element.dataset.labelGroup) {
        case "reveal": opacity = windowOpacity(frame, 59.5, 62, 70, 73); break;
        case "assembly": opacity = windowOpacity(frame, 73, 77, 98, 109); break;
        case "debug": opacity = windowOpacity(frame, 132, 135, 143, 146); break;
        case "board": opacity = windowOpacity(frame, 146, 150, 161, 164); break;
        case "power": opacity = windowOpacity(frame, 204, 208, 213, 216); break;
        case "relay": opacity = smooth((frame - 216) / 5); break;
        default: opacity = 0;
      }
      element.style.opacity = String(opacity);
      if (!opacity) continue;
      for (const {part, key, line, dot, x, y, elbow} of parts) {
        const a = current[key], b = next?.[key] || a;
        const valid = Array.isArray(a) && Array.isArray(b) && a.length === 2 && b.length === 2;
        const ax = valid ? a[0] + (b[0] - a[0]) * fraction : NaN;
        const ay = valid ? a[1] + (b[1] - a[1]) * fraction : NaN;
        const visible = ax >= 0 && ax <= 1 && ay >= 0 && ay <= 1;
        part.style.visibility = visible ? "visible" : "hidden";
        if (!visible) continue;
        const px = ax * area.width, py = ay * area.height;
        line.setAttribute("d", `M ${x} ${y} h ${elbow} L ${px} ${py}`);
        dot.setAttribute("cx", px);
        dot.setAttribute("cy", py);
      }
    }
  }

  async function loadAnchors() {
    if (!labels || anchors || anchorsPending || performance.now() < anchorRetry) return;
    anchorsPending = true;
    try {
      const response = await fetch("assets/product/motion/anchors.json" + atlasVersion);
      if (!response.ok) throw new Error("Missing callouts");
      anchors = await response.json();
      renderLabels(drawnFrame);
    } catch {
      anchorRetry = performance.now() + 2000;
      if (!anchorRetried) {
        anchorRetried = true;
        window.setTimeout(schedule, 2050);
      }
    } finally {
      anchorsPending = false;
    }
  }

  function trimSheets() {
    const limit = saveData || motion.matches ? 2 : 3;
    const focus = sheetOf(Math.round(frameAt(position)));
    while (sheets.size > limit) {
      const removable = [...sheets.keys()].filter(index => !wantedSheets.includes(index));
      const candidates = removable.length ? removable : [...sheets.keys()];
      const oldest = candidates.sort((a, b) => Math.abs(b - focus) - Math.abs(a - focus))[0];
      sheets.delete(oldest);
    }
  }

  function requestSheet(index) {
    const now = performance.now();
    if (index < 0 || index > sheetOf(lastFrame) || sheets.has(index) || pending.has(index) || retryAfter.get(index) > now) return;
    pending.add(index);
    const image = new Image();
    image.decoding = "async";
    image.src = "assets/product/motion/" + String(index).padStart(3, "0") + ".webp" + atlasVersion;
    image.decode().then(() => {
      sheets.set(index, image);
      retryAfter.delete(index);
      trimSheets();
    }).catch(() => {
      retryAfter.set(index, performance.now() + 2000);
      if (!retried.has(index)) {
        retried.add(index);
        window.setTimeout(schedule, 2050);
      }
    }).finally(() => {
      pending.delete(index);
      schedule();
    });
  }

  function buffer(frame) {
    if (!inView || document.hidden || Math.max(position, target) < .28) return;
    const limited = saveData || motion.matches;
    const concurrency = limited ? 1 : 2;
    const page = sheetOf(Math.round(frame));
    const candidates = [page];
    const otherTile = sheetOf(Math.floor(frame)) === page ? sheetOf(Math.ceil(frame)) : sheetOf(Math.floor(frame));
    if (otherTile !== page) candidates.push(otherTile);
    if (!limited && position >= handoffStart) {
      const destination = sheetOf(Math.round(frameAt(target)));
      const neighbor = page + direction;
      if (destination !== page) candidates.push(destination);
      if (frame > 1 || direction < 0) candidates.push(neighbor);
    }
    wantedSheets = [...new Set(candidates)].slice(0, limited ? 2 : 3);
    for (const index of wantedSheets) {
      if (pending.size >= concurrency) break;
      requestSheet(index);
    }
    if (Math.max(frame, frameAt(target)) >= 40) loadAnchors();
  }

  function tile(frame) {
    return frame === 0 && poster.complete && poster.naturalWidth ? poster : sheets.get(sheetOf(frame));
  }

  function drawTile(image, frame) {
    const cell = image === poster ? 0 : frame % framesPerSheet;
    context.drawImage(image, (cell % 2) * tileWidth, Math.floor(cell / 2) * tileHeight,
      tileWidth, tileHeight, 0, 0, canvas.width, canvas.height);
  }

  function sizeCanvas() {
    if (canvas.width === backingWidth) return false;
    canvas.width = backingWidth;
    canvas.height = Math.round(backingWidth * tileHeight / tileWidth);
    return true;
  }

  function paint(frame) {
    if (frame === 0) {
      sizeCanvas();
      if (drawnFrame !== 0) {
        canvas.style.opacity = "0";
        poster.style.opacity = "1";
        drawnFrame = 0;
        renderLabels(0);
      }
      return;
    }
    let lo = Math.floor(frame), hi = Math.ceil(frame);
    let imageA = tile(lo), imageB = tile(hi);
    if (!imageA && !imageB) return;
    if (!imageA) { lo = hi; imageA = imageB; }
    if (!imageB) { hi = lo; imageB = imageA; }
    const fraction = hi === lo ? 0 : frame - lo;
    const actual = lo + fraction;
    if (!sizeCanvas() && Math.abs(actual - drawnFrame) < .002) return;
    if (actual > 0) {
      context.clearRect(0, 0, canvas.width, canvas.height);
      context.globalAlpha = 1 - fraction;
      drawTile(imageA, lo);
      if (fraction) {
        // Add premultiplied RGBA so transparent edges retain their coverage during in-between frames.
        context.globalCompositeOperation = "lighter";
        context.globalAlpha = fraction;
        drawTile(imageB, hi);
        context.globalCompositeOperation = "source-over";
      }
      context.globalAlpha = 1;
    }
    canvas.style.opacity = actual > 0 ? "1" : "0";
    poster.style.opacity = actual > 0 ? "0" : "1";
    drawnFrame = actual;
    renderLabels(actual);
  }

  function renderRoom(progress) {
    const lit = lampOverride ?? progress >= .36;
    if (progress !== lastRoomProgress || lit !== lastLampState || lampOverride !== lastOverride) {
      window.NultraRoom?.setState(progress, lampOverride);
      sequence.style.setProperty("--room-progress", String(progress));
      if (roomIntro) roomIntro.inert = progress >= .8;
      lastRoomProgress = progress;
      lastLampState = lit;
      lastOverride = lampOverride;
      if (lampButton) {
        lampButton.hidden = !window.NultraRoom;
        lampButton.setAttribute("aria-pressed", String(lit));
        if (lampText) lampText.textContent = lit ? "Turn lamp off" : "Turn lamp on";
      }
    }
  }

  function render() {
    const mix = smooth((position - handoffStart) / (hardwareStart - handoffStart));
    sequence.style.setProperty("--room-opacity", String(1 - mix));
    // The room sits above the matched hardware pose. An opaque base avoids a dark dip in the dissolve.
    sequence.style.setProperty("--hardware-opacity", position >= handoffStart ? "1" : "0");
    room.inert = mix >= .5;
    hardware.inert = mix < .5;
    renderRoom(clamp(position / hardwareStart));
    const frame = frameAt(position);
    buffer(frame);
    paint(frame);
    const batteryProgress = smooth((position - .598) / (.709 - .598));
    sequence.style.setProperty("--battery-life-progress", String(batteryProgress));
    sequence.style.setProperty("--battery-life-visibility", String(windowOpacity(position, .585, .605, .72, .742)));
    const active = position < hardwareStart - .0006 ? 0 : drawnFrame < 36 ? 1 : drawnFrame < 123 ? 2 : 3;
    if (chapter !== active) {
      chapter = active;
      sequence.dataset.chapter = String(active);
      tabs.forEach((button, i) => button.setAttribute("aria-pressed", String(i === active)));
      copies.forEach((copy, i) => { copy.hidden = i !== active; });
    }
    const shot = drawnFrame < 146 ? "debug" : drawnFrame < 164 ? "board" :
      drawnFrame < 204 ? "turn" : drawnFrame < 216 ? "power" : "relay";
    const inspection = active === 3 ? shot : "";
    if (sequence.dataset.inspection !== inspection) sequence.dataset.inspection = inspection;
    const description = inspection ? inspectionDescriptions[inspection] : descriptions[active];
    if (poster.alt !== description) poster.alt = description;
    const number = Math.round(target * 100);
    if (number !== lastPercent || slider.dataset.chapter !== String(active)) {
      lastPercent = number;
      slider.dataset.chapter = String(active);
      slider.value = String(number);
      slider.setAttribute("aria-valuetext", (tabs[active]?.textContent.trim() || "") + ", " + number + "%");
      if (percent) percent.value = number + "%";
      sequence.style.setProperty("--sequence-progress", String(target));
    }
  }

  function measure() {
    const rect = sequence.getBoundingClientRect();
    const style = getComputedStyle(pin);
    start = window.scrollY + rect.top - (parseFloat(style.top) || mast?.offsetHeight || 0);
    span = style.position === "sticky" ? Math.max(0, rect.height - pin.offsetHeight) : 0;
    bottom = window.scrollY + rect.bottom;
    const displayWidth = canvas.getBoundingClientRect().width;
    const width = Math.min(tileWidth, Math.round(displayWidth * Math.min(window.devicePixelRatio || 1, 1.5)));
    if (width > 0) backingWidth = width;
    measureNeeded = false;
  }

  function updateTarget(value, instant) {
    const next = clamp(value);
    if (next !== target) direction = Math.sign(next - target);
    target = next;
    if (lampOverride !== undefined && Math.abs(target - lampAt) > .055) lampOverride = undefined;
    // Direct section links and fast page jumps request the destination sheet immediately.
    if (instant || motion.matches || Math.abs(target - position) > .19) position = target;
  }

  function introOwnsTimeline() {
    return introState !== "done" && introState !== "waiting";
  }

  function pauseHold() {
    if (!holdTimer) return;
    window.clearTimeout(holdTimer);
    holdTimer = 0;
    holdRemaining = Math.max(0, holdRemaining - (performance.now() - holdSince));
  }

  function scheduleHold() {
    if (holdTimer || document.hidden) return;
    holdSince = performance.now();
    const phase = introState;
    holdTimer = window.setTimeout(() => {
      holdTimer = 0;
      if (introState !== phase) return;
      if (document.hidden) {
        holdRemaining = Math.max(0, holdRemaining - (performance.now() - holdSince));
        return;
      }
      introState = phase === "lit-hold" ? "rewinding" : "playing";
      introElapsed = 0;
      introTime = 0;
      schedule();
    }, holdRemaining);
  }

  function stopIntro(alignScroll) {
    if (introState === "done") return;
    const wasPlaying = introOwnsTimeline();
    pauseHold();
    introState = "done";
    introTime = 0;
    window.removeEventListener("wheel", takeWheel, true);
    for (const type of takeoverInputs) window.removeEventListener(type, takeControl, true);
    if (!wasPlaying) return;
    target = position;
    previousTime = 0;
    if (alignScroll && span > 0 && !motion.matches && inView) {
      // Both coordinates paint the same pinned view. Align before the native wheel/touch/key action.
      const aligned = start + span * position;
      if (Math.abs(window.scrollY - aligned) > .5) window.scrollTo({top: aligned, behavior: "instant"});
    }
  }

  function playIntro(time) {
    if (introState === "waiting") {
      if (Math.abs(window.scrollY - start) > 3 || !inView || motion.matches) {
        stopIntro(false);
        return false;
      }
      introOrigin = window.scrollY;
      introState = "playing";
    }
    if (introState === "lit-hold" || introState === "dark-hold") {
      scheduleHold();
      return true;
    }
    if (!introOwnsTimeline()) return false;
    if (introTime) introElapsed += Math.max(0, time - introTime);
    introTime = time;
    const forward = introState === "playing";
    const elapsed = clamp(forward ? (introElapsed - 200) / 3500 : introElapsed / 2600);
    position = target = .14 * (forward ? smooth(elapsed) : 1 - smooth(elapsed));
    if (elapsed === 1) {
      introState = forward ? "lit-hold" : "dark-hold";
      holdRemaining = forward ? 5000 : 1200;
      scheduleHold();
    }
    return true;
  }

  function tick(time) {
    raf = 0;
    if (document.hidden) return;
    if (measureNeeded) measure();
    if (scrollChanged) {
      scrollChanged = false;
      const y = window.scrollY;
      inView = y + window.innerHeight >= start && y <= bottom;
      if (introState === "waiting" && (!inView || Math.abs(y - start) > 3)) stopIntro(false);
      if (introState === "done" && span && !motion.matches) updateTarget((y - start) / span, resetPosition);
      resetPosition = false;
    }
    if (!inView) return;
    if (playIntro(time)) {
      render();
      if (introState === "playing" || introState === "rewinding") schedule();
      return;
    }
    const dt = previousTime ? Math.min(60, Math.max(1, time - previousTime)) : 16;
    previousTime = time;
    const remaining = target - position;
    position = Math.abs(remaining) < .00012 ? target : position + remaining * (1 - Math.exp(-dt / 60));
    render();
    if (position !== target) schedule();
    else previousTime = 0;
  }

  function schedule() {
    if (!raf) raf = window.requestAnimationFrame(tick);
  }

  function seek(value, scrollToStory) {
    if (!Number.isFinite(value)) return;
    stopIntro(false);
    if (measureNeeded) measure();
    inView = true;
    updateTarget(value, true);
    if (span && !motion.matches || scrollToStory) {
      window.scrollTo({top: start + (motion.matches ? 0 : span * target), behavior: "instant"});
    }
    render();
    schedule();
  }

  function toggleLamp() {
    if (position >= hardwareStart) return;
    stopIntro(true);
    lampAt = target;
    lampOverride = !(lampOverride ?? position / hardwareStart >= .36);
    renderRoom(clamp(position / hardwareStart));
  }

  function remeasure() {
    measureNeeded = true;
    scrollChanged = true;
    schedule();
  }

  slider.addEventListener("input", () => seek(Number(slider.value) / 100, false));
  tabs.forEach(button => button.addEventListener("click", () => seek(Number(button.dataset.chapterAt), false)));
  document.querySelectorAll("[data-story-at]").forEach(link => link.addEventListener("click", event => {
    if (event.button > 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    if (link.hash && link.hash !== location.hash) window.history.pushState(null, "", link.hash);
    seek(Number(link.dataset.storyAt), true);
  }));
  lampButton?.addEventListener("click", toggleLamp);
  window.addEventListener("nultra-lamp-toggle", toggleLamp);
  window.addEventListener("nultra-room-ready", () => { lastRoomProgress = -1; schedule(); });
  const takeoverInputs = ["touchstart", "pointerdown", "keydown"];
  const takeControl = () => stopIntro(true);
  function takeWheel(event) {
    if (introOwnsTimeline() && span && event.cancelable && event.deltaY && !event.ctrlKey) {
      // A compositor can otherwise discard the first upward delta because the physical document is still at zero.
      const unit = event.deltaMode === 2 ? window.innerHeight : event.deltaMode === 1 ? 16 : 1;
      const nextY = start + span * position + event.deltaY * unit;
      stopIntro(false);
      event.preventDefault();
      window.scrollTo({top: nextY, behavior: "instant"});
      return;
    }
    stopIntro(true);
  }
  if (introState !== "done") {
    window.addEventListener("wheel", takeWheel, {capture:true, passive:false});
    for (const type of takeoverInputs) window.addEventListener(type, takeControl, {capture:true, passive:true});
  }
  window.addEventListener("scroll", () => {
    // Scrollbar and accessibility scrolls can arrive without a preceding input event.
    if (introOwnsTimeline() && Math.abs(window.scrollY - introOrigin) > 1) {
      const nativeY = window.scrollY;
      stopIntro(false);
      if (span && nativeY < bottom && !motion.matches) {
        window.scrollTo({top: nativeY + position * span, behavior: "instant"});
      }
    }
    scrollChanged = true;
    schedule();
  }, {passive:true});
  window.addEventListener("resize", remeasure);
  window.addEventListener("pageshow", remeasure);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) pauseHold();
    introTime = 0;
    previousTime = 0;
    remeasure();
  });
  motion.addEventListener("change", () => { if (motion.matches) stopIntro(false); remeasure(); });
  if ("ResizeObserver" in window) {
    const observer = new ResizeObserver(remeasure);
    observer.observe(sequence);
    observer.observe(pin);
    if (mast) observer.observe(mast);
  }

  sequence.classList.add("motion-ready");
  render();
  schedule();
})();
