/**
 * Capture the static room and wall-box reveal images from the site's WebGL scene.
 * Requires Node.js 22+ and a Chromium browser with headless WebGL support.
 * Run: node tools/capture_room_posters.mjs "/path/to/chrome" [output-directory]
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
const [executable, output = join(docs, "assets", "room")] = process.argv.slice(2);
if (!executable) throw new Error('Pass the path to a Chromium browser executable.');
const types = { ".js": "text/javascript", ".webp": "image/webp", ".bin": "application/octet-stream" };
const preview = `<!doctype html><meta charset="utf-8"><style>
  *{margin:0}body{background:#151413}#room-stage,#room-canvas{position:fixed;inset:0;width:100%;height:100%}
  .model-wrap{position:fixed;top:10%;left:35%;width:64%;aspect-ratio:1056/864}
  </style><div class="model-wrap"></div><div id="room-stage"><canvas id="room-canvas"></canvas></div>
  <script src="room.js"></script>`;
const server = createServer(async (request, response) => {
  const path = new URL(request.url, "http://localhost").pathname;
  if (path === "/") {
    response.writeHead(200, { "Content-Type": "text/html" }).end(preview);
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
  for (const [format, width, height] of [["wide", 1536, 864], ["tall", 540, 1080]]) {
    await command("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    await command("Page.navigate", { url: "http://127.0.0.1:" + server.address().port + "/" });
    let ready = false;
    for (let i = 0; i < 160 && !ready; i++) {
      await delay(100);
      ready = await evaluate('window.NultraRoom?.getState().renderer === "webgl"');
    }
    if (!ready) throw new Error("The " + format + " WebGL room did not load. Check its source assets.");
    const poses = [["open", 0, null], ["off", .24, false], ["lit", .37, true], ["detail", .47, true],
      ["release", .612, true], ["detached", .755, true], ["detached-dark", .755, false]];
    for (const [name, progress, lamp] of poses) {
      await evaluate(`window.NultraRoom.setState(${progress}, ${lamp}); new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)))`);
      const shot = await command("Page.captureScreenshot", { format: "webp", quality: 88, fromSurface: true });
      const file = join(output, name + "-" + format + ".webp");
      await writeFile(file, Buffer.from(shot.data, "base64"));
      console.log(basename(file));
    }
  }
} finally {
  browser.kill();
  await ended;
  server.closeAllConnections();
  server.close();
  if (dirname(profile) === resolve(tmpdir()) && basename(profile).startsWith("nultra-poster-"))
    await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 250 });
}
