# PeptideX — Screenshot Seed Data & App Fixes

Companion to `APP_STORE_SCREENSHOTS_GUIDE.md`. This doc specifies **the
exact data state to seed in the simulator** before shooting, and the
**list of app fixes** required to make every slot capture cleanly.

> **Design rule for everything below.** Lean into the **three audiences
> Apple is comfortable with**: recovery / healing, longevity / anti-aging,
> and sleep / wellness. Light touch on cognitive. **Avoid performance /
> bodybuilding framing entirely** in screenshots. That's where peptide
> apps get rejected — and it's also where the broadest, most
> credit-card-ready audience *isn't*. Recovery + longevity is a bigger
> market than performance, and it's safer.

---

## Part 1 — The 3 featured protocols

Build these 3 protocols in the simulator. They're chosen so each slot
that needs a protocol on screen has the right one to point at, and so
the **library, today view, and analytics** all read as a coherent user
who runs serious protocols across multiple goals.

### Protocol A — "Joint Recovery 8-Week" *(featured on slots 1, 2)*

The flagship protocol for screenshots. BPC-157 is the most recognizable
peptide in the entire space, and the recovery framing is the
single safest with App Review.

| Field | Value |
| --- | --- |
| **Name** | Joint Recovery 8-Week |
| **Category** | Healing |
| **Schedule type** | Cycled — 8 weeks on, 4 weeks off |
| **Status in screenshots** | Active, week 5 of 8 |
| **Notes field** | "Post-meniscus rehab. Pair with PT 3x/week." |

**Peptides in protocol:**

| Peptide | Dose | Frequency | Route | Site |
| --- | --- | --- | --- | --- |
| BPC-157 | 250 mcg | 2× daily (8 AM, 8 PM) | Subcutaneous | Near site of injury |
| TB-500 | 2 mg | 2× weekly (Mon, Thu) | Subcutaneous | Abdomen, rotating |

**Why this combo for screenshots:**
- BPC-157 is the most-Googled peptide name. Instant recognition for the
  target user.
- The 2-substance combo demonstrates "stack" capability without looking
  like a bodybuilder cocktail.
- 8/4 cycled schedule is the screenshot-perfect example of why a
  generic medication tracker fails this audience.
- Both substances have published research and clinical/research framing
  — easy to defend on review.

---

### Protocol B — "Daily Foundations" *(featured on slot 1 today-view, slot 4 library)*

Background daily protocol. Shows that the user runs more than one
protocol simultaneously — important because power-users (the conversion
target) always run stacks.

| Field | Value |
| --- | --- |
| **Name** | Daily Foundations |
| **Category** | Longevity |
| **Schedule type** | Daily, ongoing |
| **Status in screenshots** | Active, day 87 |
| **Notes field** | "Baseline routine. No cycling." |

**Peptides in protocol:**

| Peptide | Dose | Frequency | Route | Site |
| --- | --- | --- | --- | --- |
| Glutathione | 200 mg | 3× weekly (Mon, Wed, Fri) | Intramuscular | Deltoid, alternating |
| NAD+ | 100 mg | 1× weekly (Sun) | Subcutaneous | Abdomen |
| Glycine | 3 g | Nightly | Oral | — |

**Why this combo for screenshots:**
- Glutathione + NAD+ + Glycine is the most mainstream-friendly stack
  in the entire peptide world. NAD+ is on the cover of *Time*. Glycine
  is at GNC. Glutathione is in IV drip bars.
- Mixed routes (IM, SubQ, oral) showcase the app's flexibility on
  injection-site logging.
- Variable frequencies (3×/week, 1×/week, daily) give the heatmap
  visual variety.

---

### Protocol C — "Cognitive Routine 5/2" *(featured on slot 2 alternate, library variety)*

Optional 3rd protocol if you want to show the protocol *list* with
multiple entries. Selank + Semax is a real, well-known nootropic stack
with non-spicy framing.

| Field | Value |
| --- | --- |
| **Name** | Cognitive Routine 5/2 |
| **Category** | Cognitive |
| **Schedule type** | Cycled — 5 days on, 2 days off (weekends off) |
| **Status in screenshots** | Active, week 3 |
| **Notes field** | "Workdays only. Off on weekends." |

**Peptides in protocol:**

| Peptide | Dose | Frequency | Route | Site |
| --- | --- | --- | --- | --- |
| Selank | 500 mcg | 1× daily AM | Intranasal | — |
| Semax | 600 mcg | 1× daily AM | Intranasal | — |

