# Atlas — App Store screenshot deck

Production-ready App Store marketing screenshots for the **PeptideX → Atlas**
relaunch, generated from code so they regenerate deterministically and stay in
sync with the listing copy in [`APP_STORE_METADATA.md`](../../APP_STORE_METADATA.md).

```
marketing/app-store/
  assets/atlas.css        shared iPhone/iPad design system (tokens, glass, rings…)
  assets/ipad.css         render-time override → iPad caption-left / device-right
  assets/watch.css        Apple Watch design system (OLED, glanceable)
  assets/watch-frame.css  Apple Watch marketing-frame device (case/crown/band)
  screens/*.html          iPhone/iPad mockup per slot (10)
  screens-watch/*.html    Apple Watch App Store screens (6), one source for every watch size
  screens-watch-frames/*.html  Apple Watch caption frames for web/social (6)
  render.mjs              Playwright → PNG at exact App Store dimensions
  screenshots/*.png            iPhone 6.9"  (1320 × 2868)
  screenshots-ipad/*.png       iPad 13"     (2064 × 2752)
  screenshots-watch*/          Apple Watch uploads: Ultra 3, Ultra 2, Series 11/10, Series 6 (see slot table)
  screenshots-watch-frames/*.png  Apple Watch caption frames (1320 × 1650) — web/social
  _preview*.png           contact sheets (phone · ipad · watch · watch-frames)
```

> These are **designed marketing frames** (real app UI laid out with realistic
> data + caption overlays), not raw simulator captures — which is exactly what
> the App Store's top apps ship. Use them as-is, or drop real on-device captures
> into the same device frame later. The numbers shown are illustrative.
>
> **Design pass (v2):** clean / realistic / one-hero-stat. Each frame shows the
> **full device with native iOS chrome** (status bar, a real bottom tab bar on the
> tab screens, sheet grabbers on modals), is decluttered to a single dominant stat,
> and drops gimmicky floating callouts. No fake ratings or unverifiable claims.

---

## Regenerate

```bash
# one-time (already done in this environment):
#   npx playwright install chromium
cd marketing/app-store
GROOT=$(npm root -g) node render.mjs            # iPhone (all 10)
GROOT=$(npm root -g) node render.mjs --ipad     # iPad (all 10)
GROOT=$(npm root -g) node render.mjs --watch    # Apple Watch uploads (all 6, every watch size)
GROOT=$(npm root -g) node render.mjs --watchframe  # Apple Watch caption frames (all 6, 1320×1650)
GROOT=$(npm root -g) node render-social.mjs        # web/social: 5 squares + hero + OG
GROOT=$(npm root -g) node render.mjs 05-recovery.html          # one iPhone screen
GROOT=$(npm root -g) node render.mjs 02-recovery.html --watch=s10  # one watch screen, one size
```

> **Watch caption frames** (`screenshots-watch-frames/`) embed each rendered watch
> shot in a branded Apple Watch device + headline — for the website, social, and
> listing promo art. They are **not** the App Store watch upload; that's the bare
> `screenshots-watch/` set. Re-run `--watch` first if you change a watch screen,
> then `--watchframe` to refresh these.

Edit a file in `screens/` (or `screens-watch/`), re-run, done. Each HTML pulls its
shared stylesheet, so a token change (e.g. accent colour) propagates across the deck.

---

## The deck — narrative & rationale

Ordered for conversion. The **first three frames are visible in search results and
decide the install**, so they lead with the strongest emotional hooks; the rest
build breadth and end on the paywall (required by App Review).

| # | Screen | Hook (headline) | Job it does |
|---|--------|-----------------|-------------|
| 1 | Train (real 1.3 capture) | "Train one exercise at a time." | The 1.3 focused workout screen: rest timer, target muscles, every set. |
| 2 | Meals | "Snap a photo. Every item logged." | Effortless food logging. |
| 3 | Muscle map (real capture) | "See every muscle you train." | 30-day muscle coverage; tap a muscle for its sets. |
| 4 | Recap (real capture) | "A recap after every workout." | Duration, sets, volume and muscles after each session. |
| 5 | Recovery / Today | "Know if you're ready to train." | Daily recovery score. |
| 6 | Atlas Score | "A streak you won't break." | Retention: streaks and levels. |
| 7 | Biology · Atlas Pro | "Track your Performance Age." | Pro upsell; labelled an estimate, never "biological age". |
| 8 | Habits | "Build streaks that stick." | Six-month heatmap. |
| 9 | Protocols | "Track every protocol. To the dose." | Advanced audience. |
| 10 | Paywall | "Try free. Upgrade when ready." | Required by Guideline 3.1; 7-day trial on Monthly and Annual, matching Products.storekit. |

Slides 1, 3 and 4 embed real simulator captures from `captures/` through
`assets/capture.css`; its `.patch` boxes replace placeholder values the UI
test typed. Every iPhone frame carries a Dynamic Island. Render with an
installed Chrome and no browser download:
`GROOT=<dir with node_modules/playwright-core> PW_CHANNEL=chrome node render.mjs`.

App Store Connect slots and the folder each one takes (1.3.0):

