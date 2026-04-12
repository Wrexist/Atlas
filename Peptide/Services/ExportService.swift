import Foundation

final class ExportService {
    static let shared = ExportService()
    private init() {}

    // MARK: - CSV Export

    func exportProtocolsCSV(protocols: [PeptideProtocol], entries: [ProtocolEntry]) -> String {
        var csv = "Date,Protocol,Peptide,Scheduled Dose,Actual Dose,Time,Injection Site,Completed,Notes\n"

        let sortedEntries = entries.sorted { $0.date > $1.date }

        for entry in sortedEntries {
            let protocolName = protocols.first { $0.id == entry.protocolId }?.name ?? "Unknown"
            let dateStr = entry.date.formatted(.iso8601.year().month().day())
            let timeStr = entry.date.formatted(.dateTime.hour().minute())
            let actualDose = entry.actualDose ?? entry.dose
            let site = entry.injectionSite ?? ""
            let notes = entry.notes.replacingOccurrences(of: ",", with: ";")

            csv += "\(dateStr),\(protocolName),\(entry.peptide.abbreviation),\(entry.dose),\(actualDose),\(timeStr),\(site),\(entry.completed),\(notes)\n"
        }

        return csv
    }

    // MARK: - JSON Backup

    func exportFullBackup(protocols: [PeptideProtocol], entries: [ProtocolEntry], profile: UserProfile) -> Data? {
        let backup = AppBackup(
            exportDate: Date(),
            version: "1.0",
            protocols: protocols,
            entries: entries,
            profile: profile
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(backup)
    }

    // MARK: - File URLs

    func writeCSV(_ content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func writeJSON(_ data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

struct AppBackup: Codable {
    let exportDate: Date
    let version: String
    let protocols: [PeptideProtocol]
    let entries: [ProtocolEntry]
    let profile: UserProfile
}
