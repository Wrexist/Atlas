# PeptideX — App Store Screenshots: The Perfect Guide

A complete production playbook for PeptideX's iOS App Store screenshots.
Covers all 10 slots, copy, design system, tools, App Review risk, and a
shooting checklist.

> **Read this first.** PeptideX sits in Health & Fitness with Medical as a
> secondary category and a 17+ age rating. App Review treats peptide apps
> with elevated scrutiny because many compounds in the database are
> research chemicals not approved for human use. Screenshots are the most
> visible piece of marketing on the listing, and they are reviewed.
> **Sell the tracker, not the substances.** Every guideline below is
> written with that constraint in mind.

---

## 1. The strategy in 60 seconds

The 10 slots are not 10 ads — they're a narrative. Order them so a user
swiping left to right gets the story:

| Slot | Job | What it answers |
| --- | --- | --- |
| 1 | **Hook** | "What is this and why should I care?" |
| 2 | **Core loop** | "What will I actually do every day?" |
| 3 | **Differentiator** | "Why this app and not a notes app or a spreadsheet?" |
| 4 | **Depth — library** | "Does it cover what I'm running?" |
| 5 | **Depth — analytics** | "Will it give me real insight, not just logs?" |
| 6 | **Reminders / reliability** | "Will it actually help me stay consistent?" |
| 7 | **Ecosystem (Widgets + Watch)** | "Does it fit into my day?" |
| 8 | **Privacy** | "Where does my data go?" *(killer trust slide for this audience)* |
| 9 | **Motivation (achievements)** | "Will I keep using it?" |
| 10 | **Pro / closer** | "What do I get if I upgrade?" |

Apple shows the **first 3 portrait screenshots** in search results. Treat
slots 1–3 as your conversion engine — every word and pixel earns its place.
Slots 4–10 are for users already on the listing page; they reduce
"is this really for me" hesitation.

---

## 2. Required dimensions & deliverables

Apple scales the largest size you upload down to smaller devices, so you
only need the largest per device family. Match exactly what
`APP_STORE_METADATA.md` already specifies plus 6.5" as a defensive backup:

| Device class | Pixel size (portrait) | Required? | Count |
| --- | --- | --- | --- |
| iPhone 6.9" (16 Pro Max) | **1320 × 2868** | Yes | 3–10 |
| iPhone 6.5" (11 Pro Max) | 1242 × 2688 | Optional but recommended | 3–10 |
| iPad Pro 13" (M4) | **2064 × 2752** | Yes (you target iPad) | 3–10 |

**Format:** PNG or JPEG, sRGB or P3, no alpha, no rounded corners (Apple
adds them). Keep file size under ~8 MB each.

**Localization:** PeptideX ships English (U.S.) at v1.0 per the metadata
doc. Don't localize screenshots until you localize the app — mismatches
get rejected.

---

## 3. The PeptideX visual system for screenshots

Build all 10 slots inside a single Figma file with these tokens. Consistency
is what makes a listing look *premium* — even one off-brand slide drops
conversion.

### Color tokens

```
Background gradient    #0A0F1E  →  #141A33      (deep navy, top → bottom)
Surface (cards)        #1B2138  at 60% opacity, 1px stroke #2A3050
Primary accent         #4ADE80  (emerald — clinical, trustworthy, ≠ pharma red)
Secondary accent       #38BDF8  (cyan — for HealthKit / data overlays)
Warning / streak       #FB923C  (amber — for streak visualizations only)
Text primary           #F4F6FB
Text secondary         #9AA3B8
Disclaimer chip BG     #1F1208  /  text  #FBBF24   (used on slide 4 + 10)
```

Why emerald instead of red: red codes as "pharma / emergency / warning."
Emerald codes as "health, growth, positive." Apple's own Activity rings
also avoid medical red for daily-tracking contexts.

### Typography

Use **SF Pro Display** for everything — it's free, ships with macOS, and
matches the device frame so the marketing layer feels native.

```
Hero headline    SF Pro Display, Bold, 120pt, -2% tracking, 1.05 line height
Sub-headline     SF Pro Display, Medium, 56pt, -1% tracking
Caption          SF Pro Display, Regular, 36pt
Inline label     SF Pro Text, Semibold, 28pt, +2% tracking, UPPERCASE
```

