// Phone mockups for the product-page header and search-results art.
// Every screen is laid out in the capture's own 1320 × 2868 pixel space
// (a 6.9" iPhone at @3x) and scaled into the device, so overlays line up
// with the real simulator captures pixel for pixel.

const CAPTURE_W = 1320;
const CAPTURE_H = 2868;

// Real light-mode captures from the 1.3 UI-test run. The rest-timer
// capture was logged by an automated test with placeholder numbers
// (22 lb × 108 reps); the overlay swaps them for a believable session.
// The captures' clocks read whatever time the test ran; every phone shows 9:41.
const clock = (bg) => `<div class="patch clock" style="left:160px;top:60px;width:190px;height:76px;background:${bg}">9:41</div>`;

const screens = {
  muscles: () => `<img src="img/train-muscles.png" alt="">${clock('#F4F4F7')}`,

  rest: () => {
    const rows = [
      [2221, '50', '10'],
      [2389, '55', '8'],
      [2557, '55', '8'],
      [2725, '55', '8'],
    ];
    const patches = rows.map(([y, load, reps]) => `
      <div class="patch" style="left:290px;top:${y - 40}px;width:290px;height:80px">${load}</div>
      <div class="patch" style="left:700px;top:${y - 40}px;width:330px;height:80px">${reps}</div>`).join('');
    return `<img src="img/train-rest.png" alt="">${clock('#EAF3F9')}${patches}`;
  },

  complete: () => `<img src="img/train-complete.png" alt="">${clock('#F4F4F7')}
    <div class="patch big" style="left:109px;top:2240px;width:300px;height:130px;background:#F1F1F3">48m</div>
    <div class="patch big" style="left:518px;top:2240px;width:280px;height:130px;background:#F1F1F3">16</div>
    <div class="patch big" style="left:880px;top:2240px;width:360px;height:130px;background:#F1F1F3">9,840 lb</div>`,

  // No light-mode capture of the meal review exists yet, so this one is a
  // faithful light recreation in the app's own type, cards and colours.
  meal: () => `
    <div class="meal">
      ${statusBar()}
      <div class="m-nav"><span class="m-cancel">Cancel</span><span class="m-title">Review meal</span><span class="m-spacer"></span></div>
      <div class="m-head"><div class="m-big">Breakfast</div><div class="m-sub">Today · 8:12 AM</div></div>
      <div class="m-photo" style="background-image:url('img/meal-photo.jpg')"></div>
      <div class="m-label">3 items found</div>
      ${mealRow('Scrambled eggs', '2 eggs', 210, 'P 16 g · C 2 g · F 15 g')}
      ${mealRow('Avocado', '75 g', 120, 'P 2 g · C 7 g · F 11 g')}
      ${mealRow('Rye toast', '2 slices', 165, 'P 5 g · C 30 g · F 2 g')}
      <div class="m-card m-total">
        <div class="m-row"><span class="m-name">Meal total</span><span class="m-kcal">495 <small>kcal</small></span></div>
        <div class="m-macros">
          ${macro('Protein', '23 g', 46, '#E0703A')}
          ${macro('Carbs', '39 g', 62, '#3D7BE6')}
          ${macro('Fat', '28 g', 52, '#D9A21B')}
        </div>
      </div>
      <div class="m-cta">Log meal</div>
      <div class="m-home"></div>
    </div>`,
};

function statusBar() {
  return `<div class="m-status"><span>9:41</span><span class="m-sys">
    <svg width="54" height="36" viewBox="0 0 40 30"><g fill="#111"><rect x="0" y="18" width="6" height="12" rx="2"/><rect x="9" y="12" width="6" height="18" rx="2"/><rect x="18" y="6" width="6" height="24" rx="2"/><rect x="27" y="0" width="6" height="30" rx="2"/></g></svg>
    <svg width="50" height="36" viewBox="0 0 38 30" fill="none" stroke="#111" stroke-width="3.5" stroke-linecap="round"><path d="M4 12 A 22 22 0 0 1 34 12"/><path d="M10 19 A 13 13 0 0 1 28 19"/><circle cx="19" cy="25" r="2.4" fill="#111" stroke="none"/></svg>
    <svg width="78" height="36" viewBox="0 0 58 30"><rect x="1" y="4" width="46" height="22" rx="7" fill="none" stroke="#111" stroke-opacity=".4" stroke-width="2.5"/><rect x="4" y="7" width="38" height="16" rx="4" fill="#111"/><rect x="50" y="11" width="4" height="8" rx="2" fill="#111" fill-opacity=".5"/></svg>
  </span></div>`;
}

function mealRow(name, portion, kcal, macros) {
  return `<div class="m-card"><div class="m-row">
    <div><div class="m-name">${name}</div><div class="m-meta">${macros}</div></div>
    <div class="m-right"><div class="m-kcal">${kcal} <small>kcal</small></div><div class="m-meta">${portion}</div></div>
  </div></div>`;
}

function macro(label, value, pct, color) {
  return `<div class="m-macro"><div class="m-mrow"><span>${label}</span><b>${value}</b></div>
    <div class="m-bar"><i style="width:${pct}%;background:${color}"></i></div></div>`;
}

// Renders every <div class="phone" data-screen="..." style="--w:600px"> on the page.
function mountPhones() {
  for (const el of document.querySelectorAll('.phone')) {
    const w = parseFloat(getComputedStyle(el).getPropertyValue('--w'));
    const pad = w * 0.028;
    const screenW = w - pad * 2;
    const scale = screenW / CAPTURE_W;
    el.style.padding = `${pad}px`;
    el.innerHTML = `<div class="screen" style="width:${screenW}px;height:${CAPTURE_H * scale}px;border-radius:${w * 0.135}px">
      <div class="canvas" style="transform:scale(${scale})">${screens[el.dataset.screen]()}</div>
      <div class="island" style="width:${w * 0.29}px;height:${w * 0.085}px;top:${w * 0.03}px"></div>
    </div>`;
    el.style.borderRadius = `${w * 0.16}px`;
  }
}

document.addEventListener('DOMContentLoaded', mountPhones);
