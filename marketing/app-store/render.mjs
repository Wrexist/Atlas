// Render screens/*.html to PNGs at App Store dimensions.
//   GROOT=$(npm root -g) node render.mjs                 all → iPhone 6.9" (1320×2868)
//   GROOT=$(npm root -g) node render.mjs --ipad          all → iPad 13"   (2064×2752)
//   GROOT=$(npm root -g) node render.mjs 05-recovery.html [--ipad]   one screen
//   GROOT=$(npm root -g) node render.mjs --watch         screens-watch → every Apple Watch slot
//   GROOT=$(npm root -g) node render.mjs --watch=s10     one slot: ultra3 | ultra | s10 | s6
// Watch screens size everything in watch points (viewport width / 208), so
// each slot is a native render, never a resample of another.
import { createRequire } from 'module';
import { readdirSync, mkdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, basename } from 'path';

const require = createRequire(import.meta.url);
const groot = process.env.GROOT || '/opt/node22/lib/node_modules';
// Full `playwright` ships its own Chromium; `playwright-core` drives an
// installed Chrome instead (PW_CHANNEL=chrome), with no browser download.
const { chromium } = (() => {
  try { return require(join(groot, 'playwright')); } catch { return require(join(groot, 'playwright-core')); }
})();

const here = dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
const ipad = args.includes('--ipad');
const watchArg = args.find((a) => a === '--watch' || a.startsWith('--watch='));
const watch = Boolean(watchArg);
// App Store Connect Apple Watch slots → output folder.
const WATCH_SLOTS = {
  ultra3: { w: 422, h: 514, dir: 'screenshots-watch-ultra3' }, // Ultra 3
  ultra: { w: 410, h: 502, dir: 'screenshots-watch' },         // Ultra 2 / Ultra
  s10: { w: 416, h: 496, dir: 'screenshots-watch-s10' },       // Series 11 / 10
  s6: { w: 368, h: 448, dir: 'screenshots-watch-s6' },         // Series 6–4 / SE
};
const watchSlots = !watch ? [] : watchArg.includes('=')
  ? [WATCH_SLOTS[watchArg.split('=')[1]]]
  : Object.values(WATCH_SLOTS);
if (watchSlots.some((s) => !s)) throw new Error(`Unknown watch slot. Use one of: ${Object.keys(WATCH_SLOTS).join(', ')}`);
const watchframe = args.includes('--watchframe');
const only = args.find((a) => a.endsWith('.html'));

const screensDir = join(here, watchframe ? 'screens-watch-frames' : watch ? 'screens-watch' : 'screens');
const ipadCss = join(here, 'assets', 'ipad.css');
const targets = watch
  ? watchSlots.map((s) => ({ W: s.w, H: s.h, outDir: join(here, s.dir), tag: `[Watch ${s.w}×${s.h}] ` }))
  : [{
      W: watchframe ? 1320 : ipad ? 2064 : 1320,
      H: watchframe ? 1650 : ipad ? 2752 : 2868,
      outDir: join(here, watchframe ? 'screenshots-watch-frames' : ipad ? 'screenshots-ipad' : 'screenshots'),
      tag: watchframe ? '[WatchFrame] ' : ipad ? '[iPad] ' : '',
    }];

const files = (only ? [basename(only)] : readdirSync(screensDir))
  .filter((f) => f.endsWith('.html'))
  .sort();

const browser = await chromium.launch({ channel: process.env.PW_CHANNEL, args: ['--force-color-profile=srgb', '--font-render-hinting=none'] });

for (const { W, H, outDir, tag } of targets) {
  mkdirSync(outDir, { recursive: true });
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  for (const f of files) {
    await page.goto('file://' + join(screensDir, f), { waitUntil: 'networkidle' });
    if (ipad) await page.addStyleTag({ path: ipadCss });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    const out = join(outDir, f.replace(/\.html$/, '.png'));
    await page.screenshot({ path: out, clip: { x: 0, y: 0, width: W, height: H } });
    console.log('✓', tag + basename(out));
  }
  await page.close();
}

await browser.close();
