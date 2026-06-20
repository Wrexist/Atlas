# Atlas — App Preview video storyboard

A shot-by-shot plan for the 15–30s **App Preview** that plays at the top of the
App Store listing. Unlike the screenshots, the App Preview **must be real
on-device screen capture** (Apple Guideline 2.3.10 — it has to show the actual
app in use). Use this as the recording script; the headline overlays mirror the
screenshot deck so the whole listing tells one story.

## Specs
| Field | Value |
|---|---|
| Duration | **25 s** (Apple allows 15–30 s) |
| Orientation | Portrait |
| Capture size | iPhone 6.9" — record at device resolution, export **886 × 1920** (or 1080 × 1920) |
| Format | `.mov` or `.mp4`, H.264/HEVC, ≤ 500 MB |
| Frame rate | 30 fps |
| Audio | Optional light bed; **most users watch muted** → every beat must read without sound |
| Poster frame | Set to the Recovery hero (scene 1) — it's the thumbnail |

## Capture setup
1. Build to a real iPhone (App Previews can't use the Simulator's status bar) and
   enable **screen recording** (Control Center) — or capture from a device via
   QuickTime → New Movie Recording → select the iPhone.
2. Seed realistic demo data first (Atlas's **Screenshot mode** toggle gives the
   polished demo seed): Recovery 78, a "Push Day" with Bench Press, a logged meal,
   7+ days of HealthKit, Level-14 Atlas Score, a 47-day habit streak.
3. Record one clean continuous pass per scene, slightly slower than natural — you'll
   trim. Keep the finger/touch visible on taps so the interaction reads.
4. Add the text overlays + transitions in iMovie / Final Cut / CapCut afterward.
   Keep overlays in the **top or bottom 18%**, large and bold (match the screenshot
   captions, SF Pro / Inter, white).

## The arc (problem → proof → breadth → brand)

| # | Time | Screen / action to record | Text overlay | Transition |
|---|------|---------------------------|--------------|------------|
| 1 | 0:00–0:03 | **Today** opens; the Recovery ring fills to **78**, tiles tick in (HRV/RHR/Sleep). | "Know if you're ready to train." | Hard cut |
| 2 | 0:03–0:07 | **Train** → tap a set; weight/reps pre-fill; the **PR banner** pops on the 100 kg set. | "Log a set in 2 taps." | Push left |
| 3 | 0:07–0:11 | **Meal scan** → camera → AI splits the plate into 3 items → tap **Add**. | "Snap a photo. Logged." | Push left |
| 4 | 0:11–0:15 | **Biology** → the Bio-Age gauge animates to **28.4**, "3.6 years younger". | "See your biological age." · *Atlas Pro* badge | Cross-dissolve |
| 5 | 0:15–0:19 | **Habits** heatmap scrolls; cut to **Atlas Score** medallion ticking +48 / Level 14. | "Build a streak you won't break." | Push left |
| 6 | 0:19–0:22 | **Apple Watch** glance: Recovery 78 → raise-wrist to the complications face. | "…and on your wrist." | Cross-dissolve |
| 7 | 0:22–0:25 | Brand close: Atlas logo + wordmark on the dark gradient; App Store line. | "Atlas — your whole health, in one app." | Fade to logo |

## Pacing & polish
- **Lead with motion in the first 1 s** — the ring filling is the hook; the App
  Store autoplays muted, so the first frame must move.
- One idea per scene, ~3–4 s each. Don't linger.
- Match each overlay's wording to the screenshot it mirrors so a browser who saw
  the screenshots gets reinforcement.
- Keep the same accent-color logic as the deck (mint recovery, amber score, violet
  Pro) so the video and stills feel like one campaign.
- End on the logo for ~2 s so the brand is the last thing on screen.

## Compliance notes
- Real capture only — no marketing-only frames inside the video (the logo end-card
  is fine as a short tail).
- If scene 4 (Biology / Bio-Age) shows a Pro feature, it's allowed in the preview;
  just keep the rest of the video covering free features so it's not all-paywall.
- No pricing claims in the video itself — keep those to the paywall screen / metadata.