**Why this combo for screenshots:**
- Intranasal route shows the app handles non-injection peptides — a
  feature many trackers miss.
- The 5/2 weekday-only schedule is *the* example schedule that proves
  the protocol engine is built for real life.

---

## Part 2 — Historical dose log to seed

For the heatmap (slot 5), streak counter (slot 5, slot 1), and analytics
trend lines to look earned and not faked, seed **35 days of dose log
history.** The shape matters more than the exact numbers.

### Adherence pattern

```
Week -5 (oldest):   60% — protocol just started, learning curve
Week -4:            72% — Tuesday fully missed (travel)
Week -3:            78% — Tuesday partial
Week -2:            70% — Tuesday partial, Sunday missed (forgot AM dose)
Week -1:            85% — better
Week 0 (current):   95% — building current streak (23 days running)
```

### Specific gaps to leave in the heatmap

These create the **visual story** that lets slot 5's "Tuesdays slip"
insight bubble be honest:

- Every Tuesday in weeks -5 through -2: AT LEAST one missed dose
- Two random Sundays missed
- One random "all-skip" day in week -4 with note "Traveling — flight day"
- Week -1 onward: clean

### Sample skip notes (text on the missed entries)

Realism beats perfection. Drop these notes on the missed/late doses:

- "Forgot — woke up late"
- "Travel day, no fridge access"
- "Late by 2h — meeting overran"
- "Rest day, off-cycle"
- "Skipped intentionally — sick"

These notes will likely not be visible in the screenshots themselves,
but they make the data feel *real* if a reviewer taps in to verify.

---

## Part 3 — Achievements state

Slot 9 captures the achievements grid. Show **6 unlocked, 8 locked**.
Choose names that are entirely process-based — no health-outcome words.

### Unlock these 6 (visible at top of grid, emerald glow)

1. **First Step** — Logged your first dose
2. **One Week In** — 7-day logging streak
3. **Perfect Week** — 7/7 doses on time in one week
4. **Century Club** — 100 doses logged
5. **Cycle Complete** — Finished a full protocol cycle
6. **Health Connected** — Linked Apple Health *(implies HealthKit slot already happened — story consistency)*

### Keep these 8 locked (greyed, visible below)

7. **Iron Discipline** — 30-day perfect streak
8. **Six Months Strong** — 180-day logging streak
9. **Protocol Architect** — Build 5 protocols
10. **Stack Master** — Run 3 protocols simultaneously
11. **Site Cycle** — Use every injection site at least once
12. **Year One** — 365-day streak
13. **Data Driven** — Export your first report
14. **Insight Hunter** — Read 10 weekly insights

**Hard NO on names:** "Lean," "Shredded," "Performance Boost,"
"Anti-Aging," "Recovery Boost," anything that implies a physiological
outcome. Process language only.

---

## Part 4 — HealthKit mock data (slot 3)

The HealthKit correlation screenshot needs **HRV, sleep, and resting
heart rate trends that overlap legibly with adherence.** The shape:

| Metric | Week -5 | Week -1 | Visual story |
| --- | --- | --- | --- |
| **HRV (ms)** | 45 ms | 62 ms | Gradual upward trend, mild jaggedness |
| **Sleep (h)** | 6.8 h | 7.4 h | Gentle climb, one bad week dip |
| **Resting HR (bpm)** | 64 bpm | 58 bpm | Gradual decrease |
| **Steps** | 8.2k avg | 9.1k avg | Roughly flat |

The slot 3 chart should overlay **HRV (top line)** with **adherence %
(bottom line)** in the same time window. The two curves should rise
*together* in a visually obvious way without being suspiciously
synchronized.

### Critical disclosure — bake into the screenshot

Even with the trend visualized, the screenshot must say
**"Read-only · Never written to Health"** somewhere on the slide
(in-app chip if it exists, otherwise a Figma overlay chip). Without
this, App Review may flag the slide for implying medical correlation.

The chip says you're *reading* health signals to overlay against the
user's own logging — you're not making a medical claim.

---

## Part 5 — Peptide library state (slot 4)

For slot 4, the visible cards in the library scroll position should be
these 6 specific peptides, in this order. Don't filter or search —
just scroll to where these 6 are visible together so the **6 category
chips** above also stay on screen.