### Layout grid (all slots)

```
Canvas:   1320 × 2868 (iPhone 6.9")
Margins:  120 px left/right, 160 px top, 200 px bottom
Top zone: ~720 px tall — headline + sub-headline
Mid zone: ~1700 px — device frame OR live UI mock
Foot:     ~248 px — small caption / disclosure / Pro chip
```

The device frame should be **iPhone 16 Pro Max in Titanium Black** with
~88% scale so the screen fills the mid-zone but you still see the frame
edges. Frames give the screenshot "object permanence" — without one the
UI looks flat and is harder to parse.

### Background treatment

Don't ship raw flat gradients. Add one of these depth layers (low opacity,
3–5%):

- **Slots 1, 2, 6, 7, 10:** subtle radial glow behind the device, emerald or cyan, 8% opacity
- **Slots 3, 5:** thin grid (40px squares, 2% white) — reads as "data / analytics"
- **Slots 4, 8, 9:** soft noise / grain at 1.5% to kill banding

Never use stock photos of pills, syringes, or muscle imagery. It will
both attract App Review trouble and code as cheap supplement-ad
aesthetic — the opposite of where you want PeptideX to sit.

---

## 4. The 10 slots, in order

Each slot below has: **what to capture, the headline, the sub-headline,
the foreground annotation (if any), and notes specific to App Review
safety.**

---

### Slot 1 — HERO: "Today" view (compliance ring + next dose)

**Capture:** Home / Today screen with the day's compliance ring at ~70%
filled, "Next dose in 1h 22m" card showing, plus 2–3 logged doses below.
Use realistic but generic peptide names (not the most controversial ones —
prefer e.g. "BPC‑157," "Thymosin α‑1," "Glutathione" over anything Apple
might flag in a hero).

**Headline:** `Run Your Protocol Like a Pro`
*(5 words, punchy, no medical claim — emphasizes process not outcomes.)*

**Sub-headline:** `Schedule, log, and stay consistent — all on-device.`

**Foreground annotation:** Floating callout pointing at the ring:
"**67%** weekly compliance" — small chip, 28pt, set against the device.

**Why this slot:** It carries 80% of conversion weight. The ring is the
single most recognizable visual you have (Activity-ring shorthand =
"this is a health app I understand"). Pairing it with the headline
"Run your protocol" tells a peptide user instantly "yes, this is for me."

**App Review risk:** Low. Tracker framing, no efficacy claim, no
substance promotion.

---

### Slot 2 — CORE LOOP: Protocol builder

**Capture:** Protocol builder mid-edit. Show: schedule selector
(Daily / Cycled / Weekly), one peptide line item with dose + time +
injection site, plus the "Add to schedule" CTA. Use a *cycled*
protocol (e.g., "5 days on / 2 off") because that's distinctive vs. a
generic medication tracker.

**Headline:** `Any Schedule. Any Cycle.`

**Sub-headline:** `Daily, weekly, or cycled — the way real protocols actually run.`

**Foreground annotation:** A small UI "ghost" of a second screen showing
"Pause cycle → Resume in 14 days" — implies depth without cluttering.

**Why this slot:** Cycled scheduling is the #1 reason general medication
trackers fail this audience. Calling it out in slot 2 immediately
disqualifies competitors from the user's mental shortlist.

**App Review risk:** Low — process language ("schedule," "cycle") not
prescriptive ("take," "dose at").

---

### Slot 3 — DIFFERENTIATOR: HealthKit correlation

**Capture:** Analytics → HealthKit correlation view. Two overlaid line
charts: HRV (top) and weekly compliance % (bottom), with a subtle
shaded band where the two correlate. Plus a small caption row: "Heart
rate · HRV · Sleep · Activity."

**Headline:** `See What Your Body Says Back`

**Sub-headline:** `Read‑only HealthKit correlation. HRV, sleep, activity — overlaid on adherence.`

**Foreground annotation:** Apple Health glyph + chip:
`Read‑only · Never written`. Critical for both review and for the
privacy-conscious target user.

