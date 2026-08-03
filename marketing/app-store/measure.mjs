import { createRequire } from 'module';
import { readdirSync } from 'fs';
const require = createRequire(import.meta.url);
const { chromium } = require('/opt/node22/lib/node_modules/playwright');

const here = '/home/user/Peptide-ai/marketing/app-store';
const files = readdirSync(here + '/screens').filter(f => f.endsWith('.html'));

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const page = await browser.newPage({ viewport: { width: 1320, height: 2868 } });

const results = [];
for (const f of files) {
  await page.goto('file://' + here + '/screens/' + f);
  await page.waitForTimeout(300);
  const data = await page.evaluate(() => {
    const lum = (r,g,b) => { const c=[r,g,b].map(v=>{v/=255; return v<=0.04045?v/12.92:Math.pow((v+0.055)/1.055,2.4);}); return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]; };
    const parse = s => { const m = s.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/); return m ? {r:+m[1],g:+m[2],b:+m[3],a:m[4]===undefined?1:+m[4]} : null; };
    const bgOf = el => { let n = el; while (n && n !== document.documentElement) { const c = parse(getComputedStyle(n).backgroundColor); if (c && c.a > 0.5) return c; n = n.parentElement; } return {r:19,g:19,b:25,a:1}; };
    const contrast = (f,b) => { const L1=lum(f.r,f.g,f.b), L2=lum(b.r,b.g,b.b); return (Math.max(L1,L2)+0.05)/(Math.min(L1,L2)+0.05); };
    const out = { text: [], small: [] };
    for (const el of document.querySelectorAll('body *')) {
      if (['STYLE','SCRIPT','NOSCRIPT'].includes(el.tagName)) continue;
      const rr = el.getBoundingClientRect(); if (rr.width < 1 || rr.height < 1) continue;
      const kids = [...el.childNodes].filter(n => n.nodeType===3 && n.textContent.trim());
      if (!kids.length) continue;
      const cs = getComputedStyle(el);
      const fg = parse(cs.color); if (!fg) continue;
      const bg = bgOf(el);
      const size = parseFloat(cs.fontSize);
      const weight = parseInt(cs.fontWeight) || 400;
      const ratio = contrast(fg, bg);
      const large = (size/3) >= 24 || ((size/3) >= 18.66 && weight >= 700);
      const need = large ? 3.0 : 4.5;
      if (ratio < need) out.text.push({ t: kids.map(n=>n.textContent.trim()).join(' ').slice(0,40), size, weight, ratio: +ratio.toFixed(2), need, color: cs.color });
      const r = el.getBoundingClientRect();
      if (size < 11 && r.width > 0) out.small.push({ t: kids.map(n=>n.textContent.trim()).join(' ').slice(0,30), size });
    }
    return out;
  });
  results.push({ file: f, ...data });
}
await browser.close();

let totalFail = 0;
for (const r of results) {
  if (!r.text.length && !r.small.length) { console.log(`  ${r.file}: clean`); continue; }
  console.log(`\n  ${r.file}`);
  for (const t of r.text) { totalFail++; console.log(`    CONTRAST ${t.ratio}:1 (needs ${t.need})  ${t.size}px/${t.weight}  "${t.t}"  ${t.color}`); }
  for (const s of r.small) console.log(`    TINY ${s.size}px  "${s.t}"`);
}
console.log(`\n${totalFail} contrast failures across ${results.length} screens`);
