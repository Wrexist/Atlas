// Render social/web marketing assets at mixed sizes.
//   GROOT=$(npm root -g) node render-social.mjs [one-file.html]
import { createRequire } from 'module';
import { mkdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, basename } from 'path';

const require = createRequire(import.meta.url);
const groot = process.env.GROOT || '/opt/node22/lib/node_modules';
const { chromium } = require(join(groot, 'playwright'));

const here = dirname(fileURLToPath(import.meta.url));
const srcDir = join(here, 'social');
const outDir = join(here, 'screenshots-social');
mkdirSync(outDir, { recursive: true });

const jobs = [
  ['square-recovery.html', 1080, 1080],
  ['square-score.html', 1080, 1080],
  ['square-meals.html', 1080, 1080],
  ['square-biology.html', 1080, 1080],
  ['square-brand.html', 1080, 1080],
  ['hero.html', 2560, 1440],
  ['og.html', 1200, 630],
];

const only = process.argv[2] ? basename(process.argv[2]) : null;
const run = only ? jobs.filter((j) => j[0] === only) : jobs;

const browser = await chromium.launch({ args: ['--force-color-profile=srgb', '--font-render-hinting=none'] });
for (const [file, w, h] of run) {
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  await page.goto('file://' + join(srcDir, file), { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(150);
  const out = join(outDir, file.replace(/\.html$/, '.png'));
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width: w, height: h } });
  await page.close();
  console.log('✓', basename(out), `${w}×${h}`);
}
await browser.close();
