# Atlas — App Store Screenshot Generator Prompt

Paste the prompt below into Claude.ai (claude.ai/new) to generate a
polished HTML/CSS mockup for any of the 8 App Store screenshots.

Replace `[SLOT NUMBER]` and `[SLOT NAME]` with the screenshot you want.
The prompt is self-contained — Claude needs no other context.

---

## How to use

1. Copy everything inside the code block below.
2. Open claude.ai → New conversation.
3. Paste and send.
4. Claude will output a single HTML file. Copy the HTML, save as
   `screenshot-01.html`, open in Chrome/Safari at 1320 × 2868 viewport,
   then screenshot or print-to-PDF.
5. Repeat for each slot, changing only the `TARGET SCREENSHOT` line.

To export at retina: in Chrome DevTools (⌘⌥I) → toggle device toolbar →
set custom size 1320 × 2868 → right-click → "Capture screenshot".

---

## The prompt

```
You are a world-class mobile app designer creating App Store marketing
screenshots for Atlas — a dark-themed iOS fitness & recovery app.

Design language:
• Background: deep charcoal #0D0D12 with a subtle deep-purple gradient
  (#1A0D2E) in the upper third
• Glass cards: rgba(255,255,255,0.07) background, 1px rgba(255,255,255,0.12)
  border, 16px border-radius
• Accent colours: mint green #34D399 (Recovery/HRV), violet #7B5CFF (Pro),
  amber #F59E0B (sleep/habits), coral #F87171 (heart rate), blue #60A5FA
  (nutrition/macros), orange #FB923C (protein)
• Typography: SF Pro Display equivalent — use system-ui. Headlines 34px
  bold white, body 16px #A0A0B0
• Status bar: 9:41 AM · full battery · full signal (white text, dark bg)
• No lorem ipsum. Use realistic fitness data for every number.
• The output must be a SINGLE self-contained HTML file with all CSS inlined
  or in a <style> block. No external fonts, no external images.
  Use SVG or Unicode for all icons.

Canvas: 1320px wide × 2868px tall (iPhone 16 Pro Max App Store size).

Structure of every screenshot:
  Top 10%:  Realistic status bar + app navigation bar
  Middle 70%: The actual app screen content (see TARGET SCREENSHOT below)
  Bottom 20%: Marketing overlay — dark gradient fade, then:
              • Headline text (34px bold white)
              • Sub-caption (18px #A0A0B0)
              • [Pro badge if applicable] — pill, #7B5CFF background,
                white 13px text, reads "Atlas Pro — subscription required"

─────────────────────────────────────────────────────────────────
TARGET SCREENSHOT: [SLOT NUMBER] — [SLOT NAME]
─────────────────────────────────────────────────────────────────

SLOT 1 — TODAY / RECOVERY DASHBOARD
  Navigation bar: "Tuesday, June 3" left · avatar circle right
  Content (top to bottom):
    • Large Recovery Score ring (78%, 160px diameter) in mint green
      Centre: "78" bold 48px white · below it "Recovery" 14px #A0A0B0
    • Row of 3 stat tiles (glass cards, ~140px wide each):
        HRV: "62 ms" · up-arrow chip · label "Heart Rate Var."
        RHR: "54 bpm" · steady chip · label "Resting HR"
        Sleep: "7h 24m" · up-arrow chip · label "Last Night"
    • Workout card (glass, full width, 96px tall):
        Left: dumbbell icon · "Push Day" bold · "6 exercises" subtitle
        Right: "Start" pill button in violet #7B5CFF
    • Macro progress row:
        Calorie ring (60px): 1840/2400 kcal — 77%
        Protein: 142/195g bar (orange, 73%)
        Carbs: 198/265g bar (blue, 75%)
        Fat: 38/52g bar (yellow, 73%)
  Overlay:
    Headline: "Know if you're ready to train."
    Sub-caption: "Recovery Score · HRV · Sleep · Resting HR"
    No Pro badge.

SLOT 2 — ACTIVE WORKOUT / SET LOGGING
  Navigation bar: "Push Day" title · "Finish" button right (coral pill)
  Content:
    • Exercise header: "Bench Press" bold 24px · "(Chest, Triceps)" subtitle
      Personal record chip: "PR: 95 kg × 5" in amber
    • Set table (3 rows, glass card):
        Set 1 | 85 kg | 10 reps | ✓ (checkmark, green)
        Set 2 | 87.5 kg | 8 reps | ✓ (checkmark, green)
        Set 3 | 90 kg (ghost/pre-filled lighter) | 8 reps (ghost) | ○
        "+ Add set" row at bottom
    • Rest timer circle (80px diameter, amber stroke):
        "1:24" bold 28px centre
        "Rest" 12px label below
        Thin arc progress showing 56% complete (84s of 150s)
    • Muscle heatmap strip (full width, 100px tall, anatomical front/back
      silhouette SVG): chest and anterior deltoid lit in coral, rest dark
  Overlay:
    Headline: "Log sets in 2 taps."
    Sub-caption: "Pre-filled from last session · Auto rest timer · PR detection"
    No Pro badge.

SLOT 3 — MEAL SCANNER: PER-ITEM REVIEW
  Navigation bar: "Meal Scan" title · "✕" close button
  Content:
    • Camera preview area (full width, 320px tall, dark bg) showing a blurred
      plate silhouette with a subtle scan-line animation shimmer
    • "3 items detected" header in mint green 14px
    • 3 food item cards (glass, each ~110px tall):
        Card 1: "Chicken Breast" bold · "180g · 297 kcal" · macros chips
                (P 56g orange · C 0g blue · F 6g yellow)
                Portion stepper [−] 180g [+] · checkmark toggle (green, active)
        Card 2: "Brown Rice" bold · "150g · 195 kcal" · macros chips
                (P 4g · C 42g · F 1g)
                Portion stepper [−] 150g [+] · checkmark toggle (green, active)
        Card 3: "Broccoli" bold · "80g · 28 kcal" · macros chips
                (P 3g · C 5g · F 0g)
                Portion stepper [−] 80g [+] · checkmark toggle (green, active)
    • Macro summary row: 520 kcal total · P 63g · C 47g · F 7g
    • CTA button (full width, violet, 56px tall): "Add 3 items"
  Overlay:
    Headline: "Snap a photo. Every item logged."
    Sub-caption: "AI identifies each food · Edit portions · Save to library"
    No Pro badge.

SLOT 4 — BIOLOGY TAB: BIOLOGICAL AGE  [PRO]
  Navigation bar: "Biology" title (large) · cosmic background starts here
  Background: full-canvas deep-purple cosmic gradient #0D0020 → #1A0040
              ~200 tiny white dots (stars) scattered randomly
  Content:
    • "Biological Age" label 14px #A0A0B0 centred
    • "As of Jun 3, 2026" label 12px #6B6B80 centred
    • Bio Age Dial (240px wide, 240° arc):
        Arc spans −5 years (left) to +5 years (right) of chrono age 32
        Scale labels: "27" left · "37" right in small grey text
        Glowing needle pointing to −3.6 position
        Centre: "28.4" bold 56px in mint green (#34D399) with soft glow
    • Delta badge below dial: "3.6 years younger" pill — mint bg, dark text
    • Driver pills row: "HRV −2.5y" (mint) · "RHR −1.8y" (blue) · "SLEEP +0.7y" (amber)
    • Divider
    • Two biomarker rows (glass cards):
        Row 1: violet HRV icon · "Heart Rate Variability" · "Trending up · 62 ms"
               mini sparkline (14 points, upward trend, mint stroke)
        Row 2: coral RHR icon · "Resting Heart Rate" · "Steady · 54 bpm"
               mini sparkline (14 points, flat, coral stroke)
    • Footnote: "Estimates based on your personal biometrics — not medical advice"
      in 11px #505060 centred
  Overlay:
    Headline: "See your biological age."
    Sub-caption: "HRV · Sleep · Resting HR · Performance Age"
    Pro badge: YES — "Atlas Pro — subscription required"

SLOT 5 — NUTRITION TARGETS EDITOR
  Navigation bar: "Nutrition Targets" · "Done" button right
  Content (dark glass form):
    • Goal chip row: [Build Muscle ✓] [Lose Fat] [Maintain] — first active violet
    • Hero calorie display: "2,340" bold 64px white · "kcal / day" 16px #A0A0B0
    • Proportional macro bar (full width, 12px tall, rounded):
        Protein (orange) 35% · Carbs (blue) 45% · Fat (yellow) 20%
        Labels below bar: "Protein 35%" · "Carbs 45%" · "Fat 20%"
    • "Recommended for you" banner (glass, mint left border):
        "Based on Build Muscle goal · 80 kg · Moderately active"
        "Tap to apply" link in mint
    • 3 input cards (glass, stacked):
        Protein: "195" bold · "g / day" label · stepper arrows
        Carbs: "265" bold · "g / day" label · stepper arrows
        Fat:   "52"  bold · "g / day" label · stepper arrows
  Overlay:
    Headline: "Targets built for your goal."
    Sub-caption: "Goal-aware recommendations · Live macro preview"
    No Pro badge.

SLOT 6 — HABITS: 6-MONTH HEATMAP
  Navigation bar: "Habits" · "+ New" button
  Content:
    • "2 active habits" section header
    • Habit card 1 (glass, full width, ~200px tall):
        Left: fire emoji icon in amber circle
        "Morning Walk" bold 20px · "47-day streak 🔥" subtitle amber
        6-month heatmap grid below (52 columns × 7 rows):
          Most cells filled mint green (80%), ~15% amber (partial), ~5% empty
          Week labels left: M W F · Month labels top: Jan Feb Mar Apr May Jun
    • Habit card 2 (glass, full width, ~140px tall):
        Left: snowflake icon in blue circle
        "Cold Shower" bold 20px · "12-day streak" subtitle
        Mini heatmap (last 8 weeks only): mostly blue with some gaps
    • "+ Add habit" row at bottom (dotted border glass card)
  Overlay:
    Headline: "Build momentum that sticks."
    Sub-caption: "Daily streaks · 6-month heatmap · Smart reminders"
    No Pro badge.

SLOT 7 — PROTOCOLS: DOSE LOG
  Navigation bar: "BPC-157 + TB-500" · compliance ring top-right (87%, green)
  Content:
    • Protocol header glass card:
        "BPC-157 + TB-500" bold · "Active · Day 14 of 84" subtitle
        Two compound chips: [BPC-157 250mcg] [TB-500 2mg] in tinted pills
        Research citations chip: "2 compounds · 4 citations"
    • "Today" section header (mint)
    • Dose card (glass, 96px): checkmark green circle left
        "BPC-157" bold · "250 mcg · Sub-Q abdomen" · "Taken 7:31 AM" in green
    • "Upcoming" section header
    • Dose card (glass, 96px): clock amber circle left
        "TB-500" bold · "2 mg · Sub-Q abdomen" · "Due 8:00 PM" in amber
    • Divider — "History" section header
    • 3 smaller history rows with dates and green checkmarks
    • Footnote chip: "⚠ Atlas does not recommend or prescribe doses" 11px
  Overlay:
    Headline: "Track every protocol. Down to the dose."
    Sub-caption: "208 compounds · Dose log · Reminders · Community stacks"
    No Pro badge.

SLOT 8 — PAYWALL
  No navigation bar. Full dark background.
  Content (top to bottom):
    • Atlas logo glyph (abstract mountain/triangle SVG) 48px · "ATLAS" 16px
      tracking-widest #A0A0B0
    • "Atlas Pro" bold 36px white centred
    • Feature list (5 bullets, 16px #D0D0E0, left-aligned, centred block):
        ∙ Unlimited protocols
        ∙ Biological Age + full Biology tab
        ∙ AI Research assistant
        ∙ Apple Watch + all widgets
        ∙ Cloud sync & data export
    • Three plan cards stacked (glass, full width, 80px each):
        Card 1 (violet border, "BEST VALUE" chip top-right):
          Left: "Annual" bold · "$49.99 / year" · "14-day free trial" mint
          Right: ">" chevron
        Card 2:
          Left: "Monthly" bold · "$9.99 / month" · "3-day free trial" mint
          Right: ">" chevron
        Card 3:
          Left: "Lifetime" bold · "$169" · "One-time purchase" #A0A0B0
          Right: ">" chevron
    • "Start Free Trial" CTA button (full width, violet, 56px, bold white)
    • Auto-renew disclosure (11px #606070 centred):
      "Subscription auto-renews. Cancel anytime in Apple ID Settings."
    • Links row: "Terms of Use" · "·" · "Privacy Policy" in 12px #7B5CFF
  Overlay caption area:
    Headline: "Try free. Upgrade when ready."
    Sub-caption: "14-day free trial on annual · Cancel anytime"
    No Pro badge.

─────────────────────────────────────────────────────────────────
Generate the complete HTML for the slot specified above.
Output ONLY the HTML. No explanations. No markdown wrapper.
The file must render correctly when opened locally in a browser.
Use only inline SVG, Unicode characters, and CSS — no external resources.
```

---

## Tips for best results

**Getting sharp exports from the browser:**
```bash
# After opening the HTML in Chrome, use DevTools device emulation
# Set exact dimensions: 1320 × 2868
# Then: right-click → Inspect → ⌘⌥I → device toolbar → Custom: 1320 × 2868
# Screenshot: ... menu → Capture screenshot
```

**Batch all 8 in one session:**
Ask Claude to generate them one at a time in the same conversation.
The design tokens (colours, fonts, layout rules) carry through because
they're in the system prompt at the top.

**Customising with real data:**
After Claude generates the HTML, find the hardcoded numbers and swap in
your actual values (your real streak count, your real Recovery Score
from the past week, etc.) — realistic data converts significantly
better than placeholder numbers.

**Iteration:**
If a section looks off, paste the HTML back to Claude and say:
"The [element] looks [issue]. Fix only that section, keep everything else."
Claude will patch the specific CSS/HTML without regenerating the whole file.

**Final production screenshots:**
Use the AI mockup as a layout reference, not as the final asset.
The real screenshots (captured from the app on a physical iPhone 16 Pro Max)
should be composited with the overlay layers in Figma, Sketch, or Canva —
use the Claude mockup to get the caption positions and colour palette right,
then place the real app UI underneath.
