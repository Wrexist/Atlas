import Foundation
import SwiftUI

/// Five-dimension daily check-in: energy / sleep / recovery / mood
/// / focus. Each score is on a 1-5 scale so the UI can render as
/// five-point pickers, the math averages cleanly to a single
/// "wellness" composite, and the values are coarse enough that
/// users don't agonise over "is this a 73 or a 78".
///
/// Mirrors the input shape that gives correlation engines real
/// signal: enough dimensions to differentiate (a peptide can boost
/// energy without touching sleep), few enough that the daily
/// check-in is a 30-second commitment, not a chore.
struct OutcomeEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// Wall-clock date the check-in covers. Normalised to start-of-
    /// day on save so the per-day uniqueness constraint works
    /// regardless of when in the day the user actually filled it in.
    let date: Date
    /// 1-5: how energetic did the user feel?
    var energy: Int
    /// 1-5: how restful was the night's sleep?
    var sleepQuality: Int
    /// 1-5: how recovered does the user feel from training /
    /// soreness? High = recovered, low = still beat up.
    var recovery: Int
    /// 1-5: mood. Subjective, but tracks well with peptide
    /// protocols that target wellbeing (e.g. selank, semax).
    var mood: Int
    /// 1-5: cognitive sharpness. High = focused; low = brain fog.
    var focus: Int
    /// Optional free-text note. Surfaced on the timeline view; not
    /// fed to the correlation engine (semantic analysis is a
    /// separate AI hop).
    var note: String?
    /// Stamp on create / edit. Useful for the "edited" badge in
    /// the timeline if a user fills in a retroactive day.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        energy: Int,
        sleepQuality: Int,
        recovery: Int,
        mood: Int,
        focus: Int,
        note: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.energy = energy
        self.sleepQuality = sleepQuality
        self.recovery = recovery
        self.mood = mood
        self.focus = focus
        self.note = note
        self.updatedAt = updatedAt
    }

    /// Composite "wellness" score. Simple average across the five
    /// dimensions. Useful for the trend sparkline; the correlation
    /// engine still operates on individual dimensions because a
    /// peptide can move one without the others.
    var composite: Double {
        Double(energy + sleepQuality + recovery + mood + focus) / 5.0
    }
}

/// Five named dimensions that drive both the check-in UI and the
/// correlation engine's per-dimension columns. Kept as an enum so
/// the rest of the codebase can iterate without hard-coded strings.
enum OutcomeDimension: String, CaseIterable, Identifiable, Sendable {
    case energy
    case sleepQuality
    case recovery
    case mood
    case focus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .energy:       String(localized: "Energy",  comment: "Outcome dimension — how energetic")
        case .sleepQuality: String(localized: "Sleep",   comment: "Outcome dimension — sleep quality")
        case .recovery:     String(localized: "Recovery", comment: "Outcome dimension — feeling recovered from training")
        case .mood:         String(localized: "Mood",    comment: "Outcome dimension — emotional state")
        case .focus:        String(localized: "Focus",   comment: "Outcome dimension — cognitive sharpness")
        }
    }

    var icon: String {
        switch self {
        case .energy:       "bolt.fill"
        case .sleepQuality: "moon.zzz.fill"
        case .recovery:     "figure.run"
        case .mood:         "face.smiling.fill"
        case .focus:        "brain.head.profile"
        }
    }

    /// Single source of truth for the per-dimension accent tint —
    /// consumed by the check-in sliders, the timeline rows, and the
    /// correlation card. Mirrors `MealCategory.tint`'s pattern of
    /// pinning a small palette to the model so UI surfaces don't
    /// drift apart.
    var tint: Color {
        switch self {
        case .energy:       Color(red: 1.00, green: 0.78, blue: 0.20)
        case .sleepQuality: Color(red: 0.48, green: 0.50, blue: 0.92)
        case .recovery:     Color(red: 0.36, green: 0.78, blue: 0.55)
        case .mood:         Color(red: 0.95, green: 0.50, blue: 0.55)
        case .focus:        Color(red: 0.40, green: 0.74, blue: 0.92)
        }
    }

    /// Extracts the score for this dimension from an `OutcomeEntry`.
    /// Lets correlation math operate generically over a list of
    /// `(dimension, entry) -> Int` pairs instead of branching on
    /// every dimension explicitly.
    func value(in entry: OutcomeEntry) -> Int {
        switch self {
        case .energy:       entry.energy
        case .sleepQuality: entry.sleepQuality
        case .recovery:     entry.recovery
        case .mood:         entry.mood
        case .focus:        entry.focus
        }
    }
}
