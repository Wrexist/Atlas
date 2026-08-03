import Foundation

/// Catalog of every biomarker the Biology tab can render. Each
/// case carries its presentation metadata (display name, SF
/// Symbol, unit, default ordering, Pro gate) so the view layer
/// reads everything from one switch instead of hard-coding tile
/// after tile.
///
/// Adding a new biomarker: append a case, fill the switches.
/// `BiomarkerSeriesService` is the next stop — that's where the
/// actual data fetch lives. Keeping the catalog and the fetch in
/// separate files makes the catalog safe to import from view code
/// without dragging HealthKit / DataStore into the view's surface
/// area.
enum Biomarker: String, CaseIterable, Codable, Hashable, Sendable {
    case weight
    case hrvBaseline
    case rhrBaseline
    case sleepBaseline
    case stepsBaseline
    case bodyTemperature
    case bodyFat
    case waist
    case bloodPressure
    case latestLabPanel

    // MARK: - Presentation

    var displayName: String {
        switch self {
        case .weight:           String(localized: "Weight")
        case .hrvBaseline:      String(localized: "HRV baseline")
        case .rhrBaseline:      String(localized: "Resting HR baseline")
        case .sleepBaseline:    String(localized: "Sleep baseline")
        case .stepsBaseline:    String(localized: "Steps baseline")
        case .bodyTemperature:  String(localized: "Body temperature")
        case .bodyFat:          String(localized: "Body fat")
        case .waist:            String(localized: "Waist")
        case .bloodPressure:    String(localized: "Blood pressure")
        case .latestLabPanel:   String(localized: "Latest labs")
        }
    }

    /// SF Symbol used by `BiomarkerRow`'s trend badge background.
    /// Sized for a 28–32pt circle, so prefer the `.fill` variants
    /// that hold their weight at small sizes.
    var icon: String {
        switch self {
        case .weight:           "scalemass.fill"
        case .hrvBaseline:      "waveform.path.ecg"
        case .rhrBaseline:      "heart.fill"
        case .sleepBaseline:    "bed.double.fill"
        case .stepsBaseline:    "figure.walk"
        case .bodyTemperature:  "thermometer.medium"
        case .bodyFat:          "figure"
        case .waist:            "ruler.fill"
        case .bloodPressure:    "heart.text.square.fill"
        case .latestLabPanel:   "cross.vial.fill"
        }
    }

    /// Locale-aware unit string. `MeasurementUnit.imperial` swaps
    /// kg → lb, cm → in, °C → °F. The numeric value itself is
    /// converted at the render site (BiomarkerRow uses the
    /// user's BodyMetrics.unit to choose).
    func displayUnit(for unit: MeasurementUnit) -> String? {
        switch self {
        case .weight:           return unit == .imperial ? "lb" : "kg"
        case .hrvBaseline:      return "ms"
        case .rhrBaseline:      return "bpm"
        case .sleepBaseline:    return "h"
        case .stepsBaseline:    return "steps"
        case .bodyTemperature:  return unit == .imperial ? "°F" : "°C"
        case .bodyFat:          return "%"
        case .waist:            return unit == .imperial ? "in" : "cm"
        case .bloodPressure:    return "mmHg"
        case .latestLabPanel:   return nil
        }
    }

    /// Converts a metric-stored value to the user's preferred unit
    /// for display. Pure presentation — the underlying storage stays
    /// canonical metric.
    func displayValue(_ metricValue: Double, for unit: MeasurementUnit) -> Double {
        guard unit == .imperial else { return metricValue }
        switch self {
        case .weight:           return unit.weightForDisplay(metricValue)
        case .waist:            return metricValue / 2.54            // cm → in
        case .bodyTemperature:  return metricValue * 9.0 / 5.0 + 32  // °C → °F
        default:                return metricValue
        }
    }

    /// True when the biomarker's data comes (entirely or partly)
    /// from HealthKit. The UI uses this to suppress cards when
    /// the user hasn't connected Health, vs cards backed by
    /// manual logging that work standalone.
    var requiresHealthKit: Bool {
        switch self {
        case .hrvBaseline, .rhrBaseline, .sleepBaseline,
             .stepsBaseline, .bodyTemperature:
            return true
        case .weight, .bodyFat, .waist, .bloodPressure, .latestLabPanel:
            return false
        }
    }

    /// True when the biomarker is gated behind Atlas Pro. The
    /// HealthKit baselines are free (already collected by the
    /// app's existing surfaces); manual-entry body composition
    /// + lab markers are Pro because they require additional
    /// engagement and unlock the Bio-Age signal.
    var requiresPro: Bool {
        switch self {
        case .weight, .hrvBaseline, .rhrBaseline,
             .sleepBaseline, .stepsBaseline:
            return false
        case .bodyTemperature, .bodyFat, .waist,
             .bloodPressure, .latestLabPanel:
            return true
        }
    }

    /// Default display order on the Biology tab. The user can
    /// override this in EditBiomarkersSheet (commit 8); the
    /// stored config falls back to this when no override is set.
    var preferredOrder: Int {
        switch self {
        case .weight:           return 0
        case .hrvBaseline:      return 1
        case .rhrBaseline:      return 2
        case .sleepBaseline:    return 3
        case .stepsBaseline:    return 4
        case .bodyTemperature:  return 5
        case .bodyFat:          return 6
        case .waist:            return 7
        case .bloodPressure:    return 8
        case .latestLabPanel:   return 9
        }
    }

    /// Biomarkers shown by default on a fresh install. Curated to
    /// the four free-tier HealthKit baselines + weight so the tab
    /// has something to render before the user goes shopping in
    /// EditBiomarkersSheet.
    static let defaultVisible: [Biomarker] = [
        .weight, .hrvBaseline, .rhrBaseline, .sleepBaseline,
    ]
}

// MARK: - Snapshot returned by the series service

/// What the view actually reads. `BiomarkerRow` consumes this
/// shape directly; no further math in the view layer.
struct BiomarkerSnapshot: Equatable, Sendable, Identifiable {
    var id: Biomarker { biomarker }

    let biomarker: Biomarker
    /// Most recent reading, in the biomarker's canonical unit
    /// (kg / ms / bpm / hours / steps / °C / %). `nil` when no
    /// reading exists yet — the UI degrades to "No data".
    let latest: Double?
    let trend: Trend
    /// 14 daily samples, oldest → newest. Empty when the data
    /// source doesn't support a series (e.g. blood pressure
    /// without manual log history) — the row hides its sparkline
    /// in that case.
    let sparkline: [Double]
    /// Pre-formatted "verb + value" line for the row subtitle,
    /// e.g. "Increasing · 72.0 kg". Localized in this layer so
    /// the view doesn't redo the formatting.
    let changeText: String

    enum Trend: String, Equatable, Sendable {
        case up           // value rising over the window
        case down         // value falling
        case flat         // change below the noise floor
        case insufficient // not enough data to call a trend
    }

    /// Empty / no-data sentinel — used by the view when a tile
    /// renders but its data hasn't arrived yet.
    static func empty(_ biomarker: Biomarker) -> BiomarkerSnapshot {
        BiomarkerSnapshot(
            biomarker: biomarker,
            latest: nil,
            trend: .insufficient,
            sparkline: [],
            changeText: String(localized: "No data")
        )
    }
}
