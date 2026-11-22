(() => {
  const demos = [...document.querySelectorAll("[data-feature-demo]")];
  const app = document.querySelector("[data-app-scene]");
  const choices = [...document.querySelectorAll("[data-app-select]")];
  if (!app || !choices.length) return;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const appStages = [
    { name: "rename", choice: "rename", duration: 2450, description: "The rename field changes the switch name from DESKLAMP to READLAMP." },
    { name: "saved", choice: "rename", duration: 1150, description: "The switch detail screen now shows the saved name READLAMP." },
    { name: "battery", choice: "battery", duration: 2700, description: "The switch detail screen shows READLAMP with a battery reading of 5 percent." },
    { name: "alert", choice: "alert", duration: 0, description: "A Nultra notification reports that READLAMP has reached 5 percent battery." },
  ];
  const reducedPoses = {
    press: [[0, "ready"], [420, "contact"], [1050, "released"]],
    hold: [[0, "ready"], [350, "contact"], [3350, "released"]],
    service: [[0, "closed"], [680, "open"], [1480, "cell"], [2450, "open"], [3200, "closed"]],
  };
  const poseTimers = new Map();
  let appStage = -1;
  let appVisible = false;
  let appMode = "auto";
  let timer = 0;

  function displayAppStage(index) {
    appStage = index;
    const stage = appStages[index];
    app.dataset.appScene = stage.name;
    app.querySelector(".demo-phone").setAttribute("aria-label", stage.description);
    for (const button of choices) {
      button.setAttribute("aria-pressed", String(button.dataset.appSelect === stage.choice));
    }
    scheduleAppStage();
  }

  function scheduleAppStage() {
    window.clearTimeout(timer);
    if (!appVisible || document.hidden || appStage < 0) return;
    const stage = appStages[appStage];
    if (reducedMotion.matches && appMode === "auto") return;
    if (stage.duration && (appMode !== "selected" || stage.name === "rename")) {
      timer = window.setTimeout(() => displayAppStage(appStage + 1), stage.duration);
    }
  }

  function clearPoses(demo) {
    for (const id of poseTimers.get(demo) || []) window.clearTimeout(id);
    poseTimers.delete(demo);
    delete demo.dataset.pose;
  }

  function playDemo(demo) {
    clearPoses(demo);
    if (reducedMotion.matches) {
      const steps = reducedPoses[demo.dataset.featureDemo];
      demo.dataset.pose = steps[0][1];
      poseTimers.set(demo, steps.slice(1).map(([delay, pose]) =>
        window.setTimeout(() => { demo.dataset.pose = pose; }, delay)));
      return;
    }
    demo.classList.remove("demo-started");
    // Commit the resting pose before restarting an animation already on screen.
    getComputedStyle(demo.querySelector(".gesture-hand, .service-face")).animationName;
    demo.classList.add("demo-started");
    demo.querySelector("animate")?.beginElement();
  }

  for (const demo of demos) {
    const replay = demo.querySelector(".feature-replay");
    replay.hidden = false;
    replay.addEventListener("click", () => playDemo(demo));
  }
  for (const button of choices) {
    button.addEventListener("click", () => {
      appMode = "selected";
      displayAppStage(appStages.findIndex(stage => stage.name === button.dataset.appSelect));
    });
  }
  choices[0].parentElement.hidden = false;
  const appReplay = app.querySelector("[data-app-replay]");
  appReplay.hidden = false;
  appReplay.addEventListener("click", () => {
    appMode = "replay";
    app.dataset.appScene = "preview";
    getComputedStyle(app.querySelector(".demo-input span")).animationName;
    displayAppStage(0);
  });

  function setVisible(element, visible) {
    if (element === app) {
      appVisible = visible;
      if (visible && appStage < 0 && !reducedMotion.matches) displayAppStage(0);
      else scheduleAppStage();
      return;
    }
    element.classList.toggle("demo-visible", visible);
    const hand = element.querySelector(".gesture-hand");
    if (visible && !reducedMotion.matches) {
      hand?.unpauseAnimations();
      if (!element.classList.contains("demo-started")) playDemo(element);
    } else {
      hand?.pauseAnimations();
    }
  }

  reducedMotion.addEventListener("change", () => {
    for (const demo of demos) {
      clearPoses(demo);
      if (reducedMotion.matches) {
        demo.classList.remove("demo-started");
        demo.querySelector("animate")?.endElement();
      }
      setVisible(demo, demo.classList.contains("demo-visible"));
    }
    appMode = "auto";
    setVisible(app, appVisible);
  });
  document.addEventListener("visibilitychange", scheduleAppStage);
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) setVisible(entry.target, entry.intersectionRatio >= .3);
    }, { threshold: [0, .3] });
    for (const element of [...demos, app]) observer.observe(element);
  } else {
    for (const element of [...demos, app]) setVisible(element, true);
  }
})();
