(() => {
  "use strict";
  const track = document.querySelector(".scroll-track");
  const pin = document.querySelector(".hero-pin");
  const poster = document.getElementById("render");
  const canvas = document.getElementById("animation");
  const ctx = canvas.getContext("2d");
  const model = document.querySelector(".model");
  const leaders = model.querySelector(".leaders");
  const scrub = document.getElementById("scrub");
  const amount = document.getElementById("amount");
  const instruction = document.getElementById("scroll-instruction");
  const title = document.getElementById("viewer-title");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  const max = Number(scrub.max);
  const cache = new Map();
  const layout = Array.from(document.querySelectorAll("#parts-guide g"), source => {
    const group = source.cloneNode(true);
    leaders.append(group);
    const path = group.querySelector("path");
    const circle = group.querySelector("circle");
    return {
      id: group.dataset.part, path, circle,
      start: path.getAttribute("d").split(" L ")[0],
      finalX: Number(circle.getAttribute("cx")),
      finalY: Number(circle.getAttribute("cy"))
    };
  });
  let anchorFrames;
  let desired = -1;
  let visible = 0;
  let request = 0;
  let lastScroll = window.scrollY;
  let manual = false;

  function label(frame) {
    const anchors = anchorFrames?.[frame];
    const show = frame > 14 && (anchors || frame === max);
    leaders.style.opacity = show ? String(Math.min(1,(frame-14)/9)) : "0";
    if (!show) return;
    for (const part of layout) {
      const anchor = anchors?.[part.id];
      const x = anchor ? anchor[0] * canvas.width : part.finalX;
      const y = anchor ? anchor[1] * canvas.height : part.finalY;
      part.path.setAttribute("d", `${part.start} L ${x} ${y}`);
      part.circle.setAttribute("cx", x);
      part.circle.setAttribute("cy", y);
    }
  }

  function frameUrl(frame) {
    return "assets/assembly/" + String(frame).padStart(2,"0") + ".webp";
  }

  function present(frame, image) {
    if (frame !== desired) return;
    if (ctx) {
      ctx.clearRect(0,0,canvas.width,canvas.height);
      ctx.drawImage(image,0,0,canvas.width,canvas.height);
      poster.style.visibility = "hidden";
    } else {
      poster.src = frameUrl(frame);
    }
    visible = frame;
    model.style.setProperty("--zoom", String(1 + 0.12 * (1 - frame / max)));
    label(frame);
    model.setAttribute("aria-label", frame > 14
      ? "Separated enclosure showing the faceplate, switch carrier, circuit board and rear shell in order from front to back."
      : "Single-gang switch enclosure with its circular push button on the faceplate.");
  }

  function load(frame) {
    if (cache.has(frame)) return cache.get(frame);
    const image = new Image();
    image.decoding = "async";
    const item = {image, ready:false};
    cache.set(frame,item);
    image.onload = () => {
      item.ready = true;
      present(frame,image);
    };
    image.onerror = () => {
      if (cache.get(frame) === item) cache.delete(frame);
    };
    image.src = frameUrl(frame);
    return item;
  }

  function select(raw) {
    const frame = Math.max(0,Math.min(max,Math.round(raw)));
    if (frame === desired) return;
    const forward = frame >= desired ? 1 : -1;
    desired = frame;
    const percent = Math.round(100*frame/max) + "%";
    const name = frame === 0 ? "Assembled" : frame === max ? "Exploded view" : "Partly separated";
    instruction.textContent = frame === max ? "Scroll to build files" : "Scroll to disassemble";
    title.textContent = name;
    amount.value = percent;
    scrub.value = String(frame);
    scrub.setAttribute("aria-valuetext",name + ", " + percent + " separation");
    scrub.style.setProperty("--fill",percent);
    const item = load(frame);
    if (item.ready) present(frame,item.image);
    for (const step of [1,2,-1,3]) {
      const next = frame + step*forward;
      if (next >= 0 && next <= max) load(next);
    }
    for (const key of cache.keys()) {
      if (Math.abs(key-frame) > 6) cache.delete(key);
    }
  }

  function scrollPosition() {
    const header = document.querySelector(".topbar").offsetHeight;
    const start = track.getBoundingClientRect().top + window.scrollY - header;
    return {start, distance: Math.max(0, track.offsetHeight - pin.offsetHeight)};
  }

  function syncScroll() {
    request = 0;
    if (!manual && !reduced.matches) {
      const {start,distance} = scrollPosition();
      if (distance > 0) select((window.scrollY - start) / distance * max);
    }
  }

  window.addEventListener("scroll",() => {
    if (window.scrollY !== lastScroll) manual = false;
    lastScroll = window.scrollY;
    if (!request) request = requestAnimationFrame(syncScroll);
  },{passive:true});
  window.addEventListener("resize",syncScroll);
  reduced.addEventListener("change",syncScroll);
  scrub.addEventListener("input",() => {
    manual = true;
    select(Number(scrub.value));
    const {start,distance} = scrollPosition();
    if (!reduced.matches && distance > 0) {
      window.scrollTo({top:start + distance * desired/max, behavior:"instant"});
    }
  });
  document.querySelectorAll("[data-explore]").forEach(link => link.addEventListener("click",event => {
    event.preventDefault();
    const {start,distance} = scrollPosition();
    if (reduced.matches || distance === 0) {
      manual = true;
      select(max);
      document.getElementById("assembly").scrollIntoView({block:"center",behavior:"instant"});
    } else {
      manual = false;
      window.scrollTo({top:start+distance,behavior:"smooth"});
    }
    scrub.focus({preventScroll:true});
  }));
  document.documentElement.classList.add("interactive");
  label(0);
  fetch("assets/assembly/anchors.json").then(response => {
    if (!response.ok) throw new Error("Missing label coordinates");
    return response.json();
  }).then(data => {anchorFrames = data; label(visible);}).catch(() => {
    // The static guide supplies the fully separated coordinates when opened offline.
  });
  select(0);
  if (location.hash === "#assembly") document.querySelector("[data-explore]").click();
  else syncScroll();
})();
