import Foundation
import UIKit

@MainActor
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

    // MARK: - PDF Export

    func exportPDF(protocols: [PeptideProtocol], entries: [ProtocolEntry], profile: UserProfile) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "PeptideX Protocol Report",
            kCGPDFContextAuthor as String: "PeptideX",
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        // Drawing is extracted to a separate method so the pdfData closure
        // only captures Sendable value types, avoiding Swift 6 @Sendable errors.
        return renderer.pdfData { [protocols, entries, profile, pageWidth, pageHeight, margin, contentWidth] ctx in
            drawPDFContent(
                ctx: ctx,
                protocols: protocols, entries: entries, profile: profile,
                pageWidth: pageWidth, pageHeight: pageHeight,
                margin: margin, contentWidth: contentWidth
            )
        }
    }

    // swiftlint:disable:next function_body_length
    private func drawPDFContent(
        ctx: UIGraphicsPDFRendererContext,
        protocols: [PeptideProtocol],
        entries: [ProtocolEntry],
        profile: UserProfile,
        pageWidth: CGFloat,
        pageHeight: CGFloat,
        margin: CGFloat,
        contentWidth: CGFloat
    ) {
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
        let cPep:  CGFloat = margin + 72
        let cDose: CGFloat = margin + 187
        let cTime: CGFloat = margin + 267
        let cSite: CGFloat = margin + 342
        let cDone: CGFloat = margin + 442

        // MARK: Page 1 — header + summary

        startPage()

        let titleH = drawText("PeptideX Protocol Report", font: titleFont, color: accentColor)
        y += titleH + 4

        let userName = profile.name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "PeptideX User" : profile.name
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
            ("Active Protocols",  "\(activeCount) of \(protocols.count)"),
            ("Doses Logged",      "\(completedDoses) of \(entries.count)"),
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
                ("DATE",    cDate, 68.0),
                ("PEPTIDE", cPep,  110.0),
                ("DOSE",    cDose, 75.0),
                ("TIME",    cTime, 70.0),
                ("SITE",    cSite, 95.0),
                ("DONE",    cDone, 40.0),
            ] {
                hdrH = max(hdrH, drawText(text, font: labelFont, color: mutedColor, x: x, width: width))
            }
            y += hdrH + 3
            drawRule()
            y += 5

            // Entry rows
            for entry in protoEntries.prefix(60) {
                checkPageBreak(for: 14)

                let dateVal = entry.date.formatted(date: .abbreviated, time: .omitted)
                let timeVal = (entry.actualTime ?? entry.date).formatted(.dateTime.hour().minute())
                let doseVal = entry.actualDose ?? entry.dose
                let siteVal = entry.injectionSite ?? "—"

                var rowH: CGFloat = 0
                for (text, x, width) in [
                    (dateVal,                    cDate, 68.0),
                    (entry.peptide.abbreviation, cPep,  110.0),
                    (doseVal,                    cDose, 75.0),
                    (timeVal,                    cTime, 70.0),
                    (siteVal,                    cSite, 95.0),
                ] {
                    rowH = max(rowH, drawText(text, font: bodyFont, x: x, width: width))
                }
                let doneColor: UIColor = entry.completed ? greenColor : redColor
                drawText(entry.completed ? "Yes" : "No",
                         font: bodyFont, color: doneColor, x: cDone, width: 40)
                y += rowH + 3
            }

            if protoEntries.count > 60 {
                let moreH = drawText(
                    "… \(protoEntries.count - 60) earlier entries not shown",
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
            "Generated by PeptideX  ·  \(Date().formatted(date: .abbreviated, time: .shortened))",
            font: captionFont, color: mutedColor, align: .center
        )
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

    func writePDF(_ data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
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

struct AppBackup: Codable {
    let exportDate: Date
    let version: String
    let protocols: [PeptideProtocol]
    let entries: [ProtocolEntry]
    let profile: UserProfile
}
