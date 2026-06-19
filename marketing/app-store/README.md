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
  screens/*.html          iPhone/iPad mockup per slot (8)
  screens-watch/*.html    Apple Watch App Store mockup per slot (5)
  screens-watch-frames/*.html  Apple Watch caption frames for web/social (5)
  render.mjs              Playwright → PNG at exact App Store dimensions
  screenshots/*.png            iPhone 6.9"  (1320 × 2868)
  screenshots-ipad/*.png       iPad 13"     (2064 × 2752)
  screenshots-watch/*.png      Apple Watch Ultra (410 × 502) — App Store upload
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
GROOT=$(npm root -g) node render.mjs            # iPhone (all 8)
GROOT=$(npm root -g) node render.mjs --ipad     # iPad (all 8)
GROOT=$(npm root -g) node render.mjs --watch    # Apple Watch upload (all 5, 410×502)
GROOT=$(npm root -g) node render.mjs --watchframe  # Apple Watch caption frames (all 5, 1320×1650)
GROOT=$(npm root -g) node render.mjs 01-recovery.html          # one iPhone screen
GROOT=$(npm root -g) node render.mjs 02-recovery.html --watch  # one watch screen
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
| 1 | Recovery / Today | "Know if you're ready to train." | Scroll-stopper. One glowing hero number = daily intelligence. |
| 2 | Atlas Score | "A streak you won't break." | Retention proof — gamified streaks/levels (what fitness installers screen for). |
| 3 | Train | "Log a set in two taps." | Core utility + a PR-celebration dopamine moment. |
| 4 | Meals | "Snap a photo. Every item logged." | The "magic" effortless-logging differentiator. |
| 5 | Biology / Bio Age | "See your biological age." | Aspirational **Atlas Pro** hero — the biggest upsell frame. |
| 6 | Habits | "Build streaks that stick." | The satisfying 6-month green heatmap; consistency. |
| 7 | Protocols | "Track every protocol. To the dose." | Differentiator for the advanced audience. |
| 8 | Paywall | "Try free. Upgrade when ready." | Required by Guideline 3.1; shows trial + disclosure + links. |

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
| Apple Watch Ultra 2 | **410 × 502** | ✅ built (`screenshots-watch/`) — required if the Watch app ships. ASC scales it to every smaller watch. |

- Upload **6–8** iPhone shots (first 3 matter most) and **3–5** watch shots.
- The deck matches the headlines documented in `APP_STORE_METADATA.md` (slots 1–8).

### Apple Watch deck (`screenshots-watch/` · 410 × 502)
Glanceable, OLED-black, one bold element each — uploaded under the same app's
**Apple Watch** screenshot section. Atlas ships a Watch app + complications, so this
set is required.

| # | Screen | Shows |
|---|--------|-------|
| 1 | Atlas Score | Level/tier medallion + total + streak |
| 2 | Recovery | Recovery ring (78) + "Ready to train" |
| 3 | Habits | Health + Training activity rings + streak |
| 4 | Next Dose | Upcoming dose, amount, time |
| 5 | Complications | A watch face with all four Atlas complications |

## Before you ship (Pre-ship checklist)
- [ ] **Meal photo:** `screens/04-meals.html` composites a real food photo from
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
