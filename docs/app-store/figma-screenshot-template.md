# Atlas — Figma Screenshot Master Template

Production-ready spec for the 8 App Store screenshots. Build the
template once, then duplicate + swap the simulator capture +
headline copy for each screen. Once the master exists, each
screenshot is a ~5-minute export.

This document is the **single source of truth** for screenshot
visuals. If a designer (or future-you) ever asks "what padding?
what font weight? what gradient?" — the answer is here, not in
someone's head.

---

## 1 — Canvas sizes (one master, per device export)

Apple's required + commonly-needed device frames for v2.1:

| Device | Resolution (px) | Notes |
|---|---|---|
| **iPhone 16 Pro Max** | **1320 × 2868** | Primary master — most premium, biggest screen |
| iPhone 15 Pro Max | 1290 × 2796 | 6.7" required floor for current submission |
| iPhone 14 Plus | 1290 × 2796 | Same size as above, App Store treats as 6.7" |
| iPad Pro 13" (M4) | 2064 × 2752 | Optional but premium signal |

**Recommendation:** build the master at 1320 × 2868. Scale to
1290 × 2796 for the 6.7" export (97 % scale). The iPad gets its
own layout with content laid horizontally; skip for v2.1 unless
you want to invest the extra ~3 hours.

---

## 2 — Layout — single master template

Vertical zones from top to bottom:

```
┌───────────────────────────────────────┐  ← top of canvas
│                                       │  
│      [Headline]                       │  ← zone A — 280px tall
│      [Subhead]                        │
│                                       │
├───────────────────────────────────────┤
│   ╔═════════════════════════════╗     │
│   ║                             ║     │
│   ║   [iPhone screen capture]   ║     │  ← zone B — naked capture
│   ║   (no device chrome)        ║     │     rounded 75px corners
│   ║                             ║     │
│   ║                             ║     │
│   ╚═════════════════════════════╝     │
│                                       │
│                                       │  ← zone C — bottom safe area
│                                       │     ~120px
└───────────────────────────────────────┘
```

### Zone A — headline (top)
- Top padding: **160 px**
- Left/right padding: **96 px**
- Max headline width: **1128 px**
- Headline → subhead gap: **24 px**
- Headline → screen capture gap: **80 px**

### Zone B — screen capture
- Capture is a **naked simulator screenshot** (no device frame),
  scaled to fill ~80 % of canvas width, centred
- Capture width: **1128 px** (canvas width − 192 px gutter total)
- Corner radius: **75 px** (matches iPhone 16 Pro Max display
  corner radius)
- Drop shadow: `0 24 64 rgba(0,0,0,0.5)` — subtle lift, not
  drama
- Optional soft glow behind capture: 240 px Gaussian blur, accent
  color at 35 % opacity, only at the top edge

### Zone C — bottom
- Bottom padding: **120 px** (clears Apple's required content
  margin)

---

## 3 — Backdrop

Full-canvas linear gradient, top-leading → bottom-trailing.

### Default gradient (use for screenshots 1, 2, 8)
```
0%   #0E0F1A   (near-black, deep navy)
50%  #1A1B2E   (dark navy with a hint of accent)
100% #0A0A0A   (true black, app background)
```

### Per-screenshot accent variations
Each screenshot gets its own accent glow added to the default
gradient — a radial gradient in the top-right corner, blend-mode
`plus lighter`, opacity 35 %.

| # | Accent glow color | Why |
|---|---|---|
| 1 — Today overview | `#10B981` emerald | Brand primary |
| 2 — Weekly recap | `#7F77DD` indigo | Insights / recap color |
| 3 — Live Activity | `#22D3EE` cyan | Action / live state |
| 4 — Insights | `#7F77DD` indigo | Insights tab identity |
| 5 — Food library | `#EF9F27` warm orange | Nutrition |
| 6 — Protocols | `#10B981` emerald | Stack / compliance |
| 7 — Apple Watch | `#D4A844` gold | Watch ecosystem |
| 8 — Siri | `#22D3EE` cyan | Voice / signal |

