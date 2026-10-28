import Foundation

/// What the fasting widget shows, written by the app to the App Group
/// container whenever a fast starts, ends or is edited. Its own file
/// rather than fields on `WidgetData`: a fast changes on its own
/// schedule, and rewriting the shared payload for it would spend every
/// other widget's reload budget too.
struct FastingWidgetSnapshot: Codable, Equatable, Sendable {
    struct Active: Codable, Equatable, Sendable {
        let fastId: UUID
        let window: FastingWindow
        /// Pre-resolved app-side ("16:8", "OMAD").
        let protocolName: String
    }

    /// The open fast, or nil when the user isn't fasting.
    let active: Active?

    static let notFasting = FastingWidgetSnapshot(active: nil)

    /// Matches `FastingWidget.kind`, so the app can reload just this widget.
    static let widgetKind = "FastingWidget"
    static let fileName = "fasting-widget.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent(fileName)
    }

    /// ISO-8601 dates, like `widget-data.json`, so the file reads the
    /// same in either process whatever the default strategy becomes.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> FastingWidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FastingWidgetSnapshot.self, from: data)
    }
}
