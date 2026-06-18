// Render every screens/*.html to a 1320×2868 PNG (iPhone 6.9" App Store size).
// Usage: GROOT=$(npm root -g) node render.mjs [single-file.html]
import { createRequire } from 'module';
import { readdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join, basename } from 'path';

const require = createRequire(import.meta.url);
const groot = process.env.GROOT || '/opt/node22/lib/node_modules';
const { chromium } = require(join(groot, 'playwright'));

const here = dirname(fileURLToPath(import.meta.url));
const screensDir = join(here, 'screens');
const outDir = join(here, 'screenshots');

const W = 1320, H = 2868;

const only = process.argv[2];
const files = (only ? [basename(only)] : readdirSync(screensDir))
  .filter((f) => f.endsWith('.html'))
  .sort();

const browser = await chromium.launch({ args: ['--force-color-profile=srgb', '--font-render-hinting=none'] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });

for (const f of files) {
  await page.goto('file://' + join(screensDir, f), { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(120);
  const out = join(outDir, f.replace(/\.html$/, '.png'));
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width: W, height: H } });
  console.log('✓', basename(out));
}

await browser.close();
