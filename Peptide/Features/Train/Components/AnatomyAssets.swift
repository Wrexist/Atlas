import SwiftUI

/// Optional photoreal asset pack for the muscle map.
///
/// `MuscleMapView` draws a clean vector figure out of the box. If the app
/// later ships a set of anatomy images named by the convention below,
/// `MuscleMapView` automatically switches to rendering them instead — a
/// base body image overlaid with one tinted alpha mask per muscle — for a
/// fully realistic, photoreal look. No call-site changes are needed: the
/// switch is driven entirely by whether the assets are present.
///
/// To enable, add to the asset catalog (Assets.xcassets):
/// - `anatomy_body_front`, `anatomy_body_back` — the grayscale body
///   renders (front + back), same canvas size / framing as each other.
/// - `anatomy_<muscle>` — one image per muscle, pixel-aligned to the
///   matching base body, where `<muscle>` is the `AnatomicalMuscle`
///   raw value: `anatomy_chest`, `anatomy_lats`, `anatomy_quadricepsLeft`,
///   `anatomy_glutesRight`, … Provide them as template/alpha shapes so
///   they tint cleanly by training intensity (a flat silhouette of each
///   muscle is enough; the base image supplies the shading underneath).
///
/// Until those assets exist, `isAvailable` is `false` and the vector map
/// renders, so the figure is never blank.
enum AnatomyAssets {
    static let bodyFront = "anatomy_body_front"
    static let bodyBack = "anatomy_body_back"

    /// Grayscale muscle-écorché renders, pixel-aligned to the skin bodies.
    /// The map is a two-layer look: the colour body is smooth skin (resting
    /// state) and this grayscale écorché is the *muscle-reveal* layer —
    /// `colorMultiply` tints it to the activation hue and clips it to a
    /// muscle's mask, so a trained muscle surfaces through the skin with its
    /// shading intact. Falls back to the colour body if a grayscale render
    /// isn't bundled.
    static let bodyFrontGray = "anatomy_body_front_gray"
    static let bodyBackGray = "anatomy_body_back_gray"

    /// The grayscale tint source for a facing, or the colour body when no
    /// grayscale render ships.
    static func tintBase(front: Bool) -> String {
        let gray = front ? bodyFrontGray : bodyBackGray
        #if canImport(UIKit)
        if UIImage(named: gray) != nil { return gray }
        #endif
        return front ? bodyFront : bodyBack
    }

    /// Provenance / licence note for the bundled pack. The muscle pack is
    /// rendered from the open-source **Z-Anatomy** model (z-anatomy.com),
    /// licensed **CC BY-SA 4.0** — so attribution is required and the
    /// renders are shared alike. `tools/render_zanatomy.py` documents the
    /// headless render that produced the base bodies + per-muscle masks.
    /// Surfaced in the Profile › About credits.
    static let attribution = "Muscle anatomy from Z-Anatomy (z-anatomy.com), CC BY-SA 4.0."
    static let attributionURL = "https://www.z-anatomy.com"

    /// Asset name for a muscle's tintable mask.
    static func mask(for muscle: AnatomicalMuscle) -> String {
        "anatomy_\(muscle.rawValue)"
    }

    /// True once both base body images ship in the bundle. Resolved once
    /// — assets don't change at runtime — so the per-render branch in
    /// `MuscleMapView` is a cheap boolean read.
    static let isAvailable: Bool = imageExists(bodyFront) && imageExists(bodyBack)

    private static func imageExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return false
        #endif
    }

    #if DEBUG
    /// Muscles whose mask image is missing from the bundle. Empty when the
    /// pack is complete — or absent entirely. Drives the launch-time audit
    /// and the `AnatomyDebugView` alignment harness.
    static func missingMasks() -> [AnatomicalMuscle] {
        guard isAvailable else { return [] }
        return AnatomicalMuscle.allCases.filter { !imageExists(mask(for: $0)) }
    }

    /// Asserts loudly if a shipped anatomy pack is missing any muscle
    /// mask, so a half-imported set is caught at launch rather than
    /// rendering silent gaps. No-op when the pack isn't bundled. Call once
    /// from `PeptideApp.init()`.
    static func auditCoverage() {
        let missing = missingMasks()
        guard !missing.isEmpty else { return }
        let names = missing.map { mask(for: $0) }.joined(separator: ", ")
        assertionFailure("AnatomyAssets: base bodies present but masks missing: \(names)")
    }
    #endif
}
