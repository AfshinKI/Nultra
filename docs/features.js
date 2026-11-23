(() => {
  const demos = [...document.querySelectorAll("[data-feature-demo]")];
  const app = document.querySelector("[data-app-scene]");
  const phone = app?.querySelector(".demo-phone");
  const choices = [...document.querySelectorAll("[data-app-select]")];
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const inView = new Set();

  const appStages = [
    { name: "detail", choice: "rename", duration: 620, description: "The switch detail screen shows DESKLAMP and its Rename button." },
    { name: "rename", choice: "rename", duration: 2200, description: "The rename field changes the switch name from DESKLAMP to READLAMP." },
    { name: "saved", choice: "rename", duration: 1150, description: "The switch detail screen now shows the saved name READLAMP." },
    { name: "battery", choice: "battery", duration: 2300, description: "The switch detail screen shows READLAMP with a battery reading of 5 percent." },
    { name: "alert", choice: "alert", duration: 0, description: "A Nultra notification reports that READLAMP has reached 5 percent battery." },
  ];
  let appStage = -1;
  let appMode = "auto";
  let timer = 0;
  let deadline = 0;
  let remaining = 0;

  function displayAppStage(index) {
    clearTimeout(timer);
    timer = 0;
    appStage = index;
    const stage = appStages[index];
    remaining = stage.duration;
    app.dataset.appScene = stage.name;
    phone.setAttribute("aria-label", stage.description);
    for (const button of choices) {
      button.setAttribute("aria-pressed", String(button.dataset.appSelect === stage.choice));
    }
    syncPlayback(app);
  }

  function updateAppPlayback(visible) {
    if (timer) {
      clearTimeout(timer);
      timer = 0;
      remaining = Math.max(0, deadline - performance.now());
    }
    const playing = visible && !(reducedMotion.matches && appMode === "auto");
    app.classList.toggle("app-playing", playing);
    if (!playing) return;
    if (appStage < 0) {
      displayAppStage(0);
      return;
    }
    const stage = appStages[appStage];
    const editingName = stage.name === "detail" || stage.name === "rename";
    if (!stage.duration || (appMode === "selected" && !editingName)) return;
    deadline = performance.now() + remaining;
    timer = window.setTimeout(() => displayAppStage(appStage + 1), remaining);
  }

  function syncPlayback(element) {
    const visible = inView.has(element) && !document.hidden;
    if (element === app) {
      updateAppPlayback(visible);
      return;
    }
    const playing = visible && !reducedMotion.matches;
    element.classList.toggle("demo-visible", playing);
    const video = element.querySelector("video");
    if (!video) return;
    if (playing) {
      // A rapid scroll can pause the film before its pending play request resolves.
      video.play().catch(() => {});
    } else {
      video.pause();
    }
  }

  if (app && choices.length) {
    for (const button of choices) {
      button.addEventListener("click", () => {
        appMode = "selected";
        displayAppStage(appStages.findIndex(stage => stage.choice === button.dataset.appSelect));
      });
    }
    choices[0].parentElement.hidden = false;
    const replay = app.querySelector("[data-app-replay]");
    replay.hidden = false;
    replay.addEventListener("click", () => {
      appMode = "replay";
      displayAppStage(0);
    });
  }

  const scenes = app ? [...demos, app] : demos;
  function syncAll() {
    for (const scene of scenes) syncPlayback(scene);
  }
  reducedMotion.addEventListener("change", syncAll);
  document.addEventListener("visibilitychange", syncAll);
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(entries => {
      for (const {target, isIntersecting, intersectionRatio} of entries) {
        const scene = target === phone ? app : target;
        const visible = isIntersecting && (scene !== app || intersectionRatio >= .25);
        if (visible) inView.add(scene);
        else inView.delete(scene);
        syncPlayback(scene);
      }
    }, {threshold: [0, .25]});
    for (const demo of demos) observer.observe(demo);
    if (phone) observer.observe(phone);
  } else {
    for (const scene of scenes) inView.add(scene);
    syncAll();
  }
})();
