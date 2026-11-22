/**
 * Capture the static room and wall-box reveal images from the site's WebGL scene.
 * Requires Node.js 22+ and a Chromium browser with headless WebGL support.
 * Run: node tools/capture_room_posters.mjs "/path/to/chrome" [room-output-directory]
 * The temporary preview binds to loopback. Browser control uses a private pipe.
 */
import { spawn } from "node:child_process";
import { readFile, mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { basename, dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

const docs = fileURLToPath(new URL("../docs/", import.meta.url));
const [executable, roomOutput] = process.argv.slice(2);
const output=roomOutput || join(docs,"assets","room");
if (!executable) throw new Error('Pass the path to a Chromium browser executable.');
const types = { ".js": "text/javascript", ".webp": "image/webp", ".bin": "application/octet-stream" };
const preview = wall => `<!doctype html><meta charset="utf-8"><style>
  *{margin:0}html,body{background:transparent}#room-stage,#room-canvas{position:fixed;inset:0;width:100%;height:100%}
  .model-wrap{position:fixed;top:10%;left:35%;width:64%;aspect-ratio:1056/864}
  </style><div class="model-wrap"></div><div id="room-stage"><canvas id="room-canvas" ${wall ? 'data-capture-wall' : ''}></canvas><span class="wall-battery-pin" hidden></span></div>
  <script src="room.js"></script>`;
const server = createServer(async (request, response) => {
  const path = new URL(request.url, "http://localhost").pathname;
  if (path === "/") {
    const wall=new URL(request.url,"http://localhost").searchParams.has("wall");
    response.writeHead(200, { "Content-Type": "text/html" }).end(preview(wall));
    return;
  }
  const file = resolve(docs, "." + path);
  if (!file.startsWith(resolve(docs) + sep) || !types[extname(file)]) {
    response.writeHead(404).end();
    return;
  }
  try {
    const data = await readFile(file);
    response.writeHead(200, { "Content-Type": types[extname(file)] }).end(data);
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const profile = await mkdtemp(join(tmpdir(), "nultra-poster-"));
const browser = spawn(executable, ["--headless=new", "--no-first-run", "--no-default-browser-check",
  "--remote-debugging-pipe",
  "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--user-data-dir=" + profile, "about:blank"
], { stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"], windowsHide: true });
const ended = new Promise(resolve => browser.once("close", resolve));
try {
  let id = 0, buffer = "", sessionId;
  const pending = new Map();
  function failPending(error) {
    for (const { reject } of pending.values()) reject(error);
    pending.clear();
  }
  browser.on("error", failPending);
  browser.stdio[3].on("error", failPending);
  browser.stdio[4].setEncoding("utf8").on("data", chunk => {
    const messages = (buffer + chunk).split("\0");
    buffer = messages.pop();
    for (const message of messages) {
      const reply = JSON.parse(message), item = pending.get(reply.id);
      if (!item) continue;
      pending.delete(reply.id);
      if (reply.error) item.reject(new Error(reply.error.message)); else item.resolve(reply.result);
    }
  });
  browser.once("exit", () => failPending(new Error("Chromium closed before completing the capture.")));
  function command(method, params = {}) {
    const request = ++id;
    return new Promise((resolve, reject) => {
      pending.set(request, { resolve, reject });
      browser.stdio[3].write(JSON.stringify({ id: request, method, params, sessionId }) + "\0");
    });
  }
  const { targetId } = await command("Target.createTarget", { url: "about:blank" });
  ({ sessionId } = await command("Target.attachToTarget", { targetId, flatten: true }));
  async function evaluate(expression) {
    const reply = await command("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (reply.exceptionDetails) throw new Error(reply.exceptionDetails.text);
    return reply.result.value;
  }
  await mkdir(output, { recursive: true });
  await command("Emulation.setDefaultBackgroundColorOverride",{color:{r:0,g:0,b:0,a:0}});
  async function openScene(width,height,wall=false) {
    await command("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    await command("Page.navigate", { url: "http://127.0.0.1:" + server.address().port + "/" + (wall?"?wall":"") });
    let ready = false;
    for (let i = 0; i < 160 && !ready; i++) {
      await delay(100);
      ready = await evaluate('window.NultraRoom?.getState().renderer === "webgl"');
    }
    if (!ready) throw new Error("The WebGL room did not load. Check its source assets.");
  }
  async function capture(file,progress,lamp) {
    await evaluate(`window.NultraRoom.setState(${progress}, ${lamp}); new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)))`);
    const shot = await command("Page.captureScreenshot", { format: "webp", quality: 89, fromSurface: true });
    await writeFile(file, Buffer.from(shot.data, "base64"));
    console.log(basename(file));
  }
  // The lightweight WebGL posters are the immediate fallback while the photographic atlas decodes.
  // A second, bare-wall capture lets the same photographs appear with WebGL disabled.
  const registration={};
  const poses = [["open",0,null],["off",.089,false],["lit",.137,true],["detail",.178,true],
    ["approach",.238,true],["approach-dark",.238,false],["release",.303,true],["mounted",.39,true],
    ["screws",.478,true],["detached",.53,true],["detached-dark",.53,false],["focus",.561,true],
    ["cell",.622,true],["exploded",.684,true],["board",.718,true]];
  for (const [format,width,height] of [["wide",1536,864],["tall",540,1080],["compact",320,425]]) {
    registration[format]={};
    await openScene(width,height);
    for(const [name,progress,lamp] of poses){
      await capture(join(output,name+"-"+format+".webp"),progress,lamp);
      const points=await evaluate("window.NultraRoom.getState()");
      registration[format][name]={mount:points.mountPoints,battery:points.batteryPoint};
    }
    await openScene(width,height,true);
    for(const [name,progress,lamp] of poses.filter(([name])=>!["open","lit","cell","exploded","board"].includes(name))){
      await capture(join(output,"wall-"+name+"-"+format+".webp"),progress,lamp);
    }
  }
  await writeFile(join(output,"registration.json"),JSON.stringify(registration,(_,v)=>typeof v==="number"?Number(v.toFixed(6)):v)+"\n");
} finally {
  browser.kill();
  await ended;
  server.closeAllConnections();
  server.close();
  if (dirname(profile) === resolve(tmpdir()) && basename(profile).startsWith("nultra-poster-"))
    await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 250 });
}