### Backdrop noise (optional but premium)
3 % monochromatic grain overlay across the whole canvas — keeps
the dark background from looking like flat black. Photoshop /
Figma "Add Noise" filter set to 3 %, monochromatic, Gaussian.

---

## 4 — Typography

### Headlines
- **Font:** SF Pro Display, weight **Heavy** (900)
- **Size:** 96 pt
- **Color:** `#FFFFFF` (pure white, 100 % opacity)
- **Line height:** 1.05 (tight, premium)
- **Tracking (letter spacing):** −1.5 % (−1.4 px at 96 pt)
- **Alignment:** Left
- **Max two lines** — anything longer needs rephrasing

### Subheads
- **Font:** SF Pro Display, weight **Medium** (500)
- **Size:** 40 pt
- **Color:** `#FFFFFF` at 65 % opacity (`rgba(255,255,255,0.65)`)
- **Line height:** 1.3
- **Tracking:** 0
- **Max one line** — keep it tight

### Wordmark (when used — optional small "Atlas" badge in the corner)
- **Font:** SF Pro Display, weight **Heavy** (900)
- **Size:** 28 pt
- **Color:** `#FFFFFF` at 85 % opacity
- **Position:** top-right, 96 px from top + right edges
- **Optional:** include a 3-pt × 24-pt accent bar to the left of
  the wordmark, color = current screenshot's accent

> **If SF Pro isn't available in Figma:** use **Inter Variable**
> at the same weights. Inter is metrically compatible with SF Pro
> and is freely available.

---

## 5 — Headline + subhead copy (8 screenshots)

Final copy keyed to the App Store screenshot plan. Lock these in
before building the masters so each variant just needs the text
swap.

| # | Headline | Subhead | Accent |
|---|---|---|---|
| 1 | **Your day,** \n **at a glance.** | One screen, every domain. | Emerald |
| 2 | **Your week,** \n **summarised by AI.** | Sundays, in 150 words. | Indigo |
| 3 | **Log doses** \n **from the lock screen.** | No unlock. No app launch. | Cyan |
| 4 | **See what's** \n **actually working.** | Correlation across sleep, HRV, mood. | Indigo |
| 5 | **Three million foods.** \n **One barcode.** | Scan, save, log. | Warm orange |
| 6 | **Built for** \n **stacking.** | Active stacks, vial shelf, planner. | Emerald |
| 7 | **On your** \n **wrist.** | Quick-log from Apple Watch. | Gold |
| 8 | **"Hey Siri,** \n **log my BPC-157."** | Siri, Action Button, Spotlight. | Cyan |

> The `\n` indicates a hard line break in the Figma text node —
> don't let Figma auto-wrap, set explicit two-line breaks so the
> typography lays out predictably across the 8 variants.

---

## 6 — Status bar override

Always show the "perfect" status bar in every screenshot.
Configure the simulator before each capture:

```bash
# Set all 8 simulator status-bar values in one go
xcrun simctl status_bar booted override \
  --time "9:41" \
  --dataNetwork wifi \
  --wifiMode active \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 \
  --batteryState charged \
  --batteryLevel 100
```

Reset between dev / capture sessions:
```bash
xcrun simctl status_bar booted clear
```

---

## 7 — Capture workflow (per screenshot)

1. Boot iPhone 16 Pro Max simulator in Xcode
2. Run the app from Xcode (`⌘ R`)
3. Apply status-bar override (snippet in section 6)
4. Profile → Settings → **Screenshot mode** → tap "Show demo
   data" → confirm
5. Tap the **×** on the floating reminder banner to hide it (it
   stays hidden for the session — comes back on next launch as
   long as demo mode is still on)
6. Navigate to the target screen:
   - **#1** Today tab, scroll position: top
   - **#2** Today tab, scroll position: top with weekly recap
     hero visible
   - **#3** Lock screen of the simulator — set the dose to come
     due in ~3 min, then `⌘ L` to lock; the Live Activity
     appears in `dueNow` state
   - **#4** Insights tab → "What's working" section visible
   - **#5** Today → Meals → tap Food Library → search for a
     food and let results render; capture the search results
   - **#6** Protocols tab, scroll to show vial shelf + stack
     health cards
   - **#7** Apple Watch simulator paired with the iPhone sim →
     swipe to the third page (nutrition)
   - **#8** From iPhone, hold Side button to invoke Siri, ask
     "Log my BPC-157" → capture the response card
