(() => {
  "use strict";
  const section = document.getElementById("control");
  if (!section) return;
  const pin = section.querySelector(".control-pin");
  const stage = section.querySelector("[data-phone-stage]");
  const app = section.querySelector("[data-phone-app]");
  const launcher = section.querySelector("[data-phone-launch]");
  const detail = section.querySelector("[data-phone-detail]");
  const action = section.querySelector("[data-phone-action]");
  const desk = section.querySelector("[data-toggle-desk]");
  const caption = section.querySelector("[data-phone-caption]");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  const dashboardPosition = .46, lightPosition = .78;
  let current = -1;
  let replayStart = null;
  let manualY = null;
  let frame = 0;
  let start = 0;
  let travel = 0;
  let layoutDirty = true;

  const clamp = x => Math.max(0, Math.min(1, x));
  function ramp(value, first, last) {
    const t = clamp((value - first) / (last - first));
    return t * t * (3 - 2 * t);
  }
  function show(position) {
    const p = clamp(position);
    if (p === current) return;
    current = p;
    const open = ramp(p, .12, .37);
    const lit = p >= .68;
    const details = p >= .9;
    const onDashboard = open >= .96;
    stage.style.setProperty("--ph-open", String(open));
    stage.style.setProperty("--ph-glow", String(ramp(p, .65, .78)));
    stage.style.setProperty("--ph-tilt", (-4 + 3 * ramp(p, 0, .78)).toFixed(2) + "deg");
    const tap = reduced.matches ? 0 : ramp(p, .48, .60) * (1 - ramp(p, .67, .76));
    stage.style.setProperty("--ph-tap", String(tap));
    stage.dataset.app = onDashboard ? "open" : "closed";
    stage.dataset.lamp = lit ? "on" : "off";
    stage.dataset.view = details ? "detail" : "dashboard";
    launcher.inert = onDashboard;
    app.inert = !onDashboard;
    detail.inert = !details;
    desk.disabled = details;
    caption.textContent = !onDashboard ? "App closed" : lit ? "Desk lamp on" : "Desk lamp off";
    action.textContent = !onDashboard ? "Open app" : lit ? "Turn lamp off" : "Turn lamp on";
    desk.setAttribute("aria-label", lit ? "Turn desk lamp off" : "Turn desk lamp on");
  }
  function measure() {
    const style = getComputedStyle(pin);
    start = section.getBoundingClientRect().top + window.scrollY - (parseFloat(style.top) || 0);
    travel = style.position === "sticky" ? Math.max(0, section.offsetHeight - pin.offsetHeight) : 0;
    layoutDirty = false;
  }
  function sync(now) {
    frame = 0;
    if (layoutDirty) measure();
    if (manualY !== null && Math.abs(window.scrollY - manualY) > 22) {
      manualY = null;
      replayStart = null;
    }
    if (replayStart !== null) {
      const progress = clamp((now - replayStart) / 2800);
      show(progress);
      if (progress < 1) schedule();
      else replayStart = null;
    } else if (travel && !reduced.matches && manualY === null) {
      show((window.scrollY - start) / travel);
    }
  }
  function schedule() {
    if (!frame) frame = window.requestAnimationFrame(sync);
  }
  function manual(position) {
    replayStart = null;
    manualY = window.scrollY;
    show(position);
  }
  function act() {
    if (stage.dataset.app === "closed") manual(dashboardPosition);
    else manual(stage.dataset.lamp === "on" ? dashboardPosition : lightPosition);
  }
  section.querySelector("[data-open-app]").addEventListener("click", event => {
    manual(dashboardPosition);
    if (!event.detail) desk.focus({preventScroll:true});
  });
  desk.addEventListener("click", act);
  action.addEventListener("click", act);
  section.querySelector("[data-switch-off]").addEventListener("click", event => {
    manual(dashboardPosition);
    if (!event.detail) desk.focus({preventScroll:true});
  });
  section.querySelector("[data-close-detail]").addEventListener("click", event => {
    manual(lightPosition);
    if (!event.detail) desk.focus({preventScroll:true});
  });
  section.querySelector("[data-phone-replay]").addEventListener("click", () => {
    manual(0);
    if (!reduced.matches) {
      replayStart = performance.now();
      schedule();
    }
  });
  const resized = () => { layoutDirty = true; schedule(); };
  section.classList.add("ph-ready");
  section.querySelector("[data-phone-controls]").hidden = false;
  show(0);
  window.addEventListener("scroll", schedule, {passive:true});
  window.addEventListener("resize", resized);
  window.addEventListener("pageshow", resized);
  reduced.addEventListener("change", () => { manual(0); resized(); });
  if ("ResizeObserver" in window) new ResizeObserver(resized).observe(document.body);
  schedule();
})();
