# Atlas — App Store screenshot deck

Production-ready App Store marketing screenshots for the **PeptideX → Atlas**
relaunch, generated from code so they regenerate deterministically and stay in
sync with the listing copy in [`APP_STORE_METADATA.md`](../../APP_STORE_METADATA.md).

```
marketing/app-store/
  assets/atlas.css     shared design system (tokens, glass, rings, heatmap…)
  screens/*.html       one self-contained mockup per screenshot slot
  render.mjs           Playwright → PNG at exact App Store dimensions
  screenshots/*.png    the rendered deck (1320 × 2868, iPhone 6.9")
  _preview.png         contact sheet of all 8 frames
```

> These are **designed marketing frames** (real app UI laid out with realistic
> data + caption overlays), not raw simulator captures — which is exactly what
> the App Store's top apps ship. Use them as-is, or drop real on-device captures
> into the same device frame later. The numbers shown are illustrative.

---

## Regenerate

```bash
# one-time (already done in this environment):
#   npx playwright install chromium
cd marketing/app-store
GROOT=$(npm root -g) node render.mjs            # all screens
GROOT=$(npm root -g) node render.mjs 01-recovery.html   # one screen
```

Edit a file in `screens/`, re-run, done. Each HTML pulls `assets/atlas.css`, so a
token change (e.g. accent colour) propagates across the whole deck.

---

## The deck — narrative & rationale

Ordered for conversion. The **first three frames are visible in search results and
decide the install**, so they lead with the strongest emotional hooks; the rest
build breadth and end on the paywall (required by App Review).

| # | Screen | Hook (headline) | Job it does |
|---|--------|-----------------|-------------|
| 1 | Recovery / Today | "Know if you're ready to train." | Scroll-stopper. One glowing hero number = daily intelligence. |
| 2 | Atlas Score | "Every rep, meal & habit earns points." | Retention proof — gamified streaks/levels (what fitness installers screen for). |
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
7. **Device frame + guide-the-eye annotations.** UI sits in a modern iPhone frame
   with floating callouts ("Peak readiness", "Pre-filled for you") to direct attention.
8. **Headlines big, copy < 20% of the frame**, legible at search-thumbnail size.
9. **Social proof early.** Frame 1 carries a `★ 4.9 · No ads · No tracking` strip.
   *(Swap 4.9 for your real rating before shipping — see Pre-ship.)*
10. **Vertical frames** (the 2026 standard for ~96% of top apps).

### Dopamine levers used
Glowing progress rings · a gold level-up medallion · climbing trend lines · 🔥 streak
counters · a PR-confetti burst · "younger than your age" · filling macro/volume bars ·
big tabular numbers. Each frame shows a *win in progress*, not an empty state.

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
| iPad Pro 13" | 2064 × 2752 | only if iPad-targeted (re-layout needed — see below) |

- Upload **6–8** of these; the first 3 matter most.
- The deck matches the headlines documented in `APP_STORE_METADATA.md` (slots 1–8).

## Before you ship (Pre-ship checklist)
- [ ] Replace the `★ 4.9` social-proof strip in `01-recovery.html` with your **real**
      rating, or remove it (don't claim a rating you don't have).
- [ ] Confirm the `873` exercise count and `208` compound count still match the app.
- [ ] Keep the `Atlas Pro — subscription required` badge on every Pro-gated frame.
- [ ] A/B test via **Apple Product Page Optimization** — test frame 1 (Recovery ring)
      against frame 2 (Atlas Score) as the lead; that's the highest-leverage test.
- [ ] iPad: the phone-framed layout letterboxes at iPad aspect. For an iPad set, widen
      `.device`/`.cap` in `atlas.css` (or render two-up) before generating 2064 × 2752.
