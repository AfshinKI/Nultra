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
  const hardwareStart = .777;
  const firstFrame = 132;
  const handoffStart = .751;
  const lampDemoEnd = .14;
  // Each leg ends at a change in the subject being shown. Durations leave time to read the callouts.
  const tourLegs = [
    {end: .237, duration: 3000},     // Track the installed switch.
    {end: .345, duration: 3600},     // Peel the magnetic cover away from the carrier.
    {end: .434, duration: 5700},     // Read the seated AA and its discharge profile.
    {end: .561, duration: 3750},     // Back out the fasteners, then move the switch forward.
    {end: .626, duration: 1900},     // Take the AA out of its contacts.
    {end: hardwareStart, duration: 3950}, // Open the shell and settle on the PCB.
    {end: .815, duration: 3450},     // Expose the board and its debug pads.
    {end: .868, duration: 2700},     // Antenna and Bluetooth CPU.
    {end: .933, duration: 1600},     // Turn to the reverse side.
    {end: .962, duration: 1650},     // Bring the rear components into view together.
    {end: 1, duration: 3400},        // Finish the rear camera move slowly while the labels are readable.
  ];
  const boxRevealStart = .346, boxRevealEnd = .434;
  const lastFrame = 232;
  const atlasVersion = "?v=233b";
  const framesPerSheet = 4;
  const tileWidth = 1056;
  const tileHeight = 864;
  const sheetOf = frame => Math.floor(frame / framesPerSheet);
  // The room renderer reaches the same projected board pose as the first inspection tile.
  const beats = [
    [hardwareStart, firstFrame], [.80, 140], [.815, 146], [.868, 164], [.933, 204], [.962, 216], [1, lastFrame],
  ];
  function interpolate(stops, value, from) {
    const to = 1 - from;
    if (value <= stops[0][from]) return stops[0][to];
    for (let i = 1; i < stops.length; i++) {
      const before = stops[i - 1], after = stops[i];
      if (value > after[from]) continue;
      const part = (value - before[from]) / (after[from] - before[from]);
      return before[to] + (after[to] - before[to]) * part;
    }
    return stops[stops.length - 1][to];
  }
  const frameAt = progress => Math.round(interpolate(beats, progress, 0) * 1e7) / 1e7;
  const positionAt = frame => interpolate(beats, frame, 1);
  const sheets = new Map();
  const pending = new Set();
  const retries = new Map();
  const labels = document.getElementById("sequence-labels");
  const labelGroups = Array.from(labels?.querySelectorAll("[data-label-group]") || [], element => ({
    element,
    parts: Array.from(element.querySelectorAll("[data-part]"), part => ({
      part, key: part.dataset.part, line: part.querySelector("path"), dot: part.querySelector("circle"),
      text: part.querySelector("text"), bounds: null,
    })),
  }));
  const tabs = Array.from(sequence.querySelectorAll("[data-chapter-at]"));
  const copies = sequence.querySelectorAll("[data-chapter-copy]");
  const lampButton = sequence.querySelector("[data-room-lamp]");
  const roomIntro = room.querySelector(".room-intro");
  const lampText = lampButton?.querySelector("[data-room-action-text]");
  const mast = document.querySelector(".mast");
  const descriptions = [
    "Nultra switch mounted on the wall beside the desk lamp.",
    "The faceplate lifts from its magnets to reveal the AA cell and two mounting screws.",
    "The uncovered switch moves forward. The AA lifts out, then the carrier and rear shell separate from the circuit board.",
    "Both sides of the populated circuit board.",
  ];
  const inspectionDescriptions = {
    debug: "The circuit board moves forward, exposing the debug pads.",
    board: "The front of the board carries the printed antenna, Bluetooth microcontroller and SWD debug pads.",
    turn: "The circuit board turns to show its reverse side.",
    power: "The rear-side DC/DC converter raises the AA cell voltage for the electronics.",
    relay: "The reverse of the board carries the DC/DC converter, latching relay and AC load screw terminal.",
  };

  let target = 0, position = 0, drawnFrame = firstFrame;
  let pendingSeek = false;
  let chapter = -1, lastPercent = -1, lastRoomProgress = -1;
  let lampOverride, lampAt = 0, lastLampState, lastOverride;
  let anchors, anchorsPending = false, anchorRetry = 0, anchorFailures = 0;
  let networkTimer = 0, wakeAt = Infinity;
  let wantedSheets = [];
  let start = 0, span = 0, bottom = 0, inView = true;
  let measureNeeded = true, scrollChanged = true, resetPosition = true;
  let raf = 0, previousTime = 0, direction = 1, backingWidth = canvas.width;
  const historyReturn = performance.getEntriesByType?.("navigation")[0]?.type === "back_forward";
  let introState = motion.matches || location.hash || historyReturn ? "done" : "waiting";
  let introElapsed = 0, introTime = 0, introOrigin = 0;
  let tourLeg = 0, afterHold;
  let holdTimer = 0, holdSince = 0, holdRemaining = 0;

  function smooth(value) {
    const t = clamp(value);
    return t * t * (3 - 2 * t);
  }

  function windowOpacity(value, from, to, endFrom, endTo) {
    return Math.min(smooth((value - from) / (to - from)), 1 - smooth((value - endFrom) / (endTo - endFrom)));
  }

  const labelOpacity = {
    board: frame => windowOpacity(frame, 134, 138, 155, 160),
    relay: frame => smooth((frame - 208) / 5),
  };
  const productLabels = Object.values(labelOpacity);
  function readingWeight(progress) {
    if (progress < hardwareStart) {
      const {magnet=0,battery=0} = window.NultraRoom?.detailWeights(progress) || {};
      return Math.max(magnet,battery,window.NultraRoom?.switchLabelOpacity(progress) ?? 0);
    }
    const frame = frameAt(progress);
    // Overlapping labels share one reading interval.
    return productLabels.reduce((weight, opacity) => Math.max(weight, opacity(frame)), 0);
  }

  // The last few degrees of the rear orbit ease into a small push-in before the pin releases.
  const closingMove = frame => smooth((frame - 208) / (lastFrame - 208));

  // Integrate the fades once. The same curve maps native scrolling to a shot and a direct seek back to scrollY.
  const scrollStops = [[0, 0]];
  const intervals = 256;
  let distance = 0;
  for (let i = 1; i <= intervals; i++) {
    const progress = (i - .5) / intervals;
    distance += 1 + .45 * readingWeight(progress) + 3 * closingMove(frameAt(progress));
    scrollStops.push([i / intervals, distance]);
  }
  for (const stop of scrollStops) stop[1] /= distance;
  const scrollAt = progress => interpolate(scrollStops, progress, 0);
  const progressAtScroll = fraction => interpolate(scrollStops, fraction, 1);

  function leaderPath(box, px, py) {
    // Connect from the nearest outside edge, leaving breathing room around every line of text.
    const left = box.x - 10, right = box.x + box.width + 10;
    const top = box.y - 8, bottom = box.y + box.height + 8;
    const x = Math.max(left, Math.min(right, px)), y = Math.max(top, Math.min(bottom, py));
    const dx = px - x, dy = py - y;
    if (!dx && !dy) return "";
    const horizontal = Math.abs(dx) > Math.abs(dy);
    const elbowX = x + (horizontal ? Math.sign(dx) * Math.min(18, Math.abs(dx)) : 0);
    const elbowY = y + (horizontal ? 0 : Math.sign(dy) * Math.min(18, Math.abs(dy)));
    return `M ${x} ${y} L ${elbowX} ${elbowY} L ${px} ${py}`;
  }

  function measureLabels() {
    for (const {parts} of labelGroups) {
      for (const label of parts) label.bounds = label.text.getBBox();
    }
    renderLabels(drawnFrame);
  }

  function renderLabels(frame) {
    if (!labels) return;
    const lo = Math.floor(frame), hi = Math.ceil(frame), fraction = frame - lo;
    const current = anchors?.[lo], next = anchors?.[hi];
    labels.style.opacity = current ? "1" : "0";
    if (!current) return;
    const area = labels.viewBox.baseVal;
    function point(key) {
      const a = current[key], b = next?.[key] || a;
      if (!Array.isArray(a) || !Array.isArray(b)) return null;
      const x = (a[0] + (b[0] - a[0]) * fraction) * area.width;
      const y = (a[1] + (b[1] - a[1]) * fraction) * area.height;
      return x >= 0 && y >= 0 && x <= area.width && y <= area.height ? {x, y} : null;
    }
    for (const {element, parts} of labelGroups) {
      const opacity = labelOpacity[element.dataset.labelGroup]?.(frame) ?? 0;
      element.style.opacity = String(opacity);
      if (!opacity) continue;
      for (const {part, key, line, dot, text, bounds} of parts) {
        const target = point(key);
        part.style.visibility = target ? "visible" : "hidden";
        if (!target) continue;
        line.setAttribute("d", leaderPath(bounds || text.getBBox(), target.x, target.y));
        dot.setAttribute("cx", target.x);
        dot.setAttribute("cy", target.y);
      }

    }
  }

  function retryTime(failures) {
    return performance.now() + Math.min(30000, 2000 * 2 ** Math.min(failures - 1, 4));
  }

  function wakeForNetwork(time) {
    if (document.hidden || !inView || navigator.onLine === false || time >= wakeAt) return;
    if (networkTimer) window.clearTimeout(networkTimer);
    wakeAt = time;
    networkTimer = window.setTimeout(() => {
      networkTimer = 0;
      wakeAt = Infinity;
      schedule();
    }, Math.max(1, time - performance.now()));
  }

  async function loadAnchors() {
    if (!labels || anchors || anchorsPending || navigator.onLine === false) return;
    if (performance.now() < anchorRetry) { wakeForNetwork(anchorRetry); return; }
    anchorsPending = true;
    try {
      const response = await fetch("assets/product/motion/anchors.json" + atlasVersion + "-2");
      if (!response.ok) throw new Error("Missing callouts");
      anchors = await response.json();
      renderLabels(drawnFrame);
    } catch {
      anchorRetry = retryTime(++anchorFailures);
      wakeForNetwork(anchorRetry);
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

  function requestSheet(index, required) {
    if (index < sheetOf(firstFrame) || index > sheetOf(lastFrame) || sheets.has(index) || pending.has(index) || navigator.onLine === false) return;
    const retry = retries.get(index);
    if (retry && retry.time > performance.now()) {
      if (required) wakeForNetwork(retry.time);
      return;
    }
    pending.add(index);
    const image = new Image();
    image.decoding = "async";
    image.src = "assets/product/motion/" + String(index).padStart(3, "0") + ".webp" + atlasVersion;
    image.decode().then(() => {
      sheets.set(index, image);
      retries.delete(index);
      trimSheets();
    }).catch(() => {
      const failures = (retry?.failures || 0) + 1;
      retries.set(index, {failures, time: retryTime(failures)});
    }).finally(() => {
      pending.delete(index);
      schedule();
    });
  }

  function buffer(frame) {
    if (!inView || document.hidden || Math.max(position, target) < .70) return;
    const limited = saveData || motion.matches;
    const concurrency = limited ? 1 : 2;
    const low = sheetOf(Math.floor(frame)), high = sheetOf(Math.ceil(frame));
    const candidates = [low, high];
    const ahead = direction > 0 ? high : low;
    if (!limited && (frame > firstFrame || target > hardwareStart)) {
      candidates.push(ahead + direction, ahead + 2 * direction);
    } else if (saveData && !motion.matches && !pendingSeek && position !== target) {
      // One in flight. Fetch an adjacent sheet only if the scroll target already requires it.
      const destination = sheetOf(Math.round(frameAt(target)));
      if ((destination - ahead) * direction > 0) candidates.push(ahead + direction);
    }
    wantedSheets = [...new Set(candidates)].slice(0, limited ? 2 : 3);
    for (const index of wantedSheets) {
      if (pending.size >= concurrency) break;
      requestSheet(index, frame > firstFrame && (index === low || index === high));
    }
    loadAnchors();
  }

  function tile(frame) {
    return frame === firstFrame && poster.complete && poster.naturalWidth ? poster : sheets.get(sheetOf(frame));
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
    if (frame === firstFrame) {
      pendingSeek = false;
      sizeCanvas();
      if (drawnFrame !== firstFrame) {
        canvas.style.opacity = "0";
        poster.style.opacity = "1";
        drawnFrame = firstFrame;
        renderLabels(firstFrame);
      }
      return;
    }
    const lo = Math.floor(frame), hi = Math.ceil(frame);
    const imageA = tile(lo), imageB = tile(hi);
    if (!imageA || !imageB) return;
    pendingSeek = false;
    const fraction = hi === lo ? 0 : frame - lo;
    const actual = lo + fraction;
    if (!sizeCanvas() && Math.abs(actual - drawnFrame) < .002) return;
    if (actual > firstFrame) {
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
    canvas.style.opacity = actual > firstFrame ? "1" : "0";
    poster.style.opacity = actual > firstFrame ? "0" : "1";
    drawnFrame = actual;
    renderLabels(actual);
  }

  function renderRoom(progress) {
    const lit = lampOverride ?? progress >= .36 * .37;
    if (progress !== lastRoomProgress || lit !== lastLampState || lampOverride !== lastOverride) {
      window.NultraRoom?.setState(progress, lampOverride);
      sequence.style.setProperty("--room-progress", String(progress/.37));
      if (roomIntro) roomIntro.inert = progress >= .59*.37;
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

  function render(requestedFrame = frameAt(position)) {
    const mix = smooth((position - handoffStart) / (hardwareStart - handoffStart));
    sequence.style.setProperty("--room-opacity", String(1 - mix));
    // The room sits above the matched hardware pose. An opaque base avoids a dark dip in the dissolve.
    sequence.style.setProperty("--hardware-opacity", position >= handoffStart ? "1" : "0");
    room.inert = mix >= .5;
    hardware.inert = mix < .5;
    renderRoom(Math.min(position,hardwareStart));
    const frame = frameAt(position);
    buffer(requestedFrame);
    paint(frame);
    sequence.style.setProperty("--closing-scale", String(1 + .024 * closingMove(drawnFrame)));
    const batteryProgress = smooth((position - .348) / (.387 - .348));
    sequence.style.setProperty("--battery-life-progress", String(batteryProgress));
    const active = position < .237 ? 0 : position < .512 ? 1 : position < .751 ? 2 : 3;
    if (chapter !== active) {
      chapter = active;
      sequence.dataset.chapter = String(active);
      tabs.forEach((button, i) => button.setAttribute("aria-pressed", String(i === active)));
      copies.forEach(copy => { copy.hidden = Number(copy.dataset.chapterCopy) !== active; });
    }
    const shot = drawnFrame < 134 ? "debug" : drawnFrame < 164 ? "board" :
      drawnFrame < 204 ? "turn" : drawnFrame < 208 ? "power" : "relay";
    const inspection = active === 3 ? shot : "";
    if (sequence.dataset.inspection !== inspection) sequence.dataset.inspection = inspection;
    const description = inspection ? inspectionDescriptions[inspection] : descriptions[active];
    if (poster.alt !== description) poster.alt = description;
    const number = Math.round(position * 100);
    if (number !== lastPercent || slider.dataset.chapter !== String(active)) {
      lastPercent = number;
      slider.dataset.chapter = String(active);
      slider.value = String(number);
      const wallView = [
        [.237,.346,"Magnetic faceplate lifting from its three attachment points"],
        [boxRevealStart,boxRevealEnd,"AA battery seated in the switch, held in its wall box by two screws"],
        [.434,.494,"Two mounting screws backing out of the carrier"],
        [.494,.562,"Uncovered switch moving out of its wall box"],
        [.562,.626,"AA battery lifting out of the carrier"],
        [.626,.751,"Exploded battery, carrier, circuit board and rear shell"],
      ].find(([from,to])=>position>=from&&position<to);
      const view = wallView?.[2] || tabs[active]?.textContent.trim() || "";
      slider.setAttribute("aria-valuetext", view + ", " + number + "%");
      if (percent) percent.value = number + "%";
      sequence.style.setProperty("--sequence-progress", String(position));
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
    measureLabels();
    measureNeeded = false;
  }

  function updateTarget(value, instant) {
    const next = clamp(value);
    if (pendingSeek && !instant && !motion.matches) {
      // Ignore the subpixel rounding of our own scrollTo while a direct seek decodes.
      if (Math.abs(next - position) < Math.max(.0001, 1 / Math.max(span, 1))) return;
      pendingSeek = false;
      position = drawnFrame > firstFrame ? positionAt(drawnFrame) : Math.min(position, hardwareStart);
    }
    if (next !== position) direction = Math.sign(next - position);
    target = next;
    if (lampOverride !== undefined && Math.abs(target - lampAt) > .055) lampOverride = undefined;
    if (instant || motion.matches) {
      position = target;
      pendingSeek = true;
    }
  }

  function advance(dt, speedLimit) {
    if (position === target) return frameAt(position);
    const remaining = target - position;
    direction = Math.sign(remaining);
    const eased = Math.abs(remaining) * (1 - Math.exp(-dt / 60));
    // A quick wheel or touch gesture can outrun the renderer. Catch up to its destination without adding a stop.
    const catchUp = speedLimit === undefined ? smooth((Math.abs(remaining) - .025) / .16) : 0;
    const speed = speedLimit ?? (.00075 + .00070 * catchUp);
    const step = Math.min(eased, dt * speed, .012 + .022 * catchUp);
    let next = Math.abs(remaining) < .00012 ? target : position + direction * step;
    let frame = frameAt(next);
    // Keep the visual step bounded even after a long task or an abruptly reversed fling.
    const maxFrames = Math.min(1.75 + 2.25 * catchUp, dt * (.09 + .13 * catchUp));
    if (Math.abs(frame - drawnFrame) > maxFrames) {
      frame = drawnFrame + direction * maxFrames;
      next = positionAt(frame);
    }
    if (frame > firstFrame && (!tile(Math.floor(frame)) || !tile(Math.ceil(frame)))) {
      // Finish the available edge pose, then let the missing sheet's decode wake the player.
      const edge = direction > 0 ? Math.ceil(drawnFrame + .00001) : Math.floor(drawnFrame - .00001);
      if ((frame - edge) * direction >= 0 && edge >= 0 && tile(edge)) position = positionAt(edge);
      return frame;
    }
    position = next;
    return frame;
  }

  function introOwnsTimeline() {
    return introState !== "done" && introState !== "waiting";
  }

  function setIntroState(state) {
    introState = state;
    sequence.classList.toggle("is-rewinding", state === "tour-rewind" || state === "rewinding");
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
      setIntroState(afterHold);
      introElapsed = 0;
      introTime = 0;
      schedule();
    }, holdRemaining);
  }

  function holdIntro(nextState, duration) {
    setIntroState("holding");
    afterHold = nextState;
    holdRemaining = duration;
    scheduleHold();
  }

  function stopIntro(alignScroll) {
    if (introState === "done") return;
    const wasPlaying = introOwnsTimeline();
    pauseHold();
    setIntroState("done");
    introTime = 0;
    window.removeEventListener("wheel", takeWheel, true);
    for (const type of takeoverInputs) window.removeEventListener(type, takeControl, true);
    if (!wasPlaying) return;
    target = position;
    previousTime = 0;
    if (alignScroll && span > 0 && !motion.matches && inView) {
      // Both coordinates paint the same pinned view. Align before the native wheel/touch/key action.
      const aligned = start + span * scrollAt(position);
      if (Math.abs(window.scrollY - aligned) > .5) window.scrollTo({top: aligned, behavior: "instant"});
    }
  }

  function advanceIntro(dt, end, speed) {
    // Reuse the scroll player's decode buffer in both directions. A missing sheet's decode wakes the player.
    const previous = position;
    target = end;
    render(advance(dt, speed));
    if (position !== previous) schedule();
    return position === end;
  }

  function playIntro(time) {
    if (introState === "stepping") {
      // A visitor who requests Replay with reduced motion sees stills of each action.
      const stops = [0, .14, .303, .415, .478, .561, .622, .684, .815, 1];
      target = position = stops[tourLeg++];
      render();
      if (tourLeg === stops.length) stopIntro(false);
      else holdIntro("stepping", position === .415 ? 3200 : 1650);
      return true;
    }
    if (introState === "waiting") {
      if (Math.abs(window.scrollY - start) > 3 || !inView || motion.matches) {
        stopIntro(false);
        return false;
      }
      introOrigin = window.scrollY;
      setIntroState("opening");
    }
    if (introState === "holding") {
      scheduleHold();
      render();
      return true;
    }
    if (!introOwnsTimeline()) return false;
    const dt = introTime ? Math.min(60, Math.max(1, time - introTime)) : 16;
    introTime = time;
    if (introState === "tour") {
      const {end, duration} = tourLegs[tourLeg];
      const from = tourLeg ? tourLegs[tourLeg - 1].end : lampDemoEnd;
      // Spend 60% of the usual time between callouts and 113% when a label is fully visible.
      const timeScale = .60 + .53 * readingWeight(position);
      if (advanceIntro(dt, end, (end - from) / (duration * timeScale))) {
        tourLeg++;
        if (tourLeg === tourLegs.length) setIntroState("tour-rewind");
      }
      return true;
    }
    if (introState === "tour-rewind") {
      const reveal = windowOpacity(position, .295, boxRevealStart, boxRevealEnd, .478);
      if (advanceIntro(dt, 0, Math.min(1 / 3600, .00065 / (1 + 6 * reveal)))) holdIntro("playing", 1000);
      return true;
    }

    introElapsed += dt;
    const opening = introState === "opening";
    const forward = introState !== "rewinding";
    const delay = opening ? 350 : forward ? 200 : 0;
    const duration = opening ? 4750 : forward ? 3200 : 2450;
    const elapsed = clamp((introElapsed - delay) / duration);
    position = target = lampDemoEnd * (forward ? smooth(elapsed) : 1 - smooth(elapsed));
    render();
    if (elapsed === 1) {
      if (opening) holdIntro("tour", 1000);
      else if (forward) holdIntro("rewinding", 5000);
      else holdIntro("playing", 1200);
    } else schedule();
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
      if (introState === "done" && span && !motion.matches) updateTarget(progressAtScroll((y - start) / span), resetPosition);
      resetPosition = false;
    }
    if (!inView || playIntro(time)) return;
    const dt = previousTime ? Math.min(60, Math.max(1, time - previousTime)) : 16;
    previousTime = time;
    const previous = position;
    const requestedFrame = advance(dt);
    render(requestedFrame);
    if (position !== target && position !== previous) schedule();
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
      window.scrollTo({top: start + (motion.matches ? 0 : span * scrollAt(target)), behavior: "instant"});
    }
    render();
    schedule();
  }

  function toggleLamp() {
    if (position >= .218) return;
    stopIntro(true);
    lampAt = target;
    lampOverride = !(lampOverride ?? position / .37 >= .36);
    renderRoom(Math.min(position,hardwareStart));
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
  const takeControl = event => {
    if (!event.target?.closest?.("[data-tour-replay]")) stopIntro(true);
  };
  function takeWheel(event) {
    if (introOwnsTimeline() && span && event.cancelable && event.deltaY && !event.ctrlKey) {
      // A compositor can otherwise discard the first upward delta because the physical document is still at zero.
      const unit = event.deltaMode === 2 ? window.innerHeight : event.deltaMode === 1 ? 16 : 1;
      const nextY = start + span * scrollAt(position) + event.deltaY * unit;
      stopIntro(false);
      event.preventDefault();
      window.scrollTo({top: nextY, behavior: "instant"});
      return;
    }
    stopIntro(true);
  }
  function listenForTakeover() {
    window.addEventListener("wheel", takeWheel, {capture:true, passive:false});
    for (const type of takeoverInputs) window.addEventListener(type, takeControl, {capture:true, passive:true});
  }
  if (introState !== "done") listenForTakeover();
  sequence.querySelector("[data-tour-replay]")?.addEventListener("click", () => {
    lampOverride = undefined;
    seek(0, true);
    pendingSeek = false;
    introOrigin = window.scrollY;
    introElapsed = introTime = tourLeg = 0;
    setIntroState(motion.matches ? "stepping" : "opening");
    listenForTakeover();
    schedule();
  });
  window.addEventListener("scroll", () => {
    // Scrollbar and accessibility scrolls can arrive without a preceding input event.
    if (introOwnsTimeline() && Math.abs(window.scrollY - introOrigin) > 1) {
      const nativeY = window.scrollY;
      stopIntro(false);
      if (span && nativeY < bottom && !motion.matches) {
        window.scrollTo({top: nativeY + scrollAt(position) * span, behavior: "instant"});
      }
    }
    scrollChanged = true;
    schedule();
  }, {passive:true});
  window.addEventListener("resize", remeasure);
  window.addEventListener("online", () => {
    if (networkTimer) window.clearTimeout(networkTimer);
    networkTimer = 0;
    wakeAt = Infinity;
    retries.clear();
    anchorFailures = 0;
    anchorRetry = 0;
    schedule();
  });
  window.addEventListener("pageshow", event => {
    if (event.persisted) { stopIntro(false); resetPosition = true; }
    remeasure();
  });
  window.addEventListener("popstate", () => { stopIntro(false); resetPosition = true; remeasure(); });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) pauseHold();
    introTime = 0;
    previousTime = 0;
    remeasure();
  });
  motion.addEventListener("change", () => {
    if (motion.matches) { stopIntro(false); target = position; }
    remeasure();
  });
  if ("ResizeObserver" in window) {
    const observer = new ResizeObserver(remeasure);
    observer.observe(sequence);
    observer.observe(pin);
    if (mast) observer.observe(mast);
  }

  sequence.classList.add("motion-ready");
  document.fonts?.ready.then(measureLabels);
  render();
  schedule();
})();
