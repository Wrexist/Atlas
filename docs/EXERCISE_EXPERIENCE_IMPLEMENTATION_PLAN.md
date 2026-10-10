# Atlas exercise experience: complete implementation plan

Date: 2026-10-03. Status: proposed implementation, grounded in the current repository. This document does not mark any proposed feature or artwork as delivered.

Implementation update: the first incline-press slice is now present in the working tree. See [implementation status and validation](EXERCISE_FOCUS_IMPLEMENTATION.md) for delivered code, unexecuted device checks, and remaining scope. The inventory below describes the pre-implementation baseline.

Objective: reproduce the supplied reference's calm, illustration-led workout experience across the complete exercise library, while retaining Atlas logging, history, routines, accessibility, themes, and offline operation.

## 1. Product decision

Make the active workout a focused, one-exercise-at-a-time experience: large exercise illustration, workout exercise strip, editable set panel, integrated rest state, and session metrics. Keep a workout overview available for management and fast jumps. Use the same illustration system in exercise discovery, details, routines, and history.

Treat the reference as two states of one screen. The left is logging a set; the right is resting after a completed set. Do not build two independent screens or duplicate session state.

The full scope has four workstreams: SwiftUI presentation, workout state/persistence, exercise art production, and live workout metrics. A beautiful screen with a handful of illustrations is a prototype, not completion of this plan.

## 2. What the reference establishes

| Element | Intended implementation |
|---|---|
| Pale blue scene | Adaptive training background token; soft cool light appearance and a separately reviewed dark appearance. |
| Large gray anatomical figure | Consistent posed character with accurate equipment, soft studio lighting, dark shorts, neutral shoes, and a subtle ground shadow. |
| Orange and blue muscles | Orange primary and blue secondary muscle materials, with an explicit text legend. The exact muscle meaning is our proposed convention; the image alone does not prove it. |
| Circular close/pause buttons | Close minimizes and preserves the workout; pause freezes active duration and rest. Separate finish/discard actions remain available. |
| Five visible circular thumbnails | Scrollable workout exercise navigation. Five is an example viewport, not a limit. Each circle represents an exercise entry, including repeated entries of the same exercise. |
| Blue selection ring | Clearly selected exercise; retain its identity independently of the first unfinished exercise. |
| Green check badges | All relevant sets in that exercise are complete. Never show complete for an empty exercise. |
| Rounded white bottom panel | One adaptive surface containing exercise name, set progress/rest header, set rows, and metrics. |
| Pill-shaped weight/reps fields | Editable controls with visible units, suitable keyboard, validation, and at least 44-point hit targets. |
| Green set check | Completed; gray circle is pending; current set gets a blue marker plus an accessible label. |
| Rest title, countdown, line, Skip | Replace only the panel header during rest; set rows remain visible and editable. |
| Flame/heart/time footer | Session active energy, live heart rate, and active elapsed time when available. Use a clock for time rather than the reference's ambiguous lightning glyph. |

The reference has phone mockup chrome and unusually generous vertical space. Do not reproduce its status bar, Dynamic Island, fixed pixel coordinates, or outer device frame inside the app.

## 3. Verified starting point

The bundled catalog contains **873 exercises**: 581 strength, 123 stretching, 61 plyometrics, 38 powerlifting, 35 Olympic weightlifting, 21 strongman, and 14 cardio. All records have image paths; that does not establish successful remote downloads or suitability for the new style.

