// Measure the App Store screens the way a browser sees them: load each
// screen in Chromium, resolve every text node's computed colour against its
// real background, and report anything under WCAG 2.1 AA.
//
// This is the rendered half of the design review. `scripts/contrast-check.py`
// runs the same arithmetic over the iOS colour tokens, but it can only see
// token *pairs* — it cannot know what a given label actually sits on. This
// can, because the browser has already done the layout.
//
//   GROOT=$(npm root -g) node measure.mjs
//
// The canvas is 3x (1320px wide for a 6.9" device), so CSS px are divided by
// 3 before WCAG's large-text threshold is applied: 24px here is 8pt, which is
// small text needing 4.5:1, not large text needing 3:1.
//
// Known false positive: text over an SVG `fill="url(#...)"` gradient. The
// background walker reads CSS backgrounds only, so the gold medal on
// 02-score reports ~1.04:1 for text that is really dark-on-gold. Confirmed
// by eye; left visible rather than special-cased, because a rule that
// quietly excuses cases is how the iOS glow rule came to report zero.

import { createRequire } from 'module';
import { readdirSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
const require = createRequire(import.meta.url);
const groot = process.env.GROOT || '/opt/node22/lib/node_modules';
const { chromium } = require(join(groot, 'playwright'));

const here = dirname(fileURLToPath(import.meta.url));
const SETS = {
  phone:      { dir: 'screens',             w: 1320, h: 2868, scale: 3 },
  watch:      { dir: 'screens-watch',       w: 410,  h: 502,  scale: 2 },
  watchframe: { dir: 'screens-watch-frames', w: 1320, h: 1650, scale: 3 },
  ipad:       { dir: 'screens',             w: 2064, h: 2752, scale: 2, css: 'assets/ipad.css' },
};
const setName = process.argv[2] || 'phone';
const SET = SETS[setName];
if (!SET) { console.error('unknown set: ' + setName + ' (have: ' + Object.keys(SETS).join(', ') + ')'); process.exit(2); }
const files = readdirSync(join(here, SET.dir)).filter(f => f.endsWith('.html'));

// Honour an explicit path when the environment pins one, else let
// Playwright resolve its own bundled browser.
const exe = process.env.CHROMIUM_PATH;
const browser = await chromium.launch(exe ? { executablePath: exe } : {});
const page = await browser.newPage({ viewport: { width: SET.w, height: SET.h } });

const results = [];
for (const f of files) {
  await page.goto('file://' + join(here, SET.dir, f));
  if (SET.css) await page.addStyleTag({ path: join(here, SET.css) });
  await page.waitForTimeout(300);
  const data = await page.evaluate((SCALE) => {
    const lum = (r,g,b) => { const c=[r,g,b].map(v=>{v/=255; return v<=0.04045?v/12.92:Math.pow((v+0.055)/1.055,2.4);}); return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]; };
    const parse = s => { const m = s.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/); return m ? {r:+m[1],g:+m[2],b:+m[3],a:m[4]===undefined?1:+m[4]} : null; };
    // What is painted behind this text, by hit-testing rather than by walking
    // the ancestor chain.
    //
    // The chain is the wrong tree to walk. The gold level badge is an
    // absolutely-positioned *sibling* of its own label, so no ancestor carries
    // the gold: the walk sailed past it to the page's dark backdrop and scored
    // near-black ink on a gold disc as 1.04:1. Three failures that were never
    // real — and rather than anyone looking at them, check.sh grew a `[0-3]`
    // threshold that tolerated exactly that many, which meant the next three
    // genuine failures would also have passed.
    //
    // `elementsFromPoint` sees the actual paint order, siblings included. A
    // gradient still isn't one colour, so every stop comes back and the caller
    // scores against the worst: text that clears the darkest and the lightest
    // stop clears the whole ramp.
    const bgOf = el => {
      const r = el.getBoundingClientRect();
      const probes = [[r.left + r.width * 0.5, r.top + r.height * 0.5],
                      [r.left + 2,             r.top + r.height * 0.5],
                      [r.right - 2,            r.top + r.height * 0.5]];
      const found = [];
      for (const [x, y] of probes) {
        for (const n of document.elementsFromPoint(x, y)) {
          if (n === el || el.contains(n)) continue;
          // An SVG shape paints through `fill`, not through a CSS background,
          // and the gold badge is exactly that: a <circle fill="url(#medal)">.
          // Without this the hit test finds the circle, sees no background,
          // and walks on to the page backdrop — the same wrong answer the
          // ancestor walk gave, arrived at by a better route.
          if (n.ownerSVGElement || n.tagName === 'svg') {
            const fill = n.getAttribute && n.getAttribute('fill');
            if (fill && fill !== 'none') {
              const ref = fill.match(/^url\(#([\w-]+)\)$/);
              if (ref) {
                const server = document.getElementById(ref[1]);
                const stops = server
                  ? [...server.querySelectorAll('stop')]
                      .map(s => parse(getComputedStyle(s).stopColor))
                      .filter(c => c && c.a > 0.5)
                  : [];
                if (stops.length) { found.push(...stops); break; }
              } else {
                const c = parse(getComputedStyle(n).fill);
                if (c && c.a > 0.5) { found.push(c); break; }
              }
            }
            continue;
          }
          const cs = getComputedStyle(n);
          const img = cs.backgroundImage || '';
          if (img.includes('gradient')) {
            const stops = (img.match(/rgba?\([^)]*\)/g) || [])
              .map(parse).filter(c => c && c.a > 0.5);
            if (stops.length) { found.push(...stops); break; }
          }
          const c = parse(cs.backgroundColor);
          if (c && c.a > 0.5) { found.push(c); break; }
        }
      }
      return found.length ? found : [{r:19,g:19,b:25,a:1}];
    };
    const contrast = (f,b) => { const L1=lum(f.r,f.g,f.b), L2=lum(b.r,b.g,b.b); return (Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05); };
    const out = { text: [], small: [], overflow: [] };
    for (const el of document.querySelectorAll('body *')) {
      if (['STYLE','SCRIPT','NOSCRIPT'].includes(el.tagName)) continue;
      const rr = el.getBoundingClientRect(); if (rr.width < 1 || rr.height < 1) continue;
      const kids = [...el.childNodes].filter(n => n.nodeType===3 && n.textContent.trim());
      if (!kids.length) continue;
      const cs = getComputedStyle(el);
      const fg = parse(cs.color); if (!fg) continue;
      const bgs = bgOf(el);
      const size = parseFloat(cs.fontSize);
      const weight = parseInt(cs.fontWeight) || 400;
      const ratio = Math.min(...bgs.map(b => contrast(fg, b)));
      const large = (size/SCALE) >= 24 || ((size/SCALE) >= 18.66 && weight >= 700);
      const need = large ? 3.0 : 4.5;
      if (ratio < need) out.text.push({ t: kids.map(n=>n.textContent.trim()).join(' ').slice(0,40), size, weight, ratio: +ratio.toFixed(2), need, color: cs.color });
      const r = el.getBoundingClientRect();
      if ((size/SCALE) < 9 && r.width > 0) out.small.push({ t: kids.map(n=>n.textContent.trim()).join(' ').slice(0,30), size });
    }
    // Content wider than the box holding it. A card that overflows gets
    // clipped by the phone bezel, which is how a season and a half of every
    // habit heatmap went missing without any check noticing: contrast was
    // fine, type was fine, the pixels were simply not on screen.
    for (const el of document.querySelectorAll('*')) {
      const over = el.scrollWidth - el.clientWidth;
      if (over <= 2 || el.clientWidth <= 0) continue;
      // Absolutely-positioned children are allowed to escape their box —
      // that is how the watch's digital crown sticks out of the case, and
      // flagging it would teach everyone to ignore this rule. Only content
      // in normal flow, which is content that got clipped rather than
      // content that was placed, counts.
      const r = el.getBoundingClientRect();
      const spills = [...el.children].some(k => {
        if (getComputedStyle(k).position === 'absolute') return false;
        const kr = k.getBoundingClientRect();
        return kr.right - r.right > 2 || r.left - kr.left > 2;
      });
      if (!spills) continue;
      out.overflow.push({ sel: (el.className || el.tagName).toString().slice(0, 30),
                          client: el.clientWidth, scroll: el.scrollWidth, over });
    }
    return out;
  }, SET.scale);
  results.push({ file: f, ...data });
}
await browser.close();

let totalFail = 0;
for (const r of results) {
  if (!r.text.length && !r.small.length && !r.overflow.length) { console.log(`  ${r.file}: clean`); continue; }
  console.log(`\n  ${r.file}`);
  for (const t of r.text) { totalFail++; console.log(`    CONTRAST ${t.ratio}:1 (needs ${t.need})  ${t.size}px/${t.weight}  "${t.t}"  ${t.color}`); }
  for (const s of r.small) console.log(`    TINY ${s.size}px  "${s.t}"`);
  for (const o of r.overflow) { totalFail++; console.log(`    OVERFLOW ${o.over}px  .${o.sel}  (${o.client} available, ${o.scroll} needed)`); }
}
console.log(`\n[${setName}] ${totalFail} contrast/overflow failures across ${results.length} screens`);
