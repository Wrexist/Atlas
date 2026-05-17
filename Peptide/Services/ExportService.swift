import Foundation
@preconcurrency import UIKit

@MainActor
final class ExportService {
    static let shared = ExportService()
    private init() {}

    /// Total-entry cutoff under which the PDF paginates every entry
    /// for a protocol. Above this, the report shows only the recent
    /// `pdfRecentEntryLimit` and references the CSV for the rest.
    /// 90 fits ~3 months of daily dosing in a single PDF section
    /// without the medical-report becoming unreadable.
    static let pdfFullDetailLimit: Int = 90

    /// How many recent entries to keep when total > pdfFullDetailLimit.
    /// 30 ≈ one screen / one printed page; the monthly summary above
    /// covers the missing window.
    static let pdfRecentEntryLimit: Int = 30

    /// Returns one row per month covered by `entries`, newest-first.
    /// Months with zero activity are suppressed. Used by the PDF
    /// monthly-summary block to give the reader a trend view that
    /// stays complete regardless of how many entry rows the body
    /// truncates.
    static func monthlyBuckets(for entries: [ProtocolEntry]) -> [PDFMonthlyBucket] {
        guard !entries.isEmpty else { return [] }
        let cal = Calendar.current
        // Drop entries whose month-start can't be derived (would only
        // happen with a severely broken calendar). The previous
        // fallback to the raw `entry.date` produced a bucket keyed on
        // a full timestamp, which the LLLL-yyyy formatter rendered as
        // a day-level label and sorted incoherently.
        let bucketable: [(Date, ProtocolEntry)] = entries.compactMap { entry in
            let comps = cal.dateComponents([.year, .month], from: entry.date)
            guard let monthStart = cal.date(from: comps) else { return nil }
            return (monthStart, entry)
        }
        let grouped = Dictionary(grouping: bucketable, by: \.0)
            .mapValues { $0.map(\.1) }
        let monthFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "LLLL yyyy"
            return f
        }()
        return grouped
            .map { monthStart, group -> PDFMonthlyBucket in
                let logged = group.filter(\.completed).count
                let total = group.count
                let pct = total > 0 ? Int(Double(logged) / Double(total) * 100) : 0
                return PDFMonthlyBucket(
                    monthStart: monthStart,
                    label: monthFormatter.string(from: monthStart),
                    logged: logged,
                    missed: total - logged,
                    compliancePct: pct
                )
            }
            .sorted { $0.monthStart > $1.monthStart }
    }

    struct PDFMonthlyBucket: Equatable {
        let monthStart: Date
        let label: String
        let logged: Int
        let missed: Int
        let compliancePct: Int
    }

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

            let fields = [
                dateStr,
                csvQuote(protocolName),
                csvQuote(entry.peptide.abbreviation),
                csvQuote(entry.dose),
                csvQuote(actualDose),
                timeStr,
                csvQuote(site),
                "\(entry.completed)",
                csvQuote(entry.notes),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }

        return csv
    }

    // MARK: - Labs

    /// CSV of every blood-work entry. Columns chosen to round-trip
    /// cleanly to a doctor's spreadsheet workflow: ISO date first
    /// (sortable in any tool), panel display name + canonical
    /// unit pair, value, optional source + note. The full lab name
    /// (not the short chip-label) is used so the export reads
    /// without mental decoding ("Total testosterone" vs. "Total T").
    func exportLabsCSV(labs: [LabValue]) -> String {
        var csv = "Date,Panel,Value,Unit,Source,Notes\n"
        let sorted = labs.sorted { $0.date > $1.date }
        for entry in sorted {
            let dateStr = entry.date.formatted(.iso8601.year().month().day())
            let value = formatLabValue(entry.value)
            let fields = [
                dateStr,
                csvQuote(entry.panel.displayName),
                csvQuote(value),
                csvQuote(entry.panel.canonicalUnit),
                csvQuote(entry.source ?? ""),
                csvQuote(entry.note ?? ""),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    // MARK: - Meals

    /// CSV of every meal log entry. Columns: ISO date + time,
    /// meal category, food name, calories, macros in grams, source
    /// (search / barcode / photo / custom). One row per logged
    /// meal so a nutritionist can pivot the table by category +
    /// week without splitting cells.
    func exportMealsCSV(meals: [MealEntry]) -> String {
        var csv = "Date,Time,Category,Name,Calories,Protein,Carbs,Fat,Source\n"
        let sorted = meals.sorted { $0.date > $1.date }
        for entry in sorted {
            let dateStr = entry.date.formatted(.iso8601.year().month().day())
            let timeStr = entry.date.formatted(.dateTime.hour().minute())
            let fields = [
                dateStr,
                timeStr,
                csvQuote(entry.category.displayName),
                csvQuote(entry.name),
                "\(entry.calories)",
                "\(entry.proteinG)",
                "\(entry.carbsG)",
                "\(entry.fatG)",
                csvQuote(entry.source.rawValue),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    // MARK: - Outcome check-ins

    /// CSV of every daily wellness check-in. Five 1-5 scores per
    /// row plus the optional note. Lets the user paste their
    /// history into a spreadsheet and overlay it against any
    /// other column they're already tracking (training load,
    /// supplement schedule, etc.).
    func exportOutcomesCSV(outcomes: [OutcomeEntry]) -> String {
        var csv = "Date,Energy,Sleep,Recovery,Mood,Focus,Note\n"
        let sorted = outcomes.sorted { $0.date > $1.date }
        for entry in sorted {
            let dateStr = entry.date.formatted(.iso8601.year().month().day())
            let fields = [
                dateStr,
                "\(entry.energy)",
                "\(entry.sleepQuality)",
                "\(entry.recovery)",
                "\(entry.mood)",
                "\(entry.focus)",
                csvQuote(entry.note ?? ""),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    /// Smart number formatter for lab CSV cells. Whole numbers
    /// drop the decimal so "600" exports as "600" not "600.0";
    /// fractional values keep two decimals so a 0.85 ng/mL TSH
    /// reads honestly. Falls back through `String(value)` for
    /// values smaller than 0.01 to avoid scientific notation.
    private func formatLabValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        if abs(value) < 0.01 {
            return String(value)
        }
        return String(format: "%.2f", value)
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
        do {
            return try encoder.encode(backup)
        } catch {
            AppLog.export.error("exportFullBackup encode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - PDF Export

    // swiftlint:disable:next function_body_length
    func exportPDF(protocols: [PeptideProtocol], entries: [ProtocolEntry], profile: UserProfile) throws -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Atlas Protocol Report",
            kCGPDFContextAuthor as String: "Atlas",
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin

            // MARK: Helpers

            func startPage() {
                ctx.beginPage()
                y = margin
            }

            func checkPageBreak(for height: CGFloat) {
                if y + height > pageHeight - margin - 20 { startPage() }
            }

            @discardableResult
            func drawText(
                _ text: String,
                font: UIFont,
                color: UIColor = .black,
                x: CGFloat = margin,
                width: CGFloat = contentWidth,
                align: NSTextAlignment = .left
            ) -> CGFloat {
                let style = NSMutableParagraphStyle()
                style.alignment = align
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: style,
                ]
                let bounds = text.boundingRect(
                    with: CGSize(width: width, height: 2000),
                    options: .usesLineFragmentOrigin,
                    attributes: attrs,
                    context: nil
                )
                let h = ceil(bounds.height)
                text.draw(in: CGRect(x: x, y: y, width: width, height: h), withAttributes: attrs)
                return h
            }

            // Measures text height without drawing — used to pre-compute row height
            // so checkPageBreak gets the real value before any drawing occurs.
            func measureText(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let bounds = text.boundingRect(
                    with: CGSize(width: width, height: 2000),
                    options: .usesLineFragmentOrigin,
                    attributes: attrs,
                    context: nil
                )
                return ceil(bounds.height)
            }

            func drawRule(color: UIColor = UIColor(white: 0.82, alpha: 1)) {
                color.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: contentWidth, height: 0.5)).fill()
                y += 0.5
            }

            // MARK: Fonts & colors

            let titleFont   = UIFont.boldSystemFont(ofSize: 20)
            let sectionFont = UIFont.boldSystemFont(ofSize: 12)
            let labelFont   = UIFont.systemFont(ofSize: 9, weight: .semibold)
            let bodyFont    = UIFont.systemFont(ofSize: 9)
            let captionFont = UIFont.systemFont(ofSize: 8)

            let accentColor = UIColor(red: 0.38, green: 0.60, blue: 1.0, alpha: 1)
            let mutedColor  = UIColor(white: 0.50, alpha: 1)
            let greenColor  = UIColor(red: 0.18, green: 0.72, blue: 0.42, alpha: 1)
            let redColor    = UIColor(red: 0.85, green: 0.30, blue: 0.30, alpha: 1)

            // Table column x-positions
            let cDate: CGFloat = margin
            let cPep: CGFloat = margin + 72
            let cDose: CGFloat = margin + 187
            let cTime: CGFloat = margin + 267
            let cSite: CGFloat = margin + 342
            let cDone: CGFloat = margin + 442

            // MARK: Page 1 — header + summary

            startPage()

            let titleH = drawText("Atlas Protocol Report", font: titleFont, color: accentColor)
            y += titleH + 4

            let userName = profile.name.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Atlas User" : profile.name
            let dateStr = Date().formatted(date: .long, time: .omitted)
            let subH = drawText("\(userName)  ·  Exported \(dateStr)", font: captionFont, color: mutedColor)
            y += subH + 12

            drawRule(color: accentColor.withAlphaComponent(0.5))
            y += 14

            let sumTH = drawText("SUMMARY", font: sectionFont)
            y += sumTH + 8

            let completedDoses = entries.filter(\.completed).count
            let compliancePct  = entries.isEmpty ? 0 : Int(Double(completedDoses) / Double(entries.count) * 100)
            let activeCount    = protocols.filter { $0.status == .active }.count

            for (label, value) in [
                ("Active Protocols", "\(activeCount) of \(protocols.count)"),
                ("Doses Logged", "\(completedDoses) of \(entries.count)"),
                ("Overall Compliance", "\(compliancePct)%"),
            ] {
                let h = drawText(label, font: bodyFont, color: mutedColor)
                drawText(value, font: labelFont, x: pageWidth - margin - 60, width: 60, align: .right)
                y += h + 5
            }

            y += 12
            drawRule()
            y += 14

            // MARK: Per-protocol sections

            for proto in protocols {
                let protoEntries = entries
                    .filter { $0.protocolId == proto.id }
                    .sorted { $0.date > $1.date }
                let done = protoEntries.filter(\.completed).count
                let pct  = protoEntries.isEmpty ? 0
                    : Int(Double(done) / Double(protoEntries.count) * 100)

                checkPageBreak(for: 80)

                // Protocol header
                let proH = drawText(proto.name, font: sectionFont)
                drawText(proto.status.rawValue.capitalized, font: captionFont,
                         color: mutedColor, x: pageWidth - margin - 60, width: 60, align: .right)
                y += proH + 3

                let startStr   = proto.startDate.formatted(date: .abbreviated, time: .omitted)
                let peptideStr = proto.peptides.map(\.abbreviation).joined(separator: ", ")
                let metaH = drawText(
                    "Started \(startStr)  ·  \(proto.cycleLengthWeeks)w cycle  ·  \(pct)% compliance",
                    font: captionFont, color: mutedColor
                )
                y += metaH + 2
                let pepH = drawText(peptideStr, font: captionFont, color: mutedColor)
                y += pepH + 8

                // Monthly summary block — always present, lossless.
                // Drawn before the per-entry table so users skimming
                // the PDF for trends don't need to scroll through
                // hundreds of rows. Months with zero activity are
                // suppressed.
                let monthlyBuckets = Self.monthlyBuckets(for: protoEntries)
                if !monthlyBuckets.isEmpty {
                    let summaryHeaderH = drawText("MONTHLY SUMMARY",
                        font: labelFont, color: mutedColor)
                    y += summaryHeaderH + 3
                    drawRule()
                    y += 5
                    for bucket in monthlyBuckets {
                        checkPageBreak(for: 18)
                        let lineH = drawText(
                            "\(bucket.label)  ·  \(bucket.logged) logged · \(bucket.missed) missed · \(bucket.compliancePct)% compliance",
                            font: captionFont
                        )
                        y += lineH + 3
                    }
                    y += 6
                }

                guard !protoEntries.isEmpty else {
                    let emptyH = drawText("No entries recorded.", font: captionFont, color: mutedColor)
                    y += emptyH + 10
                    drawRule()
                    y += 14
                    continue
                }

                // Table header row
                drawRule()
                y += 4
                var hdrH: CGFloat = 0
                for (text, x, width) in [
                    ("DATE", cDate, 68.0),
                    ("PEPTIDE", cPep, 110.0),
                    ("DOSE", cDose, 75.0),
                    ("TIME", cTime, 70.0),
                    ("SITE", cSite, 95.0),
                    ("DONE", cDone, 40.0),
                ] {
                    hdrH = max(hdrH, drawText(text, font: labelFont, color: mutedColor, x: x, width: width))
                }
                y += hdrH + 3
                drawRule()
                y += 5

                // Entry rows. Two modes based on volume:
                //   - ≤ Self.pdfFullDetailLimit (90): paginate every
                //     entry. Multi-page output but lossless.
                //   - > limit: show only the 30 most-recent and
                //     cross-reference the CSV export for the rest.
                // The prior implementation hard-capped at 60 with no
                // monthly summary and no CSV pointer, which silently
                // dropped data for any daily-dosing user past two
                // months of history.
                let entriesToRender = protoEntries.count <= Self.pdfFullDetailLimit
                    ? Array(protoEntries)
                    : Array(protoEntries.prefix(Self.pdfRecentEntryLimit))

                for entry in entriesToRender {
                    let dateVal = entry.date.formatted(date: .abbreviated, time: .omitted)
                    let timeVal = (entry.actualTime ?? entry.date).formatted(.dateTime.hour().minute())
                    let doseVal = entry.actualDose ?? entry.dose
                    let siteVal = entry.injectionSite ?? "—"
                    let doneVal = entry.completed ? "Yes" : "No"

                    let rowH = [
                        measureText(dateVal, font: bodyFont, width: 68),
                        measureText(entry.peptide.abbreviation, font: bodyFont, width: 110),
                        measureText(doseVal, font: bodyFont, width: 75),
                        measureText(timeVal, font: bodyFont, width: 70),
                        measureText(siteVal, font: bodyFont, width: 95),
                        measureText(doneVal, font: bodyFont, width: 40),
                    ].max() ?? 14
                    checkPageBreak(for: rowH + 3)

                    for (text, x, width) in [
                        (dateVal, cDate, 68.0),
                        (entry.peptide.abbreviation, cPep, 110.0),
                        (doseVal, cDose, 75.0),
                        (timeVal, cTime, 70.0),
                        (siteVal, cSite, 95.0),
                    ] {
                        drawText(text, font: bodyFont, x: x, width: width)
                    }
                    let doneColor: UIColor = entry.completed ? greenColor : redColor
                    drawText(doneVal, font: bodyFont, color: doneColor, x: cDone, width: 40)
                    y += rowH + 3
                }

                if protoEntries.count > entriesToRender.count {
                    let hidden = protoEntries.count - entriesToRender.count
                    let moreH = drawText(
                        "… \(hidden) earlier entries · use the CSV export in Profile → Export Data for the complete log",
                        font: captionFont, color: mutedColor
                    )
                    y += moreH + 3
                }

                y += 10
                drawRule()
                y += 14
            }

            // Footer
            y = pageHeight - margin + 6
            drawText(
                "Generated by Atlas  ·  \(Date().formatted(date: .abbreviated, time: .shortened))",
                font: captionFont, color: mutedColor, align: .center
            )
        }

        guard !data.isEmpty else {
            AppLog.export.error("exportPDF produced empty data")
            throw ExportError.pdfGenerationFailed
        }
        return data
    }

    // MARK: - File URLs

    /// Strips path separators from a caller-supplied filename so a
    /// future code path can't pass `"../../Library/Preferences/..."`
    /// and write outside the temp directory. All current callers use
    /// safe literals, but the API was wide enough to be a latent
    /// path-traversal surface.
    private static func safeFilename(_ filename: String) -> String {
        let cleaned = (filename as NSString).lastPathComponent
        return cleaned.isEmpty ? "atlas-export" : cleaned
    }

    func writeCSV(_ content: String, filename: String) -> URL? {
        let safe = Self.safeFilename(filename)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            AppLog.export.error("writeCSV \(safe, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func writeJSON(_ data: Data, filename: String) -> URL? {
        let safe = Self.safeFilename(filename)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.export.error("writeJSON \(safe, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func writePDF(_ data: Data, filename: String) -> URL? {
        let safe = Self.safeFilename(filename)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.export.error("writePDF \(safe, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func csvQuote(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

struct AppBackup: Codable, Sendable {
    let exportDate: Date
    let version: String
    let protocols: [PeptideProtocol]
    let entries: [ProtocolEntry]
    let profile: UserProfile
}

enum ExportError: Error, LocalizedError {
    case pdfGenerationFailed

    var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed: "PDF report could not be generated."
        }
    }
}