**Why this slot:** This is the hardest feature for a competitor to copy —
most trackers don't touch HealthKit, and the ones that do usually
*write* to it (which sketches users out). "Read-only" is a real
differentiator and Apple's reviewers will love seeing it surfaced.

**App Review risk:** Low *if* the "read-only" language is on the
screenshot itself. Without it, Apple sometimes asks for clarification
on health data usage. Bake the disclosure in.

---

### Slot 4 — DEPTH: Peptide library

**Capture:** Peptide database screen with the search bar visible, the
6 category chips (Healing · Metabolic · Cognitive · Longevity ·
Performance · Immune) horizontally scrollable, and ~6 peptide cards
visible. Each card shows name, category tag, and a small "Research"
chip — *not* dosage suggestions, *not* efficacy claims.

**Headline:** `208 Peptides, One Search Away`

**Sub-headline:** `Six categories. Research links on every entry.`

**Foreground annotation:** Small disclaimer chip at the very bottom
inside the device frame: `Educational reference. Not medical advice.`
This single chip materially de-risks the entire screenshot for review.

**Why this slot:** Library breadth is the strongest "is my peptide in
here" question-killer. The category pill row also visually broadcasts
"this is organized, not a junk drawer."

**App Review risk:** **Medium.** This is the screenshot most likely to
draw a question. Mitigations: (1) no dosage numbers in the visible
cards, (2) no health claim language, (3) the "Educational reference"
chip is on-screen, (4) avoid showing the most controversial substances
(MT‑II, GHRP‑6 etc.) in this hero capture — pick boring, well-studied
ones (Glutathione, BPC‑157, Thymosin α‑1, Glycine, NAD+, Selank).

---

### Slot 5 — DEPTH: Analytics (heatmap + streak)

**Capture:** Analytics tab showing the weekly heatmap (GitHub-style,
emerald palette), the current streak counter ("23 days"), and a small
trend line below. Pick a state where the heatmap has *some* gaps — a
perfect grid looks fake and brags too hard.

**Headline:** `Spot the Drift Before It Costs You`

**Sub-headline:** `Streaks, heatmap, day‑of‑week patterns. Built on Swift Charts.`

**Foreground annotation:** A small bubble near a Tuesday gap:
"Tuesdays slip. Try a 7am reminder." This makes the *insight engine*
feel real, not just decorative. (Make sure your insight engine actually
generates this kind of suggestion — never fake it on a screenshot.)

**Why this slot:** "I have a tracker but I never look at it" is the
default failure mode. This slide promises insight, not just storage.

**App Review risk:** Low.

---

### Slot 6 — RELIABILITY: Smart reminders

**Capture:** A composited shot: the iOS lock screen at the top half
showing a PeptideX rich notification with **"Mark as Taken"** and
**"Snooze"** action buttons; the bottom half shows the in-app
"Reminders" settings. Time on the lock screen: realistic, e.g. 7:00 AM.

**Headline:** `Reminders That Actually Help`

**Sub-headline:** `One‑tap log from the lock screen. Per‑slot consolidation, no spam.`

**Foreground annotation:** Tiny "64‑notification limit handled
automatically" caption. Power users *love* this — it signals the
developer actually knows iOS.

**Why this slot:** Reminders are the #1 reason adherence trackers
succeed or fail. Showing the rich notification with action buttons
demonstrates competence in 1 second.

**App Review risk:** Low. Generic notification UI.

---

### Slot 7 — ECOSYSTEM: Widgets on Home Screen + Watch

