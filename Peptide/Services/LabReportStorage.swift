import Foundation
import UIKit

/// The pages of each scanned lab report, kept on this device so the user
/// can check a transcribed value against the original. One folder per
/// report under Documents/LabReports, named by the `reportID` its lab
/// values carry; pages are JPEGs downscaled like progress photos.
///
/// Nothing here goes to iCloud, sync or device backup: a lab report is
/// health data, and the lab values that reference it sync without it. On a device that
/// never had the file the viewer simply has nothing to show.
enum LabReportStorage {

    private static let folderName = "LabReports"

    /// Writes every page, replacing any earlier copy of the same report.
    /// Downscaling and encoding up to four camera pages is slow, so it
    /// all runs off the main actor.
    static func save(pages: [UIImage], reportID: UUID) async throws {
        try await Task.detached(priority: .userInitiated) {
            let encoded = pages.compactMap { ProgressPhotoStorage.downscaled($0).jpegData(compressionQuality: 0.85) }
            try write(encoded, reportID: reportID)
        }.value
    }

    /// The report's pages in order, empty when this device has none.
    static func pageURLs(for reportID: UUID) -> [URL] {
        guard let folder = try? folder(for: reportID),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { $0.hasSuffix(".jpg") }.sorted().map { folder.appendingPathComponent($0) }
    }

    static func exists(_ reportID: UUID) -> Bool {
        !pageURLs(for: reportID).isEmpty
    }

    static func delete(_ reportID: UUID) {
        guard let folder = try? folder(for: reportID) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        } catch {
            AppLog.persistence.error("LabReportStorage.delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// "Delete all data" / account deletion: reports must not survive it.
    static func deleteAll() {
        guard let root = try? root() else { return }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Private

    private static func write(_ pages: [Data], reportID: UUID) throws {
        let folder = try folder(for: reportID)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            // Excluding the folder keeps every page in it out of device backups.
            var url = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            for (index, data) in pages.enumerated() {
                try data.write(to: folder.appendingPathComponent(pageName(index)), options: [.atomic, .completeFileProtection])
            }
        } catch {
            // No lab value will point at a half-written report, so nothing
            // would ever delete it.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private static func pageName(_ index: Int) -> String {
        String(format: "page-%02d.jpg", index + 1)
    }

    private static func folder(for reportID: UUID) throws -> URL {
        try root().appendingPathComponent(reportID.uuidString, isDirectory: true)
    }

    private static func root() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }
}
