// Real-input checks for the demo apps (apps/*.rb): Playwright clicks buttons and types into the
// Swing windows that CheerpJ draws, then reads the app state back through the page REPL.
//
//   ./run.sh test-demos [app]          e.g. ./run.sh test-demos physics
//   SHOTS=/some/dir ./run.sh test-demos   also saves a screenshot per demo
//
// Starts its own serve.py on a free 127.0.0.1 port; each demo gets a fresh browser (cold boot).
import { createRequire } from "node:module";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import net from "node:net";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const DIR = path.dirname(fileURLToPath(import.meta.url));
const only = process.argv[2];
let failures = 0;
const check = (name, ok, detail) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}  -- ${detail}`); if (!ok) failures++; };
const freePort = () => new Promise((res, rej) => {
  const s = net.createServer();
  s.on("error", rej);
  s.listen(0, "127.0.0.1", () => { const p = s.address().port; s.close(() => res(p)); });
});
const portOpen = (port) => new Promise((res) => {
  const s = net.connect(port, "127.0.0.1", () => { s.destroy(); res(true); });
  s.on("error", () => res(false));
});
const PORT = await freePort();
const BASE = `http://127.0.0.1:${PORT}`;
const server = spawn("python3", ["-I", path.join(DIR, "serve.py"), "--port", String(PORT), "--bind", "127.0.0.1", "--quiet"], { stdio: "ignore" });
for (let i = 0; i < 100 && !(await portOpen(PORT)); i++) await new Promise((r) => setTimeout(r, 100));
console.log(`started serve.py on ${BASE} (pid ${server.pid})`);

const HELPER = `
def __all(c) = [c, *(c.respond_to?(:components) ? c.components.flat_map { |k| __all(k) } : [])]
def __find(frame, &pred) = __all(frame.content_pane).find(&pred)
def __at(c) = (pt = c.getLocationOnScreen; [pt.x + c.width / 2, pt.y + c.height / 2])
nil`;
async function withApp(name, fn) {
  if (only && only !== name) return;
  console.log(`--- ${name} ---`);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 1000 } });
  await p.goto(`${BASE}/index.html?app=${name}`);
  await Promise.race([p.evaluate(() => window.jruby.ready), new Promise((_, rej) => setTimeout(() => rej(new Error('boot timeout')), 5 * 60_000))]);
  const log = (await p.textContent('#log')).trim();
  check(`${name}: app started`, !log, log.slice(0, 200) || await p.textContent('#msg'));
  const ev = async (c) => (await p.evaluate(c => window.jruby.eval(c), c)).result;
  await ev(HELPER);
  const d = await p.locator('#display').boundingBox();
  const click = async (expr) => { const [x, y] = JSON.parse((await ev(`__at(${expr})`)).slice(3)); await p.mouse.click(d.x + x, d.y + y); };
  try { await fn({ p, ev, click, d }); } catch (e) { check(name, false, e.message); }
  await p.waitForTimeout(800);
  if (process.env.SHOTS) await p.locator('#display').screenshot({ path: path.join(process.env.SHOTS, `demo-${name}.png`) });
  const c = await p.textContent('#console');
  const errs = c.split('\n').filter(l => /Exception|Error/.test(l));
  check(`${name}: no Java exceptions`, errs.length === 0, errs.slice(0, 2).join(' | ') || 'none');
  await Promise.race([b.close().catch(() => {}), new Promise((r) => setTimeout(r, 5000))]);
}
const btn = (frame, text) => `__find(${frame}) { |c| c.is_a?(javax.swing.AbstractButton) && c.text.to_s.include?(${JSON.stringify(text)}) }`;