7. Capture: in Simulator menu bar → **File → Save Screen** (`⌘ S`)
   — saves to Desktop as PNG at native resolution
8. Drop the PNG into the Figma master's screen-capture smart
   object → swap the headline + subhead → swap the accent glow
   color → export as PNG at 1×

Total time per screenshot: ~3-5 minutes once the master exists.
Total for all 8 × 2 device sizes: ~80 minutes.

---

## 8 — Export settings

### From Figma
- Format: **PNG**
- Scale: **1×** (canvas is already at native resolution)
- Background: include (gradient fills the canvas)
- Each frame exports as a separate file

### Upload to App Store Connect
- Drop the 8 × PNG files into the 6.9" / 6.7" / iPad slots
- Order matters — slot 1 is the hero (first thing users see in
  the search results)
- The first 3 screenshots show in the search-results preview;
  4-8 only show on the listing page

---

## 9 — Apple Watch screenshots

The Watch app's screenshot mode is automatically wired through
the iPhone's `ScreenshotMode.activate` — when the iPhone is in
demo mode, the Watch sync pipeline pushes demo data to the paired
Watch simulator. No separate toggle needed.

**Capture workflow for Watch screenshots:**

1. Pair Apple Watch simulator with the iPhone simulator (Xcode →
   Window → Devices and Simulators → set Companion Device)
2. Activate iPhone screenshot mode as above
3. Wait ~2 seconds for the Watch to receive the
   WatchConnectivity payload
4. In Watch simulator: File → Save Screen
5. Watch screenshot dimensions: 410 × 502 px (Ultra 49 mm) or
   396 × 484 px (Series 10 46 mm)

Watch screenshots have **their own Figma canvas**:
- 410 × 502 master
- Tighter typography: 56 pt headline, 24 pt subhead
- Same accent palette
- No subhead on tighter Watch surfaces — the screen tells the
  story alone

---

## 10 — Pre-flight checklist (before exporting final assets)

- [ ] All 8 headlines fit in 2 lines at 96 pt without
      auto-wrapping
- [ ] No status-bar variation across screenshots (every one shows
      9:41 / 100 % battery / wifi 3 bars / cellular 4 bars)
- [ ] Screenshot mode banner hidden in every capture
- [ ] Accent glow color matches the table in section 3 for each
      screenshot
- [ ] Subheads under 60 characters
- [ ] Drop shadow under the screen capture renders subtly, not
      heavy
- [ ] Wordmark "Atlas" not on screenshots #1-2 (the screen
      itself shows the app branding); optional on #3-8
- [ ] Export at 1× scale, not 2× (canvas is already native res)
- [ ] All 8 exported as PNG (not JPG — App Store strips JPG
      artifacts but the upload preview shows them)

---

## 11 — Future-proofing

When v2.2 ships with new features, this template scales:
- Duplicate the master, swap the screen capture + accent glow +
  headline
- The typography, gradient, padding stay constant — that's the
  brand
- Update section 5's copy table with the new screenshot's text
- Re-export only the changed screenshots

---

## 12 — Source files

Recommended Figma file structure:

```
Atlas v2.1 Screenshots/
├── 📄 Master — iPhone 6.9" (1320 × 2868)
├── 📄 Master — iPhone 6.7" (1290 × 2796)
├── 📁 Captures (raw simulator PNGs)
│   ├── 01-today-overview.png
│   ├── 02-weekly-recap.png
│   ├── 03-live-activity.png
│   ├── 04-insights.png
│   ├── 05-food-library.png
│   ├── 06-protocols.png
│   ├── 07-watch.png
│   └── 08-siri.png
├── 📁 Exports — 6.9"
│   └── (8 final PNGs ready for App Store Connect)
├── 📁 Exports — 6.7"
│   └── (8 final PNGs)
└── 📄 Master — Apple Watch (410 × 502)
```

Share the Figma file with the engineering account so a future
version-bump can re-export without re-onboarding a designer.
