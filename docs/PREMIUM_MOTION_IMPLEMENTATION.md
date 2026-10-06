# Premium motion implementation

Implemented in the working tree on 2026-10-04, following [the reference assessment](PREMIUM_MOTION_REFERENCES.md). Not yet build- or simulator-verified.

## Shared components

- `Peptide/DesignSystem/Components/Celebration/MilestoneArtwork.swift`: original native relief artwork with a beveled medallion, folded ribbons, embossed symbols, and an Atlas-logo emblem. No generated bitmap, external video, decoder, package, or network dependency was added.
- `Peptide/DesignSystem/Animations/MilestoneMotion.swift`: a finite 800 ms keyframe performance. Medals settle, flames compress/stretch at their base, and trophies/emblems receive a light sweep without moving their body. Each performance ends at the static pose.
- Motion uses semantic triggers, remembers the last trigger for the mounted view, waits for the active onboarding page, and displays a still under Reduce Motion, inactive scene state, or offscreen visibility. Routine badges skip arrival motion and respond only to qualifying changes. Static collections disable motion.
- Artwork is decorative for VoiceOver, does not intercept touches, and uses Atlas color tokens. Labels, counts, and controls remain native and separate from the artwork.

The APIs follow Apple's [triggered keyframe animator](https://developer.apple.com/documentation/swiftui/view/keyframeanimator(initialvalue:trigger:content:keyframes:)) and [scroll visibility callback](https://developer.apple.com/documentation/swiftui/view/onscrollvisibilitychange(threshold:_:)) documentation. These APIs do not substitute for device testing.

## Integrated surfaces

| Surface | Result |
|---|---|
| Workout finish | Medal for a normal finish, trophy for existing detected PRs. Summary statistics and PR details precede the anatomy card. Done remains pinned. Landing haptic is guarded against repeat appearances of the mounted screen. |
| Level-up overlay | Tier-specific medallion with the existing level and tier text; smaller card entrance and one VoiceOver announcement per mounted presentation. |
| Achievement toast | Matching earned medal, motion-aware entrance/dismissal, canceled tasks cannot dismiss a subsequent achievement. |
| Achievement collections | The same medals in profile and achievement previews, rendered as stills. Empty-state copy includes training, meals, and habits. |
| Meal and protocol streak indicators | Dimensional flame with a brief response only at existing milestone thresholds. No idle pulse. |
| Habit cards | Relief icon responds when the habit becomes completed; numeric totals use a numeric transition. No additional haptic is introduced by the artwork. |
| Onboarding | Welcome logo and informational heroes use one brief arrival. Page selection gates the effect. Interactive set confirmation and the ready page use the medal. Perpetual ready rings are removed. |
| Premium promo cards | Static sculpted Atlas emblem replaces the placeholder letter mark. |
| Paywall | Compact emblem in the existing header; prices and pinned purchase controls retain their hierarchy. |
| Trial offer | Same emblem, compact hero, billing choices immediately after the headline. Offer content no longer waits invisibly for product loading. Idle sparkles and purchase-button pulsing are removed. StoreKit eligibility and pricing logic are retained. |

The existing celebration queues and PR calculations remain the source of events. No new achievements, additional reward modals, or persistence schema were introduced. Cancellation handling was tightened in the existing celebration host, and its motion now respects Reduce Motion.

## Validation performed

- `python scripts/design-lint.py --all`: zero errors and warnings.
- `python scripts/check-store-metadata.py`: passes, including purchase-surface legal links.
- Tree-sitter Swift parsing: all 17 changed/new Swift files parse without errors. This is syntax validation, not Swift type checking.
- `git diff --check`: clean.
- The XcodeGen app target includes the `Peptide` directory, so the two new source files are discovered without a project-file edit.

## Device checks still required

This workspace runs Windows and has no Xcode or iOS simulator. Before release:

1. Generate the Xcode project and build the app for iOS 18 and the current iOS simulator.
2. Use the light and dark artwork previews, then enable Reduce Motion in simulator or device Settings. Replay should return every object to its original pose; under Reduce Motion it should remain still.
3. Finish an ordinary workout and one with a PR. Confirm accurate statistics, visible Done, and no duplicate records or haptics from reappearing views.
4. Trigger a habit completion and an achievement/level-up near each other. Confirm queues drain correctly and dismissing an old toast cannot dismiss the next one.
5. Navigate onboarding forward/back, including its set demo and ready page. Adjacent preloaded pages should not animate early. Background/foreground the app and scroll artwork offscreen during a performance.
6. Review small-screen and largest Dynamic Type layouts, VoiceOver labels, and all brand themes. Verify price loading, plan selection, restore, trial eligibility, purchase cancellation, and dismissal on both purchase surfaces.
7. Measure frame pacing and rendering cost on a device. No performance improvement or pixel-level visual quality is claimed from source inspection alone.

## Follow-up: action and progress feedback

The second pass extends motion to everyday actions through 11 additional source files:

- `CompletionPulse.swift` adds a finite 360 ms glyph pulse. It has no arrival animation, extra haptic, task timer, or layout displacement, and renders at normal scale under Reduce Motion or an inactive scene.
- Set-completion controls and Today habit chips pulse only when their completion value changes to true. Undoing completion suppresses the effect; mounting an already-complete item does not trigger it. Existing input fields, hit targets, and persistence handlers are retained.
- Barcode and food-library success screens use the same 64-point medal. Undo and Done remain immediately available.
- Daily check-in uses a brief introductory artwork animation and a medal when an empty check-in becomes saved. Its previous indefinitely repeating prompt pulse is removed.
- Water quick-add pulses the selected droplet after the observed water total increases. Nutrition legend values transition numerically; water/protein ring movement now honors Reduce Motion.
- Meal-review calorie and gram totals animate when portions change. The macro arc animation watches the macro amounts, including changes that leave calories unchanged. An all-zero meal no longer draws a full fat arc.
- `LoggedCaloriePanel` starts from the pre-log total without a zero flash, reveals the current total once per mounted presentation, and continues to reflect later caller updates. Reduce Motion displays the final value immediately. VoiceOver reads the actual final progress, not the animation's initial value.
- Shared `MetricRing` uses the finite completion pulse in place of a delayed reset task. Ring sweeps and `GlassProgressBar` now honor Reduce Motion.

Validation: the 11 follow-up Swift files parse without syntax errors; the repository design checker reports zero errors/warnings and the whitespace check passes. Xcode type checking and simulator/device validation remain outstanding on Windows.

Additional device cases: complete/undo/recomplete a set and a habit rapidly; open an already-complete day; add and undo different water amounts; change meal macros without changing total calories; remove every scanned item; save/edit a check-in; and reopen a meal confirmation with Reduce Motion enabled. Check that glyph motion never moves its tap target or delays the next action.
