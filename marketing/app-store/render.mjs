// Render screens/*.html to PNGs at App Store dimensions.
//   GROOT=$(npm root -g) node render.mjs                 all → iPhone 6.9" (1320×2868)
//   GROOT=$(npm root -g) node render.mjs --ipad          all → iPad 13"   (2064×2752)
//   GROOT=$(npm root -g) node render.mjs 01-recovery.html [--ipad]   one screen
import { createRequire } from 'module';
import { readdirSync, mkdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, basename } from 'path';

const require = createRequire(import.meta.url);
const groot = process.env.GROOT || '/opt/node22/lib/node_modules';
const { chromium } = require(join(groot, 'playwright'));

const here = dirname(fileURLToPath(import.meta.url));
const screensDir = join(here, 'screens');

const args = process.argv.slice(2);
const ipad = args.includes('--ipad');
const only = args.find((a) => a.endsWith('.html'));

const W = ipad ? 2064 : 1320;
const H = ipad ? 2752 : 2868;
const outDir = join(here, ipad ? 'screenshots-ipad' : 'screenshots');
const ipadCss = join(here, 'assets', 'ipad.css');
mkdirSync(outDir, { recursive: true });

const files = (only ? [basename(only)] : readdirSync(screensDir))
  .filter((f) => f.endsWith('.html'))
  .sort();

const browser = await chromium.launch({ args: ['--force-color-profile=srgb', '--font-render-hinting=none'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });

for (const f of files) {
  await page.goto('file://' + join(screensDir, f), { waitUntil: 'networkidle' });
  if (ipad) await page.addStyleTag({ path: ipadCss });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(150);
  const out = join(outDir, f.replace(/\.html$/, '.png'));
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width: W, height: H } });
  console.log('✓', (ipad ? '[iPad] ' : '') + basename(out));
}

await browser.close();
