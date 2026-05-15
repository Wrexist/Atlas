import Foundation

/// Free-form qualitative journal entry attached to a specific
/// protocol on a specific day. Sits alongside the quantitative
/// data (doses, macros, labs, outcomes) so users can capture
/// "felt great after BPC today", "skipped Friday due to travel",
/// or "side-effect: mild headache 2h post-dose" without losing
/// the context to a separate notes app.
///
/// Per-day, per-protocol — multiple notes on the same day are
/// allowed (different protocols, different times) so a user
/// running three stacks can journal each independently.
struct ProtocolNote: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// Which protocol this note attaches to. Lets the timeline
    /// view filter and the export pipeline join by protocol.
    var protocolID: UUID
    /// Wall-clock date the note covers. Stored at the timestamp
    /// the user added it; the view bins by start-of-day for the
    /// timeline grouping.
    var date: Date
    /// The note body — free-form, no length cap (the editor
    /// nudges below 500 chars in copy but doesn't enforce).
    var body: String
    /// Optional mood tag picked from the 1-5 scale users already
    /// know from the daily check-in. Lets the timeline render a
    /// tinted dot per note without making the user invent
    /// taxonomy. Nil when the user didn't pick one.
    var mood: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        protocolID: UUID,
        date: Date = Date(),
        body: String,
        mood: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.protocolID = protocolID
        self.date = date
        self.body = body
        self.mood = mood
        self.updatedAt = updatedAt
    }
}