| Existing code | Reuse and gap |
|---|---|
| `Peptide/Features/Train/ActiveWorkoutView.swift` | Already owns the workout presentation, picker, finish flow, and minimize action. Currently renders a stack of exercise cards. |
| `Components/WorkoutExerciseCard.swift`, `SetEditorRow.swift` | Preserve add/remove sets, prior-set fill, unit conversion, warmups, rest overrides, plate calculator, and logged-data removal confirmation. Restyle through shared components. |
| `Peptide/Services/WorkoutSessionService.swift` | Keep as mutation authority. It persists set changes, stamps completion, restores active sessions, and updates Live Activities. No pause API exists. |
| `Peptide/Models/Training/WorkoutSession.swift` | Stable exercise-entry and set IDs already exist. Elapsed duration is currently wall-clock time. Superset group metadata exists, but needs explicit progression behavior. |
| `Peptide/Models/Training/SetEntry.swift` | Current fields support weight/reps, RPE, notes, warmups, and completion. No duration/distance schema exists. |
| `Components/RestTimerOverlay.swift` | Absolute rest end date, notifications, adjustments, and Live Activity updates already exist. Rest state is owned by the view and is not durable session state. |
| `Components/ExerciseImageView.swift` | Shared image component and remote loader. Images currently resolve to upstream GitHub photos, not a uniform Atlas illustration set. |
| `ExerciseDetailView.swift` | Existing image pager, metadata, instructions, and muscle map provide integration points. Its legend colors should be reconciled with the actual muscle-map colors. |
| `Components/AnatomyAssets.swift`, `MuscleMapView.swift`, `BodyAnatomy.swift` | Reuse muscle taxonomy, map geometry, masks, and fallback rendering. These do not constitute a rigged character demonstrating 873 movements. |
| `tools/anatomy/` | Existing static anatomy generation is useful groundwork, not an exercise pose/animation pipeline. |
| `Peptide/Services/HealthKitService.swift` | Current initial authorization reads HRV, resting HR, steps, and sleep. It does not provide the reference's live workout HR/energy. |
| `Shared/WorkoutActivityAttributes.swift`, `WorkoutLiveActivityService.swift` | Existing workout/rest projection; current exercise is inferred from unfinished sets, which must change for explicit exercise selection. |
| `PeptideWatch/` | Companion views exist; a live workout capture experience must be added for Watch-sourced metrics. |

Existing documentation about anatomy describes a different, static muscle-map deliverable. Its completion statements must not be taken as evidence that exercise demonstration assets exist.

## 4. Shared design specification

- Add training-specific semantic tokens in `ColorTheme.swift` for scene background, panel, input fill, selected outline, primary muscle, secondary muscle, and completed state. Use `AppFont` and `Spacing` throughout.
- Keep blue for selected state, orange/blue for anatomical meaning, and green for completion on this surface. Preserve user-selected Atlas themes on surrounding screens. Document these domain colors centrally.
- Target approximately 24–32-point panel corners, 48–56-point row controls, 48-point top controls, and 52–64-point exercise thumbnails, then translate to repository spacing tokens after device review.
- At default text size on a typical portrait phone, give the illustration roughly the upper 35–45% of usable height. Treat this as a composition target, never a fixed layout contract.
- Reserve real safe areas. Shrink the hero before squeezing the set controls. Scroll long set lists; keep finish and exercise management reachable. Keyboard entry may collapse the hero temporarily.
- At accessibility sizes and short landscape heights, switch to a content-first scrolling layout. On wide layouts, show art and logging panel side by side.
- Do not crop equipment or hands to make the image fill a rectangle. Use artwork bounds and aspect-fit rendering.
- Use quiet selection/rest transitions. Reduced Motion uses still artwork and immediate or simple fades. No animation is required to understand or operate the screen.
- Do not add another glass rendering system. Use the existing compatibility helpers only where the circular controls need them; the reference's main panel is opaque and calm.

## 5. Proposed SwiftUI composition

Keep `ActiveWorkoutView` as the session host; extract these focused components under `Features/Train/Components`:

| Proposed component | Responsibility |
|---|---|
| `WorkoutFocusView` | Compose selected exercise, hero, navigator, panel, and top controls. |
| `ExerciseHeroView` | Resolve and display poster or optional motion with loading/fallback states. |
| `WorkoutExerciseStrip` | Stable entry-ID navigation, progress badges, scroll-to-selection, accessible exercise names. |
| `WorkoutSetPanel` | Shared logging/rest/paused/complete presentation. |
| `WorkoutSetRow` | Input cells selected by tracking mode; completion and current-set state. |
| `WorkoutRestHeader` | Local countdown rendering, progress, skip, and adjustment controls. |
| `WorkoutMetricsBar` | Optional timestamped metrics and locally updating elapsed duration. |
| `WorkoutOverviewSheet` | Exercise list, rename, add/remove/reorder, rest settings, finish and discard access. |

Pass narrow immutable snapshots and actions into child views. Do not create a second mutable workout model in the focus view. Keep clock ticks inside timer/metrics subviews so they do not redraw the hero or decode images every second.

Preserve direct weight/reps editing and one-tap completion when existing values are valid. Keep history hints accessible as secondary row content or a set-details sheet. Expose RPE/notes/warmup explicitly in that sheet; do not require users to discover a long press.

## 6. Durable workout state and behavior

Extend the session with compatible optional state, owned by `WorkoutSessionService`:

- Selected exercise-entry ID and selected set ID; these are not catalog exercise IDs.
- `pausedAt` and accumulated paused duration; calculate active duration from dates.
- Rest context: source entry/set IDs, target entry/set IDs, end date, planned duration, notification identifier, and frozen remaining duration while paused.
- Session revision or equivalent conflict ordering for device commands; commands include session and operation IDs for deduplication.

Persist selection at meaningful navigation changes, not on timer ticks. Persist completion and its resulting rest/progression state together. Put pure progression decisions in a small `WorkoutProgressionEngine`; keep persistence and notification side effects in the service.

| Event | Required behavior |
|---|---|
| Start/resume | Restore valid selection; otherwise choose the first pending set in workout order. No exercise means show the existing add-exercise path. |
| Tap another exercise | Change displayed selection, preserve existing rest ownership, and never mark work complete. |
| Complete working set | Commit valid inputs and completion once, then derive the next target and start configured rest if another target exists. |
| Complete warmup | Preserve current behavior: no automatic working-set rest. Move focus sensibly without counting warmup as working volume. |
| Complete last set in an exercise | Show exercise complete; next target is the next pending exercise. During transition rest, label that target explicitly. |
| Complete last set in workout | Show review/finish action; do not auto-finish or run an unnecessary final rest. |
| Rest expires or Skip | Clear rest and its notification; reveal the pending target. Neither event logs a set. |
| Adjust rest | Update the authoritative deadline, progress denominator policy, notification, and Live Activity together. Define progress as remaining/current adjusted duration. |
| Pause | Freeze active duration and remaining rest; cancel pending rest alert; pause demo playback and live capture where supported. |
| Resume | Add paused interval once; rebuild rest deadline from frozen remainder; resume capture and one notification. |
| Undo completion | Clear completion timestamp and recompute progress. Cancel rest only if it belongs to that set. |
| Complete a set during rest | End the prior rest and create the newly completed set's rest context once. |
| Delete/reorder entry or set | Repair selection by IDs; cancel invalid rest targets; retain confirmation before deleting logged data. |
| Minimize/background | Preserve session and deadlines; stop visual animation. On return, reconcile from current time. |
| Process termination/relaunch | Restore from persisted state. Expired rest becomes ready without duplicate alerts; paused rest remains paused. |
| Finish/discard | Clear rest notifications, Live Activity, active selection and capture; preserve existing finish/PR/history behavior. |
| Save failure | Surface retryable failure and avoid presenting an unsaved completion as durable. |

Supersets: alternate pending sets across group members in order and rest after a round. Handle uneven set counts and warmups explicitly. Do not silently treat the existing group field as proof that this behavior already works.

Cross-device policy: one originating device owns workout capture and authoritative command ordering. Other devices send commands and display snapshots. Detect competing active sessions without silently merging logged sets or deleting a workout. Do not pretend CloudKit propagation is a live command channel.

## 7. Every exercise needs the correct input mode

Use a reviewed manifest keyed by stable exercise ID; raw category/equipment is only a suggestion, not sufficient to choose tracking behavior automatically.

| Tracking mode | Main fields | Examples / semantics |
|---|---|---|
| Loaded reps | Load + repetitions | Presses, rows, squats; distinguish per-dumbbell vs total load in help text and stored semantics. |
| Bodyweight reps | Repetitions; optional added load | Pushups/pullups; zero external load is valid. |
| Assisted reps | Assistance + repetitions | Assisted machine work; assistance is not ordinary lifted volume. |
| Duration | Seconds/minutes | Holds and stretches; optional side labels. |
| Distance and duration | Distance + elapsed time | Cardio; pace is derived where meaningful. |
| Loaded carry | Load + distance or duration | Strongman and carries; separate from weight-times-reps volume. |

Extend set storage with optional tracking kind, duration, distance, assistance, side, and load semantics. Preserve kilograms and meters as canonical units. Store tracking semantics on logged sets so a later catalog correction does not reinterpret history.

Old sessions decode as the current weight/reps behavior. Do not retroactively infer a new mode for historical records. Update history, finish summaries, PR detection, routine templates, prior-set fill, exports, and consistency calculations alongside the new schema. Time/distance/assistance work must not produce fictional lifting volume or Epley PRs.

Custom exercises get a mode selector, muscle selection, instructions, and a matching muscle-map fallback. An arbitrary custom name cannot guarantee an accurate bespoke demonstration; state this honestly. An optional user image belongs in a separate custom-media treatment.

## 8. Consistent artwork for all 873 exercises

