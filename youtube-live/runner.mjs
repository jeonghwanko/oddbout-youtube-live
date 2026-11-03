import { chromium } from 'playwright';
import { existsSync } from 'node:fs';
import { randomInt, randomUUID } from 'node:crypto';

// Agent runner for the exhibition stream: a visible Chrome window on the X display drives
// window.oddboutBroadcast.runCup (protocol 1) cup after cup. It never handles the stream key.
const args = Object.fromEntries(process.argv.slice(2).map(arg => arg.replace(/^--/, '').split(/=(.*)/s).slice(0, 2)));
const url = args.url ?? 'http://127.0.0.1:5178/broadcast.html?lang=en';
const cups = Number(args.cups ?? 0); // 0: until stopped
const gapMs = Number(args['gap-ms'] ?? 15000);
const width = Number(args.width ?? 1920), height = Number(args.height ?? 1080);
if (!Number.isInteger(cups) || cups < 0 || !Number.isFinite(gapMs) || gapMs < 0) throw new Error('Invalid --cups or --gap-ms');

// The nine built-in commands listed in README.md.
const BUILT_IN = ['kuma', 'yume', 'bravow', 'beotim', 'quickcat', 'kungjjak', 'sikeundung', 'duldul', 'eoridung'];
const pickFour = () => {
  const pool = [...BUILT_IN];
  for (let i = pool.length - 1; i > 0; i--) { const j = randomInt(i + 1); [pool[i], pool[j]] = [pool[j], pool[i]]; }
  return pool.slice(0, 4);
};

const channel = args.channel ?? process.env.LIVE_BROWSER_CHANNEL ?? (existsSync('/usr/bin/google-chrome') ? 'chrome' : undefined);
const browser = await chromium.launch({ channel, headless: false,
  args: [`--window-size=${width},${height}`, '--window-position=0,0', '--autoplay-policy=no-user-gesture-required', '--hide-scrollbars'],
  // Keep Chrome's normal background policies, as scripts/test-twitch-cup.mjs does.
  ignoreDefaultArgs: ['--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding', '--enable-automation'],
});
const context = await browser.newContext({ viewport: null });
const page = await context.newPage();
// --kiosk needs a window manager; Xvfb has none, so ask the browser for a fullscreen window instead.
const cdp = await context.newCDPSession(page);
const { windowId } = await cdp.send('Browser.getWindowForTarget');
await cdp.send('Browser.setWindowBounds', { windowId, bounds: { windowState: 'fullscreen' } });
page.on('pageerror', error => console.error(JSON.stringify({ event: 'pageerror', message: error.message })));

let stopping = false;
const stop = async () => { stopping = true; await browser.close().catch(() => {}); process.exit(0); };
process.on('SIGINT', stop); process.on('SIGTERM', stop);

const open = async () => {
  await page.goto(url);
  await page.waitForFunction(() => window.oddboutBroadcast?.protocolVersion === 1, null, { timeout: 60000 });
};
await open();
console.log(JSON.stringify({ event: 'ready', url, browser: browser.version() }));

for (let cup = 1; !stopping && (cups === 0 || cup <= cups); cup++) {
  const input = { jobId: randomUUID(), leaseToken: `live-${cup}`, seed: randomInt(0x100000000), fighterIds: pickFour() };
  const startedAt = Date.now();
  try {
    const result = await page.evaluate(input => window.oddboutBroadcast.runCup(input), input);
    console.log(JSON.stringify({ event: 'cup', cup, seed: input.seed, fighterIds: input.fighterIds, winnerId: result.winnerId,
      bouts: result.bouts.map(b => ({ leftId: b.leftId, rightId: b.rightId, winnerId: b.winnerId, seed: b.seed, digest: b.digest })),
      wallMs: Date.now() - startedAt }));
  } catch (error) {
    if (stopping) break;
    // A failed job stays terminal for this page session; reload before the next cup.
    console.error(JSON.stringify({ event: 'cup-failed', cup, seed: input.seed, message: String(error?.message ?? error) }));
    await open();
  }
  if (cups === 0 || cup < cups) await page.waitForTimeout(gapMs);
}
await browser.close();
