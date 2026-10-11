// Drawing helpers for the watch screenshots. Every shape is drawn in a
// viewBox measured in watch points and sized with --pt, so it lands
// pixel-exact at every App Store Connect watch size. Geometry mirrors
// the SwiftUI views (ActivityRings, SleepStageRing, PulsingHeart, ECGTrace).

const glyphs = {
  heart: 'M12 21s-7.5-4.6-9.6-9.2C1 8.6 3 4.5 6.8 4.5c2.2 0 3.6 1.2 5.2 3 1.6-1.8 3-3 5.2-3C21 4.5 23 8.6 21.6 11.8 19.5 16.4 12 21 12 21z',
  run: 'M13.5 5.5a2 2 0 1 0 0-.1zM9 21l2.5-6 3 2.5V22h2v-6l-2.8-2.6.8-3.4c1.3 1.5 3 2.5 5 2.5v-2c-1.7 0-3.1-.9-3.8-2.2l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5 0-.8.1L6 7.6V12h2V8.9l1.8-.7L8.2 16 3.3 15l-.4 2 6.1 1.2z',
  pill: 'M8.5 3.5a5 5 0 0 1 7 7l-5 5a5 5 0 0 1-7-7z',
  flame: 'M12 2c1 4 6 6 6 12a6 6 0 0 1-12 0c0-3 2-5 3-7 0 2 1 3 2 3 0-3 0-5 1-8z',
  bolt: 'M13 2L4 14h7l-1 8 9-12h-7z',
  drop: 'M12 2s7 7.6 7 12.5a7 7 0 0 1-14 0C5 9.6 12 2 12 2z',
};

const ptBox = (size, inner, h = size) =>
  `<svg class="svg-pt" viewBox="0 0 ${size} ${h}" style="width:calc(var(--pt)*${size});height:calc(var(--pt)*${h})" aria-hidden="true">${inner}</svg>`;

/** Concentric Activity-style rings, outermost first. */
function rings(size, list, w, gap = 3) {
  const c = size / 2;
  let s = '';
  list.forEach((r, i) => {
    const rad = size / 2 - w / 2 - i * (w + gap);
    const circ = 2 * Math.PI * rad;
    const len = circ * Math.max(0.0001, Math.min(1, r.p));
    const id = `g${Math.random().toString(36).slice(2, 8)}`;
    s += `<defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${r.c}" stop-opacity=".72"/><stop offset="1" stop-color="${r.c}"/></linearGradient></defs>`;
    s += `<circle cx="${c}" cy="${c}" r="${rad}" fill="none" stroke="${r.c}" stroke-opacity=".16" stroke-width="${w}"/>`;
    s += `<circle cx="${c}" cy="${c}" r="${rad}" fill="none" stroke="url(#${id})" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${len} ${circ}" transform="rotate(-90 ${c} ${c})"/>`;
    const g = w * 0.6;
    s += `<path d="${glyphs[r.g]}" fill="#000" transform="translate(${c - g / 2} ${c - rad - g / 2}) scale(${g / 24})"/>`;
  });
  return ptBox(size, s);
}

/** Sleep stage ring: arcs with gaps that shrink for short stages. */
function stageRing(size, slices, w) {
  const total = slices.reduce((a, s) => a + s.m, 0);
  const rad = size / 2 - w / 2, circ = 2 * Math.PI * rad, c = size / 2;
  const gap = slices.length > 1 ? (w + 3) / circ : 0;
  let cursor = 0;
  let s = `<circle cx="${c}" cy="${c}" r="${rad}" fill="none" stroke="#fff" stroke-opacity=".12" stroke-width="${w}"/>`;
  for (const sl of slices) {
    const share = sl.m / total, g = Math.min(gap, share / 2);
    s += `<circle cx="${c}" cy="${c}" r="${rad}" fill="none" stroke="${sl.c}" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="0 ${circ * (cursor + g / 2)} ${circ * (share - g)} ${circ}" transform="rotate(-90 ${c} ${c})"/>`;
    cursor += share;
  }
  return ptBox(size, s);
}

/** A circular gauge open at the bottom, like Gauge(.accessoryCircular). */
function gauge(size, p, color, w = 5) {
  const c = size / 2, rad = c - w / 2 - 1, circ = 2 * Math.PI * rad, arc = 0.75;
  return ptBox(size,
    `<circle cx="${c}" cy="${c}" r="${rad}" fill="none" stroke="#fff" stroke-opacity=".2" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${circ * arc} ${circ}" transform="rotate(135 ${c} ${c})"/>` +
    `<circle cx="${c}" cy="${c}" r="${rad}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${circ * arc * p} ${circ}" transform="rotate(135 ${c} ${c})"/>`);
}

/** The Recovery hero frozen just after an R wave: heart mid-swell, two ripples. */
function heart(size) {
  const w = size * 1.9, h = size * 1.55, cx = w / 2, cy = h / 2;
  const ripple = (age) => `<circle cx="${cx}" cy="${cy}" r="${size / 2 * (1 + age * 0.85)}" fill="none" stroke="#FF375F" stroke-width="1.5" opacity="${(1 - age) * 0.6}"/>`;
  const g = size * 1.08;
  return ptBox(w,
    ripple(0.12) + ripple(0.56) +
    `<defs><filter id="hglow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="${size * 0.16}" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>` +
    `<path d="${glyphs.heart}" fill="#FF375F" filter="url(#hglow)" transform="translate(${cx - g / 2} ${cy - g / 2 + size * 0.03}) scale(${g / 24})"/>`,
    h);
}

/** ECGTrace at 2.4 beats across, newest beat at the right edge. */
function ecg(width, height, phaseNow = 0.62) {
  const rPeak = 0.24;
  const v = (p) => {
    const b = (c, w, h) => h * Math.exp(-Math.pow((p - c) / w, 2));
    return b(0.12, 0.025, 0.12) + b(rPeak - 0.025, 0.008, -0.15) + b(rPeak, 0.012, 1) + b(rPeak + 0.025, 0.01, -0.28) + b(0.45, 0.05, 0.24);
  };
  const frac = (x) => x - Math.floor(x);
  let d = '', last = [0, 0];
  for (let x = 0; x <= width; x += 0.75) {
    const y = height * 0.62 - v(frac(phaseNow - (width - x) / width * 2.4)) * height * 0.55;
    d += (x === 0 ? 'M' : 'L') + x.toFixed(2) + ' ' + y.toFixed(2);
    last = [x, y];
  }
  return ptBox(width,
    `<defs><linearGradient id="ecgg" x1="0" x2="1" y1="0" y2="0"><stop offset="0" stop-color="#FF375F" stop-opacity="0"/><stop offset="1" stop-color="#FF375F"/></linearGradient></defs>` +
    `<path d="${d}" fill="none" stroke="url(#ecgg)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>` +
    `<circle cx="${last[0]}" cy="${last[1]}" r="2.5" fill="#FF375F"/>`, height);
}

const icon = {
  ecg: '<svg viewBox="0 0 24 24"><path d="M2 12h4l2-5 4 10 3-7 2 2h5"/></svg>',
  bed: '<svg viewBox="0 0 24 24"><path d="M3 18V7M3 13h18v5M21 13a3 3 0 0 0-3-3h-7v3"/><circle cx="7" cy="10.5" r="1.5"/></svg>',
};

/** Fill every [data-draw] element from its expression. */
function draw() {
  document.querySelectorAll('[data-draw]').forEach((el) => { el.innerHTML = Function('return ' + el.dataset.draw)(); });
}
document.addEventListener('DOMContentLoaded', draw);