| # | Peptide | Category | Why safe + appealing |
| --- | --- | --- | --- |
| 1 | **BPC-157** | Healing | Most recognizable peptide; healing framing |
| 2 | **Thymosin α-1** | Immune | Clinical pedigree, immune framing |
| 3 | **Glutathione** | Metabolic | Mainstream wellness; in IV drip bars |
| 4 | **NAD+** | Longevity | Cover of Time magazine, mainstream |
| 5 | **Glycine** | Cognitive | Sold at GNC; sleep/cognitive framing |
| 6 | **Selank** | Cognitive | Clean nootropic; non-aggressive framing |

### Peptides to **scroll past** before shooting (do NOT include in slot 4 visible area)

- **Melanotan II / MT-II** — implications around tanning + sexual function
- **GHRP-6, Ipamorelin, CJC-1295, Tesamorelin, Sermorelin, Hexarelin** — growth-hormone-secretagogue framing → performance → review risk
- **IGF-1 LR3, MGF** — growth factor framing, bodybuilder-coded
- **PT-141 / Bremelanotide** — sexual function, will trip 17+ ratings + content review
- **AOD-9604** — fat-loss-coded
- **5-Amino 1MQ, SLU-PP-332** — weight-loss-coded

These can absolutely exist in the database — many users will search for
them. Just don't make them the **screenshot hero examples**.

### Required disclaimer chip

The "Educational reference. Not medical advice." chip must appear at
the bottom of the device frame on slot 4. If your peptide list view
doesn't have one, add it (it should exist anyway given your in-app
medical disclaimer policy from `APP_STORE_METADATA.md`).

---

## Part 6 — App fixes needed before you can shoot

Triaged by what's truly **blocking** vs. what's "this slide will look
better." Build top-down.

### 🚨 Critical — must fix before shooting (blocks specific slots)

These are fixes without which the screenshot either can't be captured
or will look amateur.

**1. Build a Privacy Summary screen** *(blocks slot 8)*

Add `PrivacySummaryView` under `Peptide/Views/Profile/`. Reachable from
Profile → About → "Privacy at a glance." Five rows with SF Symbols:

```swift
shield.checkered    "No analytics. No trackers."
network.slash       "No backend. No remote push."
key.fill            "Sign in with Apple is optional."
icloud.fill         "iCloud syncs your private database. We never see it."
square.and.arrow.up "Export everything. Anytime."
```

Bottom: small "Verified by privacy manifest" chip linking to the
in-app privacy policy. ~1 hour build, one of the highest-ROI screens
on the listing.

**2. Confirm rich notification actions render correctly on lock screen** *(blocks slot 6)*

Verify the notification category in `NotificationService` (or wherever
local notifications register) actually shows **"Mark as Taken"** and
**"Snooze"** buttons when the notification is long-pressed on the lock
screen. This is `UNNotificationCategory` + `UNNotificationAction` —
common to register at app launch but easy to silently break. Test
in simulator: trigger notification, lock with `Cmd+L`, long-press to
see actions. If they're not there, fix before shooting.

**3. Set up a StoreKit Pro test environment** *(blocks slots 5, 9, parts of 1, 3)*

Several screenshots show Pro-gated features (full analytics, HealthKit
correlation, all widgets). For shooting, you need a state where Pro is
unlocked **without** a paywall overlay or "Upgrade" CTAs in the way.
Two options:

- Use a StoreKit configuration file with a fake purchased subscription, OR
- Add a `#if DEBUG` flag that force-unlocks Pro for screenshot mode.

**4. Verify the day-of-week insight surfaces** *(blocks slot 5 annotation)*

Slot 5's foreground annotation is "Tuesdays slip — try a 7 AM reminder."
That insight has to come from your insight engine. Verify
`InsightService` (or wherever) actually generates day-of-week pattern
insights when given the seeded log history. If it doesn't, either:

- Add a day-of-week analysis pass (a few hours of work — calculate per-weekday adherence variance, surface if a day is >15% below average), OR
- Change slot 5's annotation to an insight your engine *actually*
  produces (e.g., "Streak record: 23 days — keep going.")

Either is fine. **Don't fake it on the screenshot.** Apple has rejected
apps for showing UI states that don't match the running app.

---

### 🟡 High priority — significantly improves screenshots

**5. Polish the HealthKit overlay chart styling** *(slot 3)*

The two-line overlay (HRV vs adherence) needs to be *visually
striking* on a 1320×2868 canvas. Verify:

