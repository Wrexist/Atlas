import Foundation

/// Coordinates the AI weekly summary lifecycle. Owns the network
/// call to the Vercel proxy, the on-disk cache (one entry per
/// week on `UserProfile.weeklySummaries`), the Pro gate, the
/// opt-out check, and the deterministic offline fallback.
///
/// Gating order on `generate(...)`:
///   1. `enabled` (Pro user + profile opt-in) → else throw
///      `.disabled`
///   2. Cached summary for this week exists? → return it
///   3. Engine produces a non-nil aggregate? → else throw
///      `.insufficientData`
///   4. Proxy call succeeds → return AI summary
///   5. Proxy call fails → return deterministic offline summary
///      (still cached so repeated taps don't re-fire the call)
@MainActor
final class WeeklySummaryService {
    static let shared = WeeklySummaryService()

    private let session: URLSession
    private let endpointOverride: URL?

    /// Maximum cached weekly summaries before older ones are
    /// trimmed. 26 weeks × ~500 bytes per summary = ~13 KB JSON,
    /// well within the comfortable bound for the profile sidecar.
    static let maxCachedSummaries: Int = 26

    init(session: URLSession = .shared, endpointOverride: URL? = nil) {
        self.session = session
        self.endpointOverride = endpointOverride
    }

    // MARK: - Gates

    /// True when the feature is allowed to run for this user.
    /// Pro check + per-user opt-out toggle. View layer reads this
    /// to decide whether to render the summary card at all.
    func isAvailable(profile: UserProfile) -> Bool {
        guard StoreService.shared.canAccessAIFeatures else { return false }
        return profile.weeklySummaryEnabled
    }

    // MARK: - Generation

    enum GenerationError: Error {
        /// User isn't Pro or has the toggle off — caller suppresses
        /// the card entirely.
        case disabled
        /// `WeeklySummaryEngine.build(...)` returned nil. Fewer
        /// than 3 active dose days in the window. Caller suppresses
        /// the card.
        case insufficientData
        case proxyNotConfigured
        case requestFailed(String)
    }

    /// Generates the summary for the current week. Pure with
    /// respect to `profile` — never mutates it. Caller writes the
    /// returned summary back via `record(_:in:)` once the await
    /// resolves; splitting read + write avoids passing inout
    /// across an await point, which Swift 6's exclusivity check
    /// rightly complains about for reference-rooted lvalues.
    func generate(
        profile: UserProfile,
        protocols: [PeptideProtocol],
        entries: [ProtocolEntry],
        hrvSeries: [(date: Date, value: Double)] = [],
        rhrSeries: [(date: Date, value: Double)] = [],
        sleepSeries: [(date: Date, value: Double)] = [],
        topInsightCategory: String? = nil,
        referenceDate: Date = Date(),
        forceRefresh: Bool = false
    ) async throws -> WeeklySummary {
        guard isAvailable(profile: profile) else {
            throw GenerationError.disabled
        }

        guard let aggregate = WeeklySummaryEngine.build(
            profile: profile,
            protocols: protocols,
            entries: entries,
            referenceDate: referenceDate,
            hrvSeries: hrvSeries,
            rhrSeries: rhrSeries,
            sleepSeries: sleepSeries,
            topInsightCategory: topInsightCategory
        ) else {
            throw GenerationError.insufficientData
        }

        // Cache hit — return without re-firing the API call unless
        // the caller explicitly asked for a refresh.
        if !forceRefresh, let cached = profile.weeklySummaries[aggregate.weekStart] {
            return cached
        }

        return await fetchOrFallback(aggregate: aggregate)
    }

    /// Inserts the summary into the profile's cache and trims to
    /// `maxCachedSummaries`. Sync, so calling sites can hop on the
    /// main actor and write without crossing an await — Swift 6
    /// exclusivity friendly.
    func record(_ summary: WeeklySummary, in profile: inout UserProfile) {
        write(summary: summary, into: &profile)
    }

    /// Retrieves a cached summary if one exists for the week
    /// containing `date`. Read-only — does not mutate the profile
    /// and does not trigger a fetch. Used by archive views.
    func cached(in profile: UserProfile, for date: Date) -> WeeklySummary? {
        let weekStart = Self.weekStartString(for: date)
        return profile.weeklySummaries[weekStart]
    }

    // MARK: - Network