| Slot | Size | Folder |
|---|---|---|
| iPhone with Dynamic Island, medium (required) | 1206 × 2622 | `screenshots-6.3/` |
| iPhone with Dynamic Island, large | 1320 × 2868 | `screenshots/` |
| iPhone with Face ID, large | 1284 × 2778 | `screenshots-6.5/` |
| iPad 13" | 2064 × 2752 | `screenshots-ipad/` |
| Apple Watch Ultra 3 | 422 × 514 | `screenshots-watch-ultra3/` |
| Apple Watch Ultra 2 / Ultra | 410 × 502 | `screenshots-watch/` |
| Apple Watch Series 11 / 10 | 416 × 496 | `screenshots-watch-s10/` |
| Apple Watch Series 9 / 8 / 7 | 396 × 484 | `screenshots-watch-s9/` |
| Apple Watch Series 6 / SE | 368 × 448 | `screenshots-watch-s6/` |

The 6.3 and 6.5 iPhone sets are Lanczos resizes of the rendered 6.9" set
(a few pixels centre-cropped to the slot's aspect), not separate renders.
Every Apple Watch set is a native render: the watch screens size everything
in watch points (viewport width / 208), so `node render.mjs --watch` draws
all four slots from one source, and `--watch=ultra3|ultra|s10|s9|s6` draws one.
App Store Connect wants one Apple Watch size used across every localization.

Pro-gated frames (only #5 here) carry the `Atlas Pro — subscription required`
badge per Guideline 2.3.2.

---

## Research → what these screenshots deliberately do

Synthesised from 2025–2026 ASO/CRO guidance (sources below). Every rule is applied
in the deck:

1. **The first 3 are everything.** They appear in search results; most users decide
   in seconds without reading the description. Frames 1–3 each carry one strong
   headline + one hero visual. *(SplitMetrics, ASOMobile, AppScreenshotStudio)*
2. **Lead with the emotional benefit, not a feature list.** "Know if you're ready to
   train" / "earns points" / "two taps" — outcomes, not specs.
3. **Tell a story across the set:** problem → emotional payoff → solution, then breadth.
4. **Real, specific numbers convert.** "47-day streak", "12,480", "100 kg × 5",
   "3.6 years younger" — concrete data signals a real, active product far better than
   "track your workouts". *(SensorTower, Nakxi)*
5. **Prove consistency for a fitness app.** Streaks, heatmaps, and a score are
   front-loaded (frames 2 & 6) because that's what fitness installers actually screen
   for — not exercise-library size.
6. **Dark, high-contrast = "intense & purposeful."** The recommended palette for
   strength/recovery apps; mint-green + violet keep health credibility and signal
   premium. *(ScreenshotWhale, Nakxi)*
7. **Authenticity beats over-polish.** Users tune out obviously-designed frames, so
   the UI sits in a full iPhone with **native iOS chrome** (status bar + real tab bar)
   and reads like a genuine screenshot — no gimmicky floating callouts. *(ASOMobile)*
8. **Headlines big, copy < 20% of the frame**, legible at search-thumbnail size.
9. **One hero stat per frame.** Each screen is decluttered so a single dominant number
   (78 · 12,480 · 100 kg · 28.4 · 47-day streak) carries it — no competing chips.
10. **No unverifiable claims.** No fake star rating; only honest signals
    ("No ads · No tracking", real trial terms).
11. **Vertical frames** (the 2026 standard for ~96% of top apps).

### Dopamine levers used
Glowing progress rings · a gold level-up medallion · climbing trend lines · 🔥 streak
counters · a clean PR moment · "younger than your age" · filling macro bars · big
tabular numbers. Each frame shows a *win in progress*, not an empty state.

### Sources
- [SplitMetrics — App Store screenshot guide (2025)](https://splitmetrics.com/blog/app-store-screenshots-aso-guide/)
- [ASOMobile — Screenshots 2025: conversion guide](https://asomobile.net/en/blog/screenshots-for-app-store-and-google-play-in-2025-a-complete-guide/)
- [AppScreenshotStudio — Screenshots that convert: 2026 guide](https://medium.com/@AppScreenshotStudio/app-store-screenshots-that-convert-the-2026-design-guide-4438994689d6)
- [ScreenshotWhale — ASO best practices](https://screenshotwhale.com/blog/app-store-optimization-best-practices)
- [SensorTower — what top health & fitness screenshots teach](https://sensortower.com/blog/top-10-health-and-fitness-apps-what-their-screenshots-teach-us-about-optimization)
- [Nakxi — high-converting screenshot best practices](https://www.nakxi.com/blog/app-store-screenshots-best-practices/)
- [MobileAction — Apple screenshot sizes & guidelines (2026)](https://www.mobileaction.co/guide/app-screenshot-sizes-and-guidelines-for-the-app-store/)
- [Apptweak — how to optimise app screenshots](https://www.apptweak.com/en/aso-blog/how-to-optimize-your-app-screenshots)

---

## Upload specs (App Store Connect)

| Device class | Pixels | Required |
|---|---|---|
| iPhone 6.9" (16 Pro Max) | **1320 × 2868** | ✅ primary — this deck. Satisfies all iPhone sizes. |
| iPhone 6.5" | 1242 × 2688 | optional legacy (near-identical aspect) |
| iPad Pro 13" | 2064 × 2752 | ✅ built (`screenshots-ipad/`) — only needed if iPad-targeted |
| Apple Watch | **422 × 514 · 410 × 502 · 416 × 496 · 368 × 448** | ✅ built — required if the Watch app ships. Upload one size, the same in every localization. |

- Upload **6–8** iPhone shots (first 3 matter most) and all **6** watch shots.
- The deck matches the headlines documented in `APP_STORE_METADATA.md` (slots 1–8).

### Apple Watch deck (`screens-watch/` → the four watch folders above)
The watch app's own pages, drawn from `PeptideWatch` (watch app 2.0): true
black with one bloom of the page colour, watchOS 10 navigation chrome, no
captions. Colours are `WatchShared/WatchPalette.swift`; ring, stage-ring,
heart and ECG geometry lives in `assets/watch.js` and mirrors the SwiftUI
views. Uploaded under the app's **Apple Watch** screenshot section; Atlas
ships a Watch app and complications, so this set is required.

| # | Screen | Shows |
|---|--------|-------|
| 1 | Today | Health, training and protocol rings, stat columns, Atlas Score |
| 2 | Recovery | Heart with ripples, ECG strip, 56 BPM resting, Recovery and HRV |
| 3 | Sleep Score | Stage ring with 84, "High", time asleep, stage key |
| 4 | Nutrition | Calorie and protein rings, protein and streak, water buttons |
| 5 | Protocol | Adherence bar and today's doses |
| 6 | Complications | A watch face with Sleep Score, Recovery, Atlas Score and habits |

`screens-watch-frames/` puts each 410 × 502 render in a drawn watch case
under a caption for the web and social (`--watchframe`, 1320 × 1650); those
are not App Store uploads.

### Web / social (`screenshots-social/` · via `render-social.mjs`)
Not App Store uploads — for the website, link previews, and social. Self-contained
(`assets/social.css`), so they don't depend on the App Store layout.

| File | Size | Use |
|---|---|---|
| `square-recovery / score / meals / biology / brand` | 1080 × 1080 | Instagram / social posts (1:1) |
| `hero` | 2560 × 1440 | Website hero banner (phone + watch) |
| `og` | 1200 × 630 | Open Graph / Twitter link-preview card |

The hero and OG **crop the rendered device shots** via `background-position`, so they
auto-update when you re-render the iPhone/Watch decks.

### App Preview video
[`APP_PREVIEW_STORYBOARD.md`](APP_PREVIEW_STORYBOARD.md) — a 25-second, scene-by-scene
shot list for the listing's autoplay video. It must be **real on-device capture**
(Apple 2.3.10), so it's a recording script rather than a generated asset.

## Before you ship (Pre-ship checklist)
- [ ] **Meal photo:** `screens/02-meals.html` composites a real food photo from
      `assets/meal-photo.jpg` (avocado + scrambled eggs + rye toast) with verified
      macros. The current file is a low-res **demo placeholder** from a public ML
      research repo (`facebookresearch/inversecooking`, demo image) whose image
      license isn't clearly stated — **replace it with your own meal photo before
      submitting** (drop a JPG at `assets/meal-photo.jpg` and re-render). Your own
      photo is the ideal asset anyway: it's authentic, owned, and zero-risk.
- [ ] Confirm the `873` exercise count and `208` compound count still match the app.
- [ ] Swap the illustrative figures (Recovery 78, Atlas Score 12,480, 47-day streak,
      Bio Age 28.4) for real screenshots/values if you'd rather not ship sample data.
- [ ] Keep the `Atlas Pro — subscription required` badge on every Pro-gated frame.
- [ ] A/B test via **Apple Product Page Optimization** — test frame 1 (Recovery ring)
      against frame 2 (Atlas Score) as the lead; that's the highest-leverage test.
- [ ] iPad: the phone-framed layout letterboxes at iPad aspect. For an iPad set, widen
      `.device`/`.cap` in `atlas.css` (or render two-up) before generating 2064 × 2752.


## Checking contrast

`render.mjs` produces the PNGs; `measure.mjs` checks them the way a browser
sees them — every text node's computed colour resolved against its actual
background, held to WCAG 2.1 AA.

```sh
GROOT=$(npm root -g) node measure.mjs [phone|watch|watchframe|ipad]
# CHROMIUM_PATH=... if Playwright's bundled browser isn't where it expects
```

All four sets are checked separately because each has its own canvas scale —
the phone deck is 3x, the watch and iPad are 2x — and WCAG's large-text
threshold is in points, not pixels. Getting that wrong understates small
text by a factor of three.

The only remaining reported failures are one known false positive: text over
an SVG gradient (the gold medal on 06-score), which the background walker
cannot resolve. Verified by eye.

It found five real failures the first time it was run, including the medical
disclaimer at 2.6:1 and the subscription terms at 3.4:1 — the two pieces of
copy on these screens that most need to be readable. Re-run it after any
palette change and re-render before committing PNGs.