await withApp('qr', async ({ p, ev, click }) => {
  await click('QRStudio.studio.input');
  await p.keyboard.press('Control+A'); await p.keyboard.type('Gr', { delay: 20 });
  // ü as a Swiss-German keyboard sends it (Playwright's type() would use IME-style insertText,
  // which CheerpJ ignores).
  const cdp = await p.context().newCDPSession(p);
  await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ü', code: 'BracketLeft', text: 'ü', unmodifiedText: 'ü', windowsVirtualKeyCode: 186 });
  await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'ü', code: 'BracketLeft', windowsVirtualKeyCode: 186 });
  await p.keyboard.type('ezi from Ruby!', { delay: 20 });
  await p.waitForTimeout(1500);
  const r = await ev('QRStudio.studio.instance_variable_get(:@decoded).text');
  check('qr: typed text encodes and decodes', r.includes('Grüezi from Ruby!'), r);
});
await withApp('dice', async ({ p, ev, click }) => {
  await click(btn('Dice.roller.frame', 'Roll 1000'));
  await p.waitForTimeout(1500);
  await click(btn('Dice.roller.frame', 'Roll 100'));
  await p.waitForTimeout(1500);
  const r = await ev('[Dice.roller.total, Dice.roller.counts[7] > Dice.roller.counts[2]]');
  check('dice: Roll buttons roll', r === '=> [1100, true]', r);
});
await withApp('formula', async ({ p, ev, click }) => {
  await click("Formula.solver.instance_variable_get(:@spinners)[:c].editor.text_field");
  await p.keyboard.press('Control+A'); await p.keyboard.type('6'); await p.keyboard.press('Enter');
  await p.waitForTimeout(1200);
  const r = await ev('Formula.solver.quadratic.roots.map { |x| x.class }');
  check('formula: typing c=6 gives complex roots', r === '=> [Complex, Complex]', r);
});
await withApp('sql', async ({ p, ev, click }) => {
  await click('SqlPlayground.playground.editor');
  await p.keyboard.press('Control+A');
  await p.keyboard.type("DB[:cities].where { population > 100_000 }.order(:name).select(:name, :population)", { delay: 5 });
  await p.keyboard.press('Control+Enter');
  await p.waitForTimeout(2000);
  let r = await ev('[SqlPlayground.playground.table.row_count, SqlPlayground.playground.instance_variable_get(:@message).text[0, 80]]');
  check('sql: typed Sequel query + Ctrl+Enter', r.startsWith('=> [6,'), r);
  await click(btn('SqlPlayground.playground.frame', 'SQL'));
  await p.waitForTimeout(800);
  await click(btn('SqlPlayground.playground.frame', 'Run'));
  await p.waitForTimeout(1500);
  r = await ev('[SqlPlayground.playground.table.row_count, SqlPlayground.playground.editor.text[0, 30]]');
  check('sql: SQL mode + Run button', /^=> \[1[45],/.test(r), r);
});
await withApp('physics', async ({ p, ev, click, d }) => {
  await p.waitForTimeout(1500);
  const [x, y] = JSON.parse((await ev('v = Physics.game.view; pt = v.getLocationOnScreen; [pt.x + v.width * 0.65, pt.y + v.height * 0.6]')).slice(3));
  for (let i = 0; i < 3; i++) { await p.mouse.click(d.x + x, d.y + y + i * 20); await p.waitForTimeout(400); }
  await p.waitForTimeout(1500);
  const r = await ev('[Physics.game.sim.balls.size, Physics.game.fps]');
  check('physics: mouse clicks fire balls', r.startsWith('=> [3,'), r);
});
await withApp('polyglot', async ({ p, ev, click }) => {
  await click(btn('Polyglot.app.frame', 'Run JavaScript'));
  await p.waitForTimeout(2500);
  await click(btn('Polyglot.app.frame', 'Run Ruby'));
  await p.waitForTimeout(2500);
  const out = await ev('Polyglot.app.instance_variable_get(:@output).text');
  check('polyglot: Run JS then Run Ruby', out.includes('JS sums the Ruby primes: 129') && out.includes('js.fib(20)     => 6765'), out.slice(0, 120));
});
console.log(failures ? `\n${failures} FAILURE(S)` : '\nALL DEMOS PASSED');
server.kill();
process.exit(failures ? 1 : 0);
