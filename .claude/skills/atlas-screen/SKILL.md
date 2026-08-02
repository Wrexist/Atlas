---
name: atlas-screen
description: Build or reshape a screen in the Atlas iOS app. Loads the design system's non-negotiables and the reference-app transplant method so a new surface lands on the existing visual language instead of inventing a parallel one. Use when building, redesigning, or reviewing any SwiftUI view in this repo.
---

# Atlas screen

Build the screen: $ARGUMENTS

## 1. Steal a shape before you invent one

Atlas's strongest surfaces are transplants — an idiom Apple already taught
the user, refitted to health data. Pick the reference *first*, then map it
field by field. Inventing a novel layout is the fallback, not the default.

| The data you have | The idiom to transplant | Already used in |
|---|---|---|
| One number that is the point of the screen | Fitness ring / Bevel dial — big glyph, thin arc, delta underneath | `BioAgeDial`, `MetricRing` |
| 3–5 peer metrics, glanceable | Activity's ring trio — equal weight, no hierarchy between them | `HeroMetricTrio` |
| A value over time with a target | Stocks row — name, current value, sparkline, signed delta | `BiomarkerRow` + `BiomarkerSparkline` |
| A chronological log of mixed event types | Wallet transaction list — one row per event, type as a leading glyph | `TodayTimelineCard` |
| A set of things with state, one tap to advance | Reminders checklist — the tap target *is* the row | `TodayScheduleCard` |
| A streak or habit | Duolingo flame — the count is the hero, the calendar is secondary | `HabitRowCard` |
| Something aspirational behind a paywall | Apple One card — dark gradient, one promise, one CTA | `PremiumPromoCard` |

Write the mapping down before writing the view. If a field in your data has
no home in the idiom, that's a signal the idiom is wrong — not a reason to
bolt on a slot.

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

These are enforced by SwiftLint `custom_rules` and by there being one
obvious primitive. See the "Design system" section of `README.md`.

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
- **Metrics** — radii and hit targets from `Spacing`. Nested shapes use
  `Spacing.concentric(in:inset:)`. Tap targets use `Spacing.minimumHitTarget`.

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
  are now real; neither is checked by CI.

## 5. Verify

Run `python3 scripts/design-lint.py --all`. It mechanises most of section 4
and is at zero findings today, so anything it prints is yours.

There is no headless way to render this app. Build for an iOS 18+
simulator, and check Liquid Glass surfaces on iOS 26 specifically — the
material is a no-op below that and the fallback recipe is what you'll see.