    /// Calls the proxy, falls back to a deterministic offline
    /// summary when the network is unreachable. Both branches
    /// produce a `WeeklySummary` with the same shape so the UI
    /// renders identically; only the `kind` field distinguishes.
    private func fetchOrFallback(aggregate: WeeklyAggregate) async -> WeeklySummary {
        do {
            let text = try await fetchAISummary(aggregate: aggregate)
            return WeeklySummary(
                weekStart: aggregate.weekStart,
                text: text,
                keyStats: keyStats(from: aggregate),
                kind: .ai,
                generatedAt: Date()
            )
        } catch {
            // `.private` — `String(describing:)` on a URLError /
            // DecodingError can carry the proxy endpoint URL and
            // response-body fragments, which shouldn't land in
            // Console.app / sysdiagnose at `.public`.
            AppLog.persistence.error(
                "Weekly summary fetch failed: \(String(describing: error), privacy: .private)"
            )
            return WeeklySummary(
                weekStart: aggregate.weekStart,
                text: OfflineWeeklySummaryFormatter.summary(from: aggregate),
                keyStats: keyStats(from: aggregate),
                kind: .offline,
                generatedAt: Date()
            )
        }
    }

    private func fetchAISummary(aggregate: WeeklyAggregate) async throws -> String {
        guard let endpoint = endpoint else {
            throw GenerationError.proxyNotConfigured
        }
        guard let secret = proxySecret, !secret.isEmpty else {
            throw GenerationError.proxyNotConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Peptide-Proxy")
        request.httpBody = try JSONEncoder().encode(RequestEnvelope(aggregate: aggregate))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GenerationError.requestFailed("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GenerationError.requestFailed("HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GenerationError.requestFailed("Empty text")
        }
        return trimmed
    }

    // MARK: - Cache write

    /// Inserts the summary keyed by `weekStart`, then trims to
    /// the `maxCachedSummaries` newest entries so the JSON stays
    /// small under long-running use.
    private func write(summary: WeeklySummary, into profile: inout UserProfile) {
        profile.weeklySummaries[summary.weekStart] = summary
        if profile.weeklySummaries.count > Self.maxCachedSummaries {
            let sorted = profile.weeklySummaries.keys.sorted(by: >)
            let keep = Set(sorted.prefix(Self.maxCachedSummaries))
            profile.weeklySummaries = profile.weeklySummaries.filter { keep.contains($0.key) }
        }
    }

    // MARK: - Helpers

    /// Builds the cache key "yyyy-MM-dd" anchored to the user's local
    /// calendar's week-start. Previously ISO8601DateFormatter had no
    /// timezone set and defaulted to UTC, while the week-range
    /// computation ran in user-local TZ — for users east of UTC
    /// (AEDT, JST) the key wrote the previous Sunday's date and
    /// cache lookups missed (audit Biology H8). Now stamps with the
    /// calendar's timezone so the key round-trips locally.
    private static func weekStartString(for date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        // Fall back to the date itself (not `DateInterval()`, whose
        // start is `.distantPast` — that produced a `0001-01-01` key
        // that never matched any real lookup, re-firing the API).
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: interval.start)
    }

    private func keyStats(from aggregate: WeeklyAggregate) -> WeeklySummary.KeyStats {
        let composite = aggregate.outcomes.map {
            ($0.energyAvg + $0.sleepAvg + $0.recoveryAvg + $0.moodAvg + $0.focusAvg) / 5.0
        }
        return WeeklySummary.KeyStats(
            compliancePct: aggregate.compliance.pct,
            dosesCompleted: aggregate.compliance.completed,
            dosesTotal: aggregate.compliance.total,
            currentStreak: aggregate.streak.current,
            avgCheckInScore: composite,
            avgCalories: aggregate.nutrition?.avgCalories,
            hrvDelta: aggregate.biometrics?.hrvDelta
        )
    }

    private var endpoint: URL? {
        endpointOverride ?? MealScannerService.urlSetting(forKey: "WEEKLY_SUMMARY_ENDPOINT")
    }

    private var proxySecret: String? {
        MealScannerService.stringSetting(forKey: "WEEKLY_SUMMARY_SECRET")
    }

    // MARK: - Wire formats

    private struct RequestEnvelope: Encodable {
        let aggregate: WeeklyAggregate
    }

    private struct ResponseEnvelope: Decodable {
        let text: String
        let generatedAt: String?
    }
}
