---
name: atlas-screen
description: Build or reshape a screen in the Atlas iOS app. Loads the design system's non-negotiables and the reference-app transplant method so a new surface lands on the existing visual language instead of inventing a parallel one. Use when building, redesigning, or reviewing any SwiftUI view in this repo.
---

# Atlas screen

Build the screen: $ARGUMENTS

## 1. Steal a shape before you invent one

Load the **`dna-transplant`** skill first — it holds the donor table and the
field-mapping discipline. This section only records which donor each Atlas
surface already uses, so a new screen joins the existing language rather than
starting a second one.

| Data shape | Donor | Already used in |
|---|---|---|
| One number that is the point of the screen | Fitness ring / Bevel dial | `BioAgeDial`, `MetricRing` |
| 3–5 peer metrics, glanceable | Activity ring trio | `HeroMetricTrio` |
| A value over time with a target | Stocks row + sparkline | `BiomarkerRow` + `BiomarkerSparkline` |
| Mixed events in time order | Wallet transaction list | `TodayTimelineCard` |
| Things with state, one tap to advance | Reminders checklist | `TodayScheduleCard` |
| A streak or habit | Duolingo flame | `HabitRowCard` |
| Something aspirational behind a paywall | Apple One card | `PremiumPromoCard` |

If your data has no home in any of these, that's the signal to reach for a
new donor from `dna-transplant` — not to bolt a slot onto one of these.

## 2. Use the primitives — all of them exist

Reaching for a raw `Button`, `RoundedRectangle`, or `Font.system` means the
screen will drift. There is exactly one of each:

- **Button** — `GlassButton(title:icon:style:isFullWidth:)`, styles
  `.primary` / `.secondary` / `.ghost` / `.destructive`. Icon-only:
  `GlassIconButton`, which *requires* an accessibility label.
- **Card** — `GlassCard` / `GlassCardCompact`, or `.glassCard(...)` on any view.
- **Row** — `GlassEntryRow` for a labelled entry that opens something.
- **Empty state** — `EmptyStateView`, `.fullScreen` or `.compact`. Every
  empty state names the next action.
- **Segmented control** — `GlassSegmentedControl`.
- **Ring / bar** — `MetricRing`, `GlassProgressBar`.
- **Sheet** — `.liquidGlassPresentation(detents:)`.
- **Loading** — `.shimmer()` on a placeholder shape, never a bare spinner
  where a skeleton would show the shape of what's coming.

## 3. The four token rules

These are enforced by `scripts/design-lint.py` (which gates CI), by
SwiftLint `custom_rules`, and by there being one obvious primitive. See the
"Design system" section of `README.md`.

- **Colour** — `AppColor` only. Never `Color(hex:)`, `Color(red:)`, or
  `Color.white` in `Features/`. Surface and ink tokens resolve per trait
  collection, which is what makes light mode work; a literal opts that
  screen out silently. Ink *on* an accent fill is `AppColor.onAccent`; ink
  on a wash or the app background is `AppColor.textPrimary`.
- **Type** — the `AppFont` ramp, or `AppFont.scaled(_:weight:design:)` for a
  size the ramp doesn't carry. `Font.system(size:)` ignores Dynamic Type
  outright. Above 24pt is a display glyph and may stay fixed.
- **Glass** — `glassSurface(cornerRadius:tinted:)` for cards,
  `glassControl(_:tint:border:)` for controls. Never stack a fake fill under
  a real `glassEffect`. Keep tints at 0.15–0.20.
- **Metrics** — radii from `Spacing`; nested shapes use
  `Spacing.concentric(in:inset:)`. Any control whose artwork is under 44pt
  gets `.minimumHitArea()`, applied last so it grows the target and not the
  artwork.

## 4. Craft checks before you call it done

- No gradient used as decoration — only to carry meaning (an accent fill, a
  ring's progress). No glow that isn't a real shadow.
- No `transition`/`animation` applied to everything; animate the specific
  property that changed, through `AppAnimation`.
- No placeholder copy. Every string is the string that ships.
- Nothing recomputed in `body` that touches disk, allocates a formatter, or
  runs an engine pass — hoist it into `@State` fed by `.task(id:)`.
- Every row a VoiceOver user hits is one stop, not five:
  `.accessibilityElement(children: .combine)` with decorative glyphs hidden.
- Read the screen at the largest Dynamic Type size and in light mode. Both
  are real now, and neither can be checked without running the app.

## 5. Verify

Run `python3 scripts/design-lint.py --all`. It mechanises most of section 4
and is at zero findings today, so anything it prints is yours.

There is no headless way to render this app. Build for an iOS 18+
simulator, and check Liquid Glass surfaces on iOS 26 specifically — the
material is a no-op below that and the fallback recipe is what you'll see.