**Capture:** A staged Home Screen on iPhone with the Small widget
("Next dose · 2:30 PM · BPC‑157") in one corner and the Medium widget
(today's compliance ring + schedule list) below it. Inset on the side:
the Apple Watch face showing the next-dose complication.

**Headline:** `On Your Wrist. On Your Home Screen.`

**Sub-headline:** `Glanceable widgets and an Apple Watch app.`

**Foreground annotation:** None — the visual density is already high.

**Why this slot:** Widgets + Watch = "this developer ships the whole
Apple platform," which signals quality and ongoing support. Worth a
full slot even if widgets feel "small" relative to analytics.

**App Review risk:** Low.

---

### Slot 8 — TRUST: Privacy

**Capture:** A clean privacy summary screen — design this one
specifically for the App Store if it isn't already a screen in-app.
Centered list of icons + lines:

- 🛡️  No analytics. No trackers.
- 📵  No backend. No remote push.
- 🔐  Sign in with Apple, optional. Stored in Keychain only.
- ☁️  iCloud sync uses your private database — we never see it.
- 📤  Export everything. Anytime.

**Headline:** `Your Data Doesn't Leave Your Phone`

**Sub-headline:** `Zero analytics SDKs. Zero advertising. Verified by privacy manifest.`

**Foreground annotation:** Small Apple logo + `Privacy Nutrition Label: No data collected`
chip — directly cites the App Privacy section reviewers will see.

**Why this slot:** *This is the slot most apps skip and it's PeptideX's
strongest weapon.* Peptide users are unusually privacy-aware. Most
trackers in the space are hot garbage on this dimension (Firebase,
Mixpanel, ad SDKs). Calling out "zero analytics" with receipts
(privacy manifest) is a wedge that converts. It also tees up review
favorably — Apple loves apps that surface privacy as a feature.

**App Review risk:** **Verify before you ship.** The claims on this
screenshot must exactly match the App Privacy questionnaire and your
`PrivacyInfo.xcprivacy`. Per `APP_STORE_METADATA.md` they currently do
(no third-party SDKs, no `URLSession` to your servers). Re-verify
before each release.

---

### Slot 9 — RETENTION: Achievements

**Capture:** Achievements screen showing 4–6 unlocked badges (with
emerald glow) and 2–3 locked (greyed). Mix the categories: a streak
badge (e.g. "30‑Day Streak"), a milestone badge ("100 Doses Logged"),
a consistency badge ("Perfect Week"). Don't show anything labeled
"weight," "muscle," "fat" — keep all achievement names process-based.

**Headline:** `Consistency, Rewarded`

**Sub-headline:** `14 achievements across streaks, milestones, and weekly perfection.`

**Foreground annotation:** Optional small "Tap any badge for the story"
caption — positions achievements as content, not gamification fluff.

**Why this slot:** Tells the user "you'll keep using this." Most
peptide trackers fall off after week 2; achievements + streaks are the
single best retention mechanic, and showing them on the listing seeds
the habit before install.

**App Review risk:** Low — provided no achievement names imply
medical outcomes.

---

### Slot 10 — CLOSER: Pro pricing

**Capture:** Paywall screen, three pricing tiers visible
(Monthly $9.99 · Annual $49.99 · Lifetime $169), with the Annual
option highlighted as "Best value · 14‑day free trial." Below: a
4-bullet feature list (Unlimited protocols · Full analytics + HealthKit
correlation · AI insights · Full CSV/JSON/PDF export). Auto-renew
disclosure visible at the bottom (Apple requires this in-app and you
already have it per your metadata doc).

**Headline:** `Unlock the Full Picture`

**Sub-headline:** `Try Pro free for 14 days. Or own it once with Lifetime.`

**Foreground annotation:** Tiny inline caption: "Cancel anytime in
Settings." Reduces purchase anxiety.

**Why this slot:** Slot 10 catches the small but high-intent group of
users who scrolled all the way. They're already considering — closing
with the offer (free trial OR Lifetime) is much more effective than
another feature pitch.

**App Review risk:** **Medium.** Apple checks IAP screenshots against
the actual paywall. The prices, free trial lengths, and auto-renew
disclosure on the screenshot must match StoreKit and the in-app
paywall *exactly.* If you change pricing later, re-shoot this slot
before you submit the next build.

---

## 5. Headline copy bank (alternates for A/B testing)

App Store Connect's **Product Page Optimization** lets you test up to 3
variants of the first screenshot against the default. Set up the
following A/B once you're past 1,000 weekly visitors — below that the
results are noise.

| Slot | Default | Variant A (benefit) | Variant B (identity) |
| --- | --- | --- | --- |
| 1 | Run Your Protocol Like a Pro | Stay Consistent. See the Pattern. | Built for Serious Protocols |
| 2 | Any Schedule. Any Cycle. | Cycles That Actually Cycle | The Schedule Engine |
| 3 | See What Your Body Says Back | Connect to Apple Health. Read‑Only. | HRV. Sleep. Adherence. One View. |

Don't test more than one slot at a time, and run each test for at least
14 days.

---

## 6. App Review safety checklist (peptide-specific)

Apple has approved peptide trackers, but rejections happen on these
exact failure modes — the list below is what to verify on every
screenshot before submitting.

**Hard NOs across all 10 slots:**

- ❌ No before/after photos. Ever.
- ❌ No "weight loss," "muscle gain," "fat burning," "anti‑aging,"
  "performance enhancement" language anywhere on a screenshot.
- ❌ No specific dosage numbers paired with claims of effect (e.g.
  "5mg = better sleep" — fine to show "5mg" in a log, not paired with
  outcome copy).
- ❌ No images of syringes, vials, or pills as decoration. Diagrams of
  injection *sites* inside the app UI are fine; "marketing imagery" of
  injection paraphernalia is not.
- ❌ No quotes like "Doctor recommended," "FDA approved" — peptides are
  not, and Apple knows.
- ❌ No real human in any way that could read as a testimonial without
  disclosure.

**Required YES on at least one screenshot (slot 4 is the natural home):**

- ✅ Visible "Educational reference. Not medical advice." chip OR
  the equivalent disclaimer wording from your in-app medical disclaimer.

**Verify on slots 3, 8, 10:**

- Slot 3: "Read‑only" disclosure on HealthKit slide.
- Slot 8: Privacy claims match the App Privacy questionnaire and the
  privacy manifest *exactly*.
- Slot 10: Pricing, trial length, auto-renew disclosure match StoreKit
  and the in-app paywall *exactly*.

---

## 7. Production workflow

Day-by-day, this is a 2-day project for one person.

### Day 1 — capture

1. **Seed the simulator with realistic data.** Build a small Swift
   command in `#if DEBUG` (or use the snapshot test target you already
   have under `PeptideTests/`) that populates:
   - 1 active cycled protocol with 3 peptides
   - 5 weeks of dose log history at ~75% adherence (so the heatmap and
     streak look earned, not perfect)
   - 6 unlocked achievements
   - HealthKit mocked HRV / sleep data via `HKObserverQuery` test
     fixtures (or pre-recorded fixtures — never ship to a reviewer with
     real Health data tied to your Apple ID).

2. **Capture in the simulator** at the exact 6.9" device:

   ```bash
   xcrun simctl boot "iPhone 16 Pro Max"
   xcrun simctl io booted screenshot ~/Desktop/peptidex-01.png
   ```

   Capture in **Light or Dark mode consistently across all 10 slots** —
   given the deep navy background system above, **Dark mode** is the
   right choice for PeptideX.

3. **Verify dimensions:** every PNG must be exactly **1320 × 2868**.
   `sips -g pixelWidth -g pixelHeight peptidex-01.png` to check.

4. **Repeat for iPad 13"** — `iPad Pro 13-inch (M4)` simulator,
   2064 × 2752.

### Day 2 — design

5. **Build a Figma file** with one frame per slot at 1320 × 2868.
   Drop in the design tokens above as Figma styles + variables.

6. **Place the iPhone 16 Pro Max device frame** (Apple ships official
   PSDs at https://developer.apple.com/design/resources/ — use those,
   not third-party frames).

7. **Drop each captured screenshot into its frame**, add headline and
   sub-headline using the typography scale.

8. **Export each frame** at 1× PNG, sRGB, no compression.

### Tools

- **Figma** (free) — primary design tool. One file, 10 frames, share
  link in your repo.
- **Screenshot.rocks** or **Mockuuups Studio** — only if you don't want
  to build the frame system in Figma. Acceptable shortcut for v1.0,
  but Figma scales better when you ship updates.
- **Apple Design Resources** — official device frames + UI kits.
- **Picsew** (iOS) — long-screenshot stitching if you ever need a tall
  scroll capture for marketing site (not for App Store).
- **Fastlane Frameit** — automate the framing if you'll re-shoot every
  release. Worth setting up after v1.0.

### File naming convention

```
01-hero-today.png
02-protocol-builder.png
03-healthkit-correlation.png
04-peptide-library.png
05-analytics-heatmap.png
06-reminders.png
07-widgets-watch.png
08-privacy.png
09-achievements.png
10-paywall.png
```

Mirror in `screenshots/iphone-69/` and `screenshots/ipad-13/` under
`docs/` so the next build of these is a `git diff`, not a treasure
hunt.

---

## 8. iPad screenshots (the cheat code)

You don't need to redesign for iPad. The required workflow:

1. Run the app on the iPad Pro 13" simulator.
2. Capture the same 10 screens at 2064 × 2752.
3. In Figma, **duplicate the iPhone frame system at iPad dimensions**,
   keep the same headline copy, swap in the iPad screenshots.
4. Adjust headline placement so it doesn't collide with iPad's wider UI.

Optional but high-leverage: for slot 1 on iPad, use a **landscape**
hero (2752 × 2064) since iPad apps are often used landscape and
landscape screenshots stand out in the iPad listing.

---

## 9. App Preview video (optional, very high ROI)

Apple lets you upload up to 3 short videos (15–30 seconds, portrait
886 × 1920 or 1080 × 1920) above the screenshots. Apps with a preview
video convert ~15–25% better at the same listing position.

For PeptideX v1.1, plan a single 20-second preview cutting through:

```
0:00–0:03   Today screen — compliance ring fills
0:03–0:07   Tap a dose card → log it → confetti micro‑interaction
0:07–0:11   Swipe to Analytics → heatmap → HRV overlay
0:11–0:15   Home Screen showing widgets + Watch face
0:15–0:20   Privacy summary → logo → "PeptideX. Run your protocol."
```

Capture with **simctl recordvideo** + **iMovie** or **CapCut** for
free; **ScreenFlow** if you want to invest. No music with lyrics, no
copyrighted tracks — Apple rejects on this regularly. Use a royalty-free
ambient track from Epidemic Sound or Artlist.

---

## 10. Submission-day checklist

Tick each before hitting Submit. Skipping any of these is the most
common reason for a 1–3 day rejection cycle.

- [ ] All 10 iPhone 6.9" screenshots uploaded, named, and ordered correctly
- [ ] All 10 iPad 13" screenshots uploaded, named, and ordered correctly
- [ ] Slot 4 has the "Educational reference. Not medical advice." disclaimer chip
- [ ] Slot 3 has the "Read‑only" HealthKit chip
- [ ] Slot 8 privacy claims match `PrivacyInfo.xcprivacy` and the App Privacy questionnaire
- [ ] Slot 10 prices and trial lengths match StoreKit (Monthly $9.99 / 7‑day · Annual $49.99 / 14‑day · Lifetime $169 / no trial)
- [ ] No before/after photos, no efficacy language, no syringe imagery
- [ ] No real-person testimonial without explicit disclosure
- [ ] Captured in Dark mode consistently across all 10
- [ ] All headlines under 6 words; sub-headlines under 12 words
- [ ] Device frames are official Apple resources (no third-party "premium" frames with logos)
- [ ] Originals saved to `docs/screenshots/` in the repo
- [ ] Figma source file linked in `docs/` README

---

## 11. After launch — what to measure & change

Inside App Store Connect → App Analytics, watch:

- **Impressions → Product Page Views (CTR).** If under ~3%, slot 1
  hero or icon needs work.
- **Product Page Views → Downloads (conversion).** If under ~25%,
  slots 2–10 aren't closing — usually slot 8 (privacy) or slot 10
  (paywall clarity) is the lever.
- **Search keyword rank** for the keyword set in `APP_STORE_METADATA.md`.
  If you rank well but don't convert, screenshots are the suspect.

Set a 60-day re-shoot calendar reminder. Apps that update screenshots
quarterly outperform apps that ship once and forget — both because the
content reflects new features and because Apple's algorithm seems to
slightly favor active listings.

---

*Last updated for PeptideX v1.0. Re-verify the App Review safety
checklist (§6) and submission checklist (§10) before every submission.*
