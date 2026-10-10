# Atlas: premium motion and illustration direction

Reviewed 2026-10-03. This is a design assessment and implementation brief, not a shipped UI change. Evidence: sampled frames across both reference videos, the linked 3dicon skill, and the Atlas source files below. Atlas itself was not rendered in a simulator during this review.

**Implementation update, 2026-10-04:** The native artwork and motion integration is now in the working tree. See [implementation notes and remaining device checks](PREMIUM_MOTION_IMPLEMENTATION.md). The implementation uses SwiftUI relief artwork and keyframes; the generated-video pipeline below remains a future option, not an installed dependency.

## What to learn from the references

### Designer Elo: onboarding as a visual demonstration

[Original post and video](https://x.com/Designer_Elo/status/2105962245075370025/video/1)

The clip shows three visual stories: a task over a level ring, a streak badge counting toward 100, and a three-person podium. A large illustration owns the upper area; short copy and a primary action sit below it. Frames show staged reveals and changing progress, with a stable dark canvas and repeated layout.

**Atlas translation:** demonstrate a useful action and its result. Keep the artwork, copy, and button in predictable positions across steps. Use native UI for live numbers and controls. A fictional onboarding preview must be clearly distinguishable from the user's real progress. The podium does not map to an existing Atlas feature and is not part of this proposal.

### Samuel Yost: one expressive object within a quiet summary

[Original post and video](https://x.com/samuel_yostt/status/2104275038757368203)

The clip shows a completion sheet with an animated dimensional flame, a large completion count, three secondary statistics, and one button. The object changes shape while the surrounding layout stays stable.

**Atlas translation:** make the accomplishment the focal point, then show supporting numbers and a clear exit. Match celebration intensity to the event's significance.

### The linked 3dicon skill

[Repository](https://github.com/samyost1/3dicon) · [Skill source](https://github.com/samyost1/3dicon/blob/main/skills/3dicon/SKILL.md)

The pipeline creates a still, uses it as both video endpoints, removes the background, and exports animated WebP. Its useful discipline is to settle the art before motion, choose movement that belongs to the object, inspect the loop and alpha edges, and ship a static fallback. The skill separates natural motion, a performed action, a moving part, and a surface effect. Its app integration examples do not establish SwiftUI playback support.

Study this as an asset-production workflow. Native playback and lifecycle handling need a separate Atlas prototype. No external skill was installed or executed for this assessment.

## Where Atlas should use it

| Priority | Existing surface | Proposed change | Trigger and restraint |
|---|---|---|---|
| 1 | `Peptide/Features/Train/WorkoutFinishView.swift` | Replace the generic completion seal with a sculpted Atlas medal; use a trophy variant for a PR. Make the result and existing duration/sets/volume summary readable before the large anatomy section. | One entrance after a successful finish. Keep Done immediately available. Use existing `detectedPRs`; never run PR detection again for animation. |
| 1 | `Peptide/DesignSystem/Components/Celebration/CelebrationOverlayView.swift` | A dimensional tier badge, existing level number, and concise achievement copy. | Reuse `CelebrationCenter`'s event identity and queue. Animate once per event, not on every view appearance. |
| 2 | `Peptide/Features/Onboarding/OnboardingView.swift` | Give welcome, the existing interactive set demo, and ready three coherent visual beats: intent, action, result. The demo's checked set should visibly cause its confirmation. | Improve existing steps; avoid adding setup screens. Start effects when the page is selected, since TabView can mount adjacent pages. |
| 2 | `Peptide/Features/Onboarding/Components/ReadyHero.swift` | A settled Atlas medal/checkmark with one completion flourish. | Replace the perpetual expanding rings with a brief arrival and rest. Opening Atlas never waits for the flourish. |
| 3 | `Peptide/Features/Meals/Components/MealStreakBadge.swift` and `Peptide/Features/Home/Components/AchievementToastView.swift` | A flame/leaf asset family for meaningful meal and habit milestones; use larger art only in the milestone presentation. | Keep compact everyday badges legible and quiet. Reuse actual unlocks from `AchievementService`, which already knows meal/habit 7-, 30-, and 90-day achievements. |
| 4 | `Peptide/DesignSystem/Components/PremiumPromoCard.swift` and `Peptide/Features/Biology/BiologyView.swift` | A restrained Atlas emblem or sculpted dial within the existing trailing artwork slot. | Prefer a still here. A dashboard should not contain several competing loops. Keep measurement values separate from decorative art. |
| 4 | `Peptide/Features/Profile/Components/PaywallView.swift` and `Peptide/Features/Onboarding/Components/TrialOfferView.swift` | Reuse the same emblem at modest size to connect the offer with the rest of Atlas. | Preserve the pricing-first hierarchy, pinned purchase action, restore, close, and subscription disclosures. A large decorative hero would undo the paywall's existing layout improvements. |

Keep set-entry rows, food search, biomarker charts, navigation icons, and routine logging controls focused on speed and information. Training diagrams remain instructional assets with their own accuracy requirements.

## Art direction

Build a small original family: **medal, trophy, flame, Atlas emblem**. Start with the medal because it serves workout completion and milestone presentation.

- Same camera angle, soft upper-left light, rounded bevels, and visual weight across all four.
- Neutral graphite/pearl body with restrained Atlas accent details. Check against both light and dark backgrounds. Theme-dependent color should remain in native UI where practical.
- Clear silhouettes at the actual display size; reserve detailed artwork for hero areas.
- Keep numerals, achievement names, localized text, and metric values in SwiftUI.
- Proposed motions: medal settles once; trophy receives one light sweep; flame changes within a fixed footprint; emblem assembles once and rests.
- No background halo baked into transparent art. Depth should come from the object and consistent lighting.

This extends the existing `atlas-screen` and `dna-transplant` rules: transplant the hierarchy, retain Atlas tokens and controls, and give each screen one obvious focal point.

## Implementation contract

Prototype a shared `MilestoneArtwork` view only after the first asset is ready. Proposed inputs: artwork kind, static asset, optional motion resource, and an event identifier. It should own playback policy; callers should own achievement logic and text.

Use `AppAnimation` for native transitions and keep existing `AppColor`, `AppFont`, `Spacing`, glass, and pinned-footer primitives. Proposed starting timings are a 250-400 ms UI entrance and a short artwork performance that then rests; tune these on a device rather than treating them as measured reference timings.

Ship a still alongside every motion asset. Reduce Motion, inactive scenes, offscreen content, and playback failure should display the still. Stop and release playback resources when hidden. Decorative art is hidden from VoiceOver; the real milestone label remains accessible. Do not duplicate haptics already owned by the event flow.

Evaluate one transparent asset in a minimal native playback prototype before selecting an animated format or adding a dependency. Test decode cost, memory, frame pacing, alpha edges, and bundle-size delta. Matching first and last frames is a production technique, not proof that a generated loop has no visible seam.

### Source issues to address with the first implementation

- `HeroIcon` changes its `pulse` state but does not use that state in its rendered properties. Its documented breathing effect is therefore not implemented by that state.
- `HeroLogo` gates its idle motion for Reduce Motion, but its `bounceTrigger` handler does not apply the same guard.
- `AchievementToastView` has a bounce and movement transition without reading Reduce Motion. `StreakCounterView` gates its milestone scale but increments the symbol-bounce trigger before that guard.
- Existing tier celebrations and achievement toasts have separate pipelines. Integrate with those owners and explicitly check simultaneous events before introducing another modal.

## First implementation slice and validation

1. Produce one Atlas medal still and assess it at its intended size on light and dark surfaces.
2. Prototype its motion and native playback, retaining the still fallback.
3. Apply it to workout completion; preserve actual session statistics, PR data, and the pinned Done action.
4. Validate a normal finish, a PR finish, dismissal/reopening, and simultaneous achievement events. Confirm no duplicate saves or repeated celebration.
5. Check small-screen layout, largest Dynamic Type, VoiceOver, Reduce Motion, background/foreground transitions, and scrolling performance on iOS 18 and iOS 26.
6. Run `python scripts/design-lint.py --all` and the appropriate Xcode build/checks. Windows source review alone cannot establish visual or playback quality.
7. Reuse the validated component for tier milestones and selected onboarding moments.

Success means the reward feels distinctive, the result is easier to read, and the next action is still immediate. Measure onboarding completion and time to the first logged workout when evaluating the onboarding follow-up; do not assume animation improves conversion.