- Both lines have 4–6pt stroke (anything thinner disappears at thumbnail size)
- Colors are emerald (#4ADE80) for adherence and cyan (#38BDF8) for HRV
- Subtle gradient fill below each line at ~12% opacity
- X-axis shows "5 weeks ago → today" not raw dates

**6. Achievement badge unlocked-state glow** *(slot 9)*

Verify unlocked badges render with the emerald glow effect from your
design system. If they're flat, add a `Material.regular` background or
a subtle outer shadow at the unlocked state. Locked badges should be
visibly desaturated, not just slightly faded.

**7. Medium widget composition** *(slot 7)*

The Medium widget needs to fit the **compliance ring + today's
schedule list** in one widget without truncation. Verify text scales
correctly with Dynamic Type at default. If the schedule clips, reduce
to "Next 2 doses" instead of full day.

**8. Watch complication for the modular face** *(slot 7)*

Whichever Watch face you screenshot for slot 7, make sure the PeptideX
complication looks polished at that size. The `.modularLarge`
complication is the easiest to make look good — it can show "Next
Dose · 2:30 PM · BPC-157" as three lines.

---

### 🟢 Medium priority — quality polish

**9. Insight bubble component** *(slot 5)*

Build a reusable "insight callout" bubble component if your insight
engine doesn't already have one. Used as a small floating card above
the heatmap. Keeps the slot 5 annotation real, not a Figma overlay.

**10. Paywall single-frame layout** *(slot 10)*

The paywall must show all 3 tiers + auto-renew disclosure + "Cancel
anytime" line in one viewport without scrolling. If yours scrolls,
tighten the spacing or move "Restore Purchases" into a small text
link instead of a full button.

**11. Empty state polish on Protocol Builder** *(slot 2)*

For slot 2, the builder is captured mid-flow, but adjacent UI
elements (placeholder text, ghost buttons) get into the frame. Make
sure all placeholder copy is sentence-case, no Lorem Ipsum, no
"<peptide name>" template strings.

**12. Settings → "Screenshot mode" toggle** *(meta — speeds up future shoots)*

A `#if DEBUG` setting that toggles:
- Force Pro unlocked
- Hide TestFlight/Debug banners
- Pin device clock to a specific time per slot
- Pin battery indicator to 100%
- Pin signal to full bars

You'll re-shoot screenshots every release. A 2-hour investment now
saves a day every time.

---

## Part 7 — Suggested seeder structure

Don't seed manually in the simulator UI — it's slow and error-prone.
Build a one-shot debug seeder. Rough shape (drop into a debug-only
Swift file under `Peptide/Debug/`):

```swift
#if DEBUG
import Foundation

enum ScreenshotSeeder {
    static func seedAll(modelContext: ModelContext) async {
        await purgeExistingData(modelContext)
        await seedProtocolJointRecovery(modelContext)
        await seedProtocolDailyFoundations(modelContext)
        await seedProtocolCognitiveRoutine(modelContext)
        await seedDoseHistory(modelContext)   // 35 days, 75% adherence, Tuesday gaps
        await seedAchievements(modelContext)  // 6 unlocked, 8 locked
        await seedHealthKitMocks()            // HKAnchoredObjectQuery fixtures
        await unlockProForScreenshots()       // sandbox StoreKit
    }
}
#endif
```

Wire it to a hidden gesture in DEBUG builds (e.g. 5-finger long-press
on the Profile tab) so you can re-seed in seconds before each shoot.

---

## Part 8 — Pre-shoot checklist

The night before you shoot:

- [ ] All 3 protocols built and active in seeded state
- [ ] 35 days of dose history seeded with the adherence pattern from §2
- [ ] 6 achievements unlocked, 8 locked
- [ ] HealthKit mocks loaded (HRV, sleep, RHR, steps)
- [ ] Pro unlocked in StoreKit sandbox
- [ ] Privacy Summary view exists and is reachable
- [ ] Lock-screen notification with "Mark as Taken" + "Snooze" verified
- [ ] Day-of-week insight (or whatever insight you're using on slot 5) is generating
- [ ] Both Small and Medium widgets render cleanly on a Home Screen
- [ ] Watch complication renders cleanly on the chosen Watch face
- [ ] Paywall fits in one viewport with disclosure visible
- [ ] All TestFlight / debug banners hidden
- [ ] Simulator status bar set: 9:41 AM (Apple's standard), 100% battery, full signal
- [ ] Dark mode confirmed
- [ ] Device set to **iPhone 16 Pro Max** for iPhone shoot, **iPad Pro 13-inch (M4)** for iPad shoot

---

*Companion to `APP_STORE_SCREENSHOTS_GUIDE.md`. Update both together on
every PeptideX release.*
