# Workout sharing: Stories, posts and short videos

## Entry point

Finish and save a workout → Summary → Share workout. Saved history summaries use
the same destination. The default Exercise highlight style follows the supplied
light reference: exercise illustration, a real completed-set caption, a large
recorded-volume total, duration, exercise/set counts and an optional name/date.
Choose a featured logged exercise in the picker. Dark summary remains available.

No sample heart rate, calorie burn, streak, PR delta or mockup total was copied.
The logged-set caption uses the shared formatter including each/combined load,
timed and distance conventions. Unsupported volume remains excluded and labeled.
If volume is hidden/unavailable, the highlight shows working sets instead.

## Formats and actions

- Story: 1080×1920 opaque PNG.
- Post: 1080×1350 opaque PNG.
- Reel: 1080×1920 H.264 MP4, 30 fps, exactly six seconds, without audio. A brief
  reveal and 1.5% push use final recorded totals throughout. Reduce Motion exports
  a still composition for the full video. Preview video plays only when requested.
- Share: the existing native activity sheet, with a real PNG/MP4 file URL.
- Save image/video to Photos: explicit add-only authorization, actual Photos
  transaction, success feedback after completion, and Settings/Share alternatives
  on denial. No library reading, automatic publishing or external upload.

Actions stay in a safe-area footer while the preview/options scroll. Export
progress reflects encoded frames. Options are frozen during export; Cancel and
Close cancel unfinished encoding. A Photos transaction already in progress is
allowed to finish. Sharing cancellation doesn't relabel the workout or report a
false success. No operation mutates saved workout records.

Meta's direct Reels sample requires a registered developer App ID; this project
doesn't configure one. No fake Instagram destination button or new login was
added. Choose Instagram in the system sheet if offered; otherwise save to Photos
and import the file inside Instagram. Actual app destinations depend on installed
apps and their share extensions and still need device validation.

Reference: https://github.com/fbsamples/share_to_reels_ios
Apple APIs: https://developer.apple.com/documentation/uikit/uiactivityviewcontroller
and https://developer.apple.com/documentation/avfoundation/avassetwriter

## Privacy and rendering

Name, date and recorded volume are controlled independently. Date defaults off.
No account identifiers, private notes, exact workout times or health integration
details enter the export views. Filenames contain only an Atlas prefix and UUID.
Temporary files remain alive through the share sheet/preview and are removed
when their controller is released; partial canceled videos are removed immediately.
The OS owns copies explicitly saved to Photos or passed to another app.

Preview and export use the same fixed-size SwiftUI canvases at scale 3. App
controls retain Dynamic Type; exported typography uses the standard large size.
The dark composition can fall back to a named muscle list when space is tight.
Artwork uses existing bundled illustrations and mapped fallbacks. No new artwork
license or package dependency was introduced. AVFoundation encodes one frame at
a time on an actor outside the main UI actor. Render caching includes the saved
session, units, options and Reduce Motion, so edits cannot reuse old totals.

## Files

- `WorkoutShareView.swift`: integrated format/style selection, preview, privacy,
  persistent actions, Photos denial and native share sheet.
- `WorkoutShareFormat.swift`, `WorkoutShareController.swift`: immutable render
  identity, export state, cache, cancellation and owned file lifecycle.
- `WorkoutSocialCanvas.swift`, `WorkoutHighlightCanvas.swift`: dark and light
  compositions; the latter implements the latest supplied reference.
- `WorkoutMediaExporter.swift`: AVFoundation encoder and Photos add-only writes.
- `project.yml`, `Resources/Info.plist`: accurate image-and-video Photos purpose.
- `check-copy-claims.py`, `test_copy_claims.py`: distinguish add-only Photos usage
  from read/write APIs. Legacy authorization and asset reading remain checked.
- `WorkoutSocialShareTests.swift`, `WorkoutRecapTests.swift`, `ScreenshotTests.swift`:
  dimensions, video duration/track/decode, cancellation, anonymous filenames, and
  full sharing route captures using isolated workout fixtures.

## Verification and reproduction

Local checks: design lint 0 errors/warnings; all 288 contrast token pairs pass;
copy/entitlement checks pass; three Python Photos-purpose regression tests pass;
Info.plist parses. Swift syntax checks are not native compilation.

On a Mac: generate the project using `xcodegen generate`, run
`PeptideTests/WorkoutSocialShareTests` in the Peptide scheme, then
`ScreenshotTests/test_captureWorkoutSocialSharing` in PeptideUICapture.
The unit tests attach all six exported style/format combinations and a decoded
video frame. UI tests attach `social-highlight-*`, `social-summary-*`,
`social-reel-video-preview`, and `social-native-share-sheet`.

Native build, XCTest execution, screenshots, export orientation/legibility and
real Instagram import are not verified on this Windows host. The existing macOS
Actions runner has been blocked by GitHub's account billing lock. Before release,
also exercise Photos denial/retry, cancellation during encoding, app backgrounding,
large text, long workout names, missing anatomy assets, and on-device Instagram
Story/Post/Reel import. Do not treat authored tests as executed tests.
