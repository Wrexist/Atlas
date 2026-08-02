---
name: dna-transplant
description: Design a screen by transplanting the DNA of an interface the user already knows — Wallet's card deck, Stocks' sparkline row, a Tamagotchi's life stage — instead of inventing a layout from scratch. Use whenever building, redesigning, or reviewing a screen, a dashboard, a list, a detail view, or any "make this look better" request. Triggers on "build screen X", "design a page for Y", "this looks generic", "make it premium".
---

# DNA transplant

Most screens that read as "generated" fail before any pixel is chosen: nobody
decided *what kind of thing* the screen is. A layout invented from the data
outward produces a form with a header. A layout transplanted from an
interface the user has already learned produces something legible in one
glance.

So: **pick the donor first, map the fields, then style.**

## 1. Name the donor

Ask what shape the data actually is, then take the idiom that shape already
has a canonical answer for. `references/mappings.md` holds the proven table.
The short version:

| Data shape | Donor idiom |
|---|---|
| A set of accounts/balances | Wallet card deck — stacked, peek-through, one expands |
| A value over time vs. a target | Stocks row — name, value, sparkline, signed delta |
| One number that *is* the screen | Fitness ring / gauge — big glyph, thin arc, delta beneath |
| 3–5 peer metrics, glanceable | Activity ring trio — equal weight, no hierarchy |
| Mixed events in time order | Wallet transaction list — one row per event, type as glyph |
| Things with state, one tap to advance | Reminders checklist — the row *is* the target |
| A streak or habit | Duolingo flame — count is hero, calendar is secondary |
| A living thing that changes with care | Tamagotchi stage — state as a character, not a number |
| Something aspirational behind a paywall | Apple One card — dark, one promise, one CTA |
| A library to browse and pick from | Music/App Store shelf — horizontal rows by category |

## 2. Map the fields explicitly

Write the mapping down before writing any view code:

```
donor:      Stocks row
symbol   -> biomarker.displayName
price    -> latest value + unit
sparkline-> 14-day series
delta    -> change vs. 30-day median, coloured
```

**If a field in your data has no home in the donor, the donor is wrong.**
That's the signal to pick a different one — not to bolt an extra slot onto
the side, which is exactly how screens become forms again.

## 3. Transplant the structure, not the skin

Take the donor's *information hierarchy*: what's biggest, what's adjacent to
what, what's one tap away, what's deliberately omitted. Do not take its
colours, its corner radii, or its brand. Those come from the host app's
design system.

The tell that you skinned instead of transplanted: the screen looks like the
donor app. The tell that you did it right: the screen looks like *your* app
and a first-time user already knows how to read it.

## 4. Then verify

Run the host project's design checker if it has one. Otherwise check by
squint: blur the screen — if every block has the same weight, the transplant
didn't take, because every donor idiom above has one obvious focal point.