Recommendation: produce pre-rendered illustrations from one versioned, rigged anatomical character and reusable equipment kit. Use the same source to produce optional demonstration loops. Do not use unrelated generated images as the production library: identity, equipment geometry, framing, and anatomical masks would drift.

Blender supports reusable asset libraries; use a pinned, tested version for production rather than following a moving latest version. [Blender asset-library documentation](https://docs.blender.org/manual/en/5.0/editors/asset_browser.html).

### Art bible and source scene

- One approved character: neutral gray skin/anatomy, consistent proportions, modest black shorts, white/gray shoes, neutral face.
- Separated muscle materials for primary/secondary highlights; exact mappings reviewed per exercise, not inferred from which surfaces happen to be visible.
- One equipment library: adjustable bench, dumbbells, barbells/plates, EZ bar, kettlebells, cables, racks, major machines, bands, balls, roller, cardio and strongman equipment.
- A locked lighting/material setup and limited documented camera presets: standing, bench, floor, overhead, machine, and close movement detail. Consistent perceived subject scale across presets.
- Standard ground origin and transparent still outputs with subtle shadows. Review edges on light and dark backgrounds; provide alternate lighting renders if one asset cannot serve both.
- No text, numeric weights, or UI baked into art. No mirroring unilateral or handed equipment without review.

### Production pipeline

1. Export a CSV inventory from `exercises.json`: ID, name, category, muscles, equipment, instructions, pose family, tracking mode, art status, reviewer, and source provenance.
2. Establish rig/equipment source ownership and redistribution terms before committing production assets. Record source URLs and attribution alongside outputs; no specific commercial model is assumed purchased.
3. Produce a benchmark pack: incline dumbbell press from the reference, barbell squat, deadlift, cable row, overhead press, pullup, pushup, plank, lunge, calf raise, stretch, and cardio movement.
4. Review this pack in the actual focus screen, exercise rows, and dark mode before producing the full catalog. Lock the art bible after correcting proportions, camera, shadows, highlights, and crop.
5. Group remaining exercises into pose/equipment families, then create exercise-specific variations. Similar names do not justify sharing inaccurate poses.
6. Export each exact movement's hero poster, small thumbnail, and start/end images; render a reviewed loop for movements that benefit from motion. Motion is optional; accurate static coverage is mandatory.
7. Generate contact sheets by equipment and movement family. Review anatomy, joint positions, equipment contact, clipping, movement range, muscle assignment, framing, and consistency. Hold uncertain instructions for qualified review.
8. Publish immutable, versioned asset files with checksums and a manifest. Never overwrite a released URL with unrelated content.
9. Run catalog-wide coverage validation; every bundled exercise must resolve to its own approved art or a documented, genuinely equivalent shared asset before calling the rollout complete.

Suggested source layout: `tools/exercise-art/` for inventory, validation and render scripts; external versioned storage for large source scenes; `Peptide/Resources/exercise-visuals.json` for the bundled manifest. Keep source scenes out of the app binary.

Manifest fields: exercise ID, schema/style/asset versions, tracking mode, load semantics, hero/thumbnail/start/end/motion references, dimensions, byte counts, checksums, crop/safe bounds, muscle mapping, pose family, descriptive accessibility text, review status, and provenance reference. Put authoring-only provenance in a build manifest when it need not ship.

### Delivery and offline behavior

- Adapt `ExerciseImageView` through an exercise-ID-aware visual resolver; do not keep individual call sites constructing photo URLs.
- Resolve approved local asset, then validated disk cache, then versioned hosted asset; use the same anatomy-style fallback if unavailable. Existing photos may remain explicitly in a legacy/reference gallery during migration, not silently appear among new hero renders.
- Bundle small navigation/fallback assets and a measured starter pack. Prefetch and pin the current routine's hero assets before workout use; offer download-for-offline and storage management.
- Cache by asset version/hash and resolution; use a bounded disk cache with current-workout protection and an eviction policy. Deduplicate requests, cancel obsolete loads, and downsample for the actual display size.
- Reset image state on identity changes. The current loader's `guard image == nil` needs review when the same view instance changes URLs.
- Enforce response byte limits while receiving data, plus dimensions/decoded-pixel limits. The existing loader checks byte count after `data(from:)` has already downloaded the payload.
- Initial targets to benchmark: 256–384px thumbnails, 1024px hero posters, compressed hero budget around 150–400KB, optional motion around 1–3MB. These are engineering targets, not measured results.
- At 300KB each, 873 posters alone are about 262MB before thumbnails or motion. Do not bundle the entire full-resolution animated library by default.
- Prefer stills for the first complete release. Motion must pass real-device codec, transparency, memory, battery, Reduce Motion, and dark-background tests before rollout. A video loop never counts user repetitions automatically.

## 9. Metrics, Apple Watch, and Live Activities

The reference's calorie and HR numbers are example values, not implementable data by themselves. Use a `WorkoutMetricsSnapshot` with source, session ID, sample time, active energy and heart rate. Display session energy rather than daily calories, and use the same pause-aware elapsed duration everywhere.

Build the Watch workout capture path and a phone metrics bridge. Apple's live workout builder collects data from an active workout session; use it through platform-appropriate, availability-checked APIs. [Apple HKLiveWorkoutBuilder documentation](https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder).

- Request workout-related HealthKit types when the user enables recording, preserving existing nutrition/recovery permission behavior.
- Never interpret read authorization completion as proof that readings will be available. Support no Watch, declined access, disconnected capture, missing samples, and stale HR.
- Proposed stale HR threshold: 30 seconds, to be tuned in device testing; show unavailable or last-updated state rather than presenting stale data as live.
- Without sensor data, show elapsed time, completed sets, and volume where meaningful; optionally show unavailable HR/energy labels. Do not invent live HR or silently estimate calories.
- Coordinate start/pause/resume/finish with the originating capture device; prevent duplicate HealthKit workout saves on reconnect/retry.
- Extend shared Live Activity state to include explicit selected exercise and pause-aware elapsed/rest data, with compatible decoding. Preserve one workout activity rather than creating a second rest activity.
- Update `PeptideWidgets/WorkoutLiveActivity.swift`, notification reconciliation, deep links, and Watch displays together. No image loading or per-second network messages in widgets.

## 10. Persistence and compatibility

Update `WorkoutSession`, `SetEntry`, training storage mappings in `Peptide/Data/SwiftDataModels+Training.swift`, and `SwiftDataRepository` as one change. Inspect the actual stored scalar fields versus JSON payloads before deciding which additions require a SwiftData schema migration.

Use optional CloudKit-compatible fields/defaults and explicit decoding fallbacks where needed. Test old stored sessions, routine payloads, custom exercises, and Live Activity state fixtures. A new nonoptional Codable field with a property default is not sufficient evidence that old payloads will decode.

Decide downgrade behavior explicitly: newer tracking modes must not become ordinary rep sets when opened by an older client. Preserve unsupported data and prevent incompatible editing where possible. Keep exercise IDs, bundle IDs, product IDs, and deep-link identifiers stable.

## 11. Surface-by-surface integration

| Surface | Required change |
|---|---|
| Active workout | New focused experience plus overview; same canonical service and finish flow. |
| Library and picker | Shared consistent thumbnails, intact search/filter/favorites/recent behavior. |
| Exercise details | Large matching hero, optional demo controls, instructions, synchronized muscle legend, tracking/load explanation. |
| Routine builder/cards | Matching thumbnails and mode-appropriate planned fields; preserve exercise order and rest settings. |
| Workout history/details | Matching art, correct actual metrics, no reliance on current catalog semantics to reinterpret old sets. |
| Finish screen | Correct summaries/PRs for every mode; no double-counted warmups or paused duration. |
| Custom exercise editor | Tracking-mode and muscle options, deliberate fallback art. |
| Train muscle map | Reuse anatomical vocabulary; preserve its intensity heatmap semantics rather than changing it to exercise primary/secondary colors. |
| Watch, Live Activity, notifications | Same selected exercise, active duration, rest deadline, pause and completion truth. |

## 12. Implementation sequence and acceptance gates

| Phase | Work | Exit condition |
|---|---|---|
| 0. Inventory and contracts | Generate all 873 coverage rows; lock behaviors, asset schema, tracking modes, and migration fixtures. | No unclassified catalog IDs; a reviewed list of uncertain classifications remains explicitly blocked from final release. |
| 1. Reference exercise end to end | Shared UI components and incline press hero; real session bindings, rest panel, overview, existing editing actions. | Reference composition works with real data at small/large phone sizes in light/dark and Dynamic Type. |
| 2. State and durability | Move rest into service/session; pause/resume; progression/supersets; notification and Live Activity reconciliation. | Deterministic tests cover interruption, undo, reorder, completion, and relaunch without data loss. |
| 3. Tracking completeness | New modes and migrations; update routines, history, PRs, units and custom exercises. | Every exercise has correct controls; old sessions remain readable and unchanged in meaning. |
| 4. Art pipeline and benchmark | Rig, equipment kit, render automation, 12-movement benchmark and asset loader/cache. | Reviewed art is visually consistent and offline fallback works. |
| 5. Full catalog production | Produce/review remaining movement families; contact sheets, metadata, checksums and coverage checks. | 873/873 bundled exercise IDs have approved correct visual coverage. No placeholder counted as finished art. |
| 6. Live metrics | Watch capture, phone bridge, availability-aware HealthKit recording, stale/no-data states. | Real-device tests demonstrate coherent capture and no duplicate records. |
| 7. Integration and release | Every surface, accessibility, performance, migration, offline and hardware regression testing. | All acceptance criteria below pass; measured asset/app size stays within agreed budgets. |

Phases 2–3 and art production can progress independently after contracts are stable. Metrics can be integrated once session lifecycle behavior is settled. Ship behind an internal presentation flag first; keep schema changes backward-compatible regardless of UI rollback.

Estimate the full schedule after the benchmark pack: measure scene setup, pose authoring, render, review, and correction time per family. Total artwork effort is shared rig/equipment setup plus family authoring plus per-exercise review/rework. A precise full-library delivery date before that measurement would be speculative. UI completion alone is not a reliable proxy for art completion.

## 13. Verification plan

Extend existing `WorkoutSessionTests`, `WorkoutSessionServiceTests`, `WorkoutActivityStatusTests`, `WorkoutLogMigrationServiceTests`, `PreviousSetEngineTests`, and `ExerciseLibraryTests` where behavior belongs. Add targeted progression, rest/pause, tracking-mode, asset-manifest, and persistence fixtures rather than tests that merely mirror view implementation.

- Clock-driven tests: complete/undo/double-tap, zero-rest, rest adjustment, background expiration, pause through original deadline, resume, process restoration, and finish/discard cleanup.
- Identity tests: duplicate catalog exercise entries, out-of-order selection, deleting selected set, changing exercises during rest, uneven supersets, and no-exercise/no-set sessions.
- Data tests: kg/lb round trips, per-hand semantics, decimal commas, invalid pasted input, bodyweight zero load, assistance, duration/distance validation, and old JSON decode.
- Metrics tests: unavailable permissions/data, stale HR, Watch disconnect/reconnect, duplicate commands, paused capture, and finish while capture is unavailable.
- Media tests: 404, timeout, oversized response, huge decoded image, checksum mismatch, cache eviction, offline routine, rapid hero switching, Reduce Motion, and inactive playback suspension.
- UI tests: start from routine, change weight, complete set, rest, skip, navigate exercises, pause/minimize/relaunch/resume, finish, and verify history. Include custom, timed, and distance exercises.
- Visual review: reference incline press logging/rest pair, small and large phones, wide layout, dark mode, all supported theme settings, accessibility XXXL, keyboard, long names, and 10+ sets.
- Accessibility: named icon buttons, independently operable fields, VoiceOver state labels, no color-only completion, no continuous countdown announcements, contrast review and minimum hit targets.
- Performance: measure cold/warm load, scrolling, repeated exercise switches, memory under image churn, battery during a workout and binary/download/cache sizes on the oldest supported test device. Initial interaction target: smooth 60Hz rendering with no image decode on the main thread; confirm with profiling.
- Run SwiftLint, `python scripts/design-lint.py --all`, and the affected iOS/Watch/widget build and test targets on macOS. This Windows workspace cannot validate a SwiftUI simulator build locally.

## 14. Definition of complete

- All 873 bundled exercises have reviewed tracking metadata and consistent, exercise-correct artwork; shared assets are explicitly justified.
- All exercise surfaces use the shared visual resolver and style, including custom/missing/offline cases.
- Logging, rest, pause, progression, finish, history, units, and migrations work with actual persisted sessions.
- Watch/Live Activity/notifications agree with session state; metrics are real or clearly unavailable.
- The reference's main composition is recognizable without compromising small screens, accessibility, dark mode or existing Atlas workflows.
- No default dependence on upstream GitHub images for the new experience; a versioned delivery/cache strategy is tested.
- Coverage checks, behavior tests, design lint, macOS builds, simulator review and real-device workout tests pass.

Recommended first implementation slice: the reference's incline dumbbell press working through logging, rest, pause and resume on the real workout service, using the reusable components and a benchmark-quality asset. Expand only after that slice establishes the visual and state contracts for the full catalog.
