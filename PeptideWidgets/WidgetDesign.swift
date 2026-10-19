import WidgetKit
import SwiftUI
import UIKit

// MARK: - Palette

/// Colour tokens for the widget extension. The extension can't import the
/// app module, so the brand values it needs are reproduced here once, each
/// next to the `AppColor` token it mirrors, instead of per widget.
///
/// Every value is a light/dark pair, like the app's: a widget follows the
/// home screen's appearance, not the app's Display setting.
enum WidgetPalette {
    /// `AppTheme.teal.primary`, the default brand emerald.
    static let brand = dynamic(light: 0x077A55, dark: 0x10B981)
    /// `AppColor.macroWater` — the same blue the Watch uses for training.
    static let training = dynamic(light: 0x1F6FC0, dark: 0x378ADD)
    /// `WatchPalette.protocolDose`, darkened in light mode for contrast.
    static let protocolDose = dynamic(light: 0x6D4FD1, dark: 0xA78BFA)
    /// `AppColor.positive`.
    static let done = dynamic(light: 0x2F8F5B, dark: 0x66C78C)
    /// `AppColor.warning`.
    static let over = dynamic(light: 0x9A6B00, dark: 0xFFB800)

    /// `AppColor.macroProtein`, `.macroCarbs`, `.macroFat`.
    static let protein = dynamic(light: 0xB56F0B, dark: 0xEF9F27)
    static let carbs = dynamic(light: 0x2A6F55, dark: 0x5FD3A0)
    static let fat = dynamic(light: 0x9E4055, dark: 0xE8899F)

    /// Track behind a ring or bar fill.
    static let track = Color.primary.opacity(0.10)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The four meal buckets, in the order `WidgetSnapshotBuilder` writes them.
/// Matched by position rather than by name because the names arrive
/// localised. Glyphs and tints mirror `MealCategory.icon` / `.tint`, which
/// also colour the segments of the app's calorie ring.
enum WidgetMeal: Int, CaseIterable {
    case breakfast, lunch, dinner, snack

    var glyph: String {
        switch self {
        case .breakfast: "sun.horizon.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .breakfast: Color(red: 1.0, green: 0.62, blue: 0.30)
        case .lunch: Color(red: 0.98, green: 0.78, blue: 0.20)
        case .dinner: Color(red: 0.48, green: 0.50, blue: 0.92)
        case .snack: Color(red: 0.36, green: 0.78, blue: 0.55)
        }
    }
}

// MARK: - Data

/// Reads the payload the app writes to the App Group container. One
/// loader for every widget, so a schema or path change is one edit.
enum WidgetStore {
    static func load() -> WidgetData? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("widget-data.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetData.self, from: data)
    }

    /// The next reload: in fifteen minutes, or at midnight if that comes
    /// first, so a new day never inherits yesterday's totals.
    static func nextRefresh(after now: Date, minutes: Int = 15) -> Date {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        )
        let soon = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now
        return min(soon, midnight)
    }
}

enum WidgetFormat {
    /// "58m", "1h 12m".
    static func duration(minutes: Int) -> String {
        Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// "4,320 kg", or "12.5K kg" once the full number stops fitting a
    /// widget column.
    static func volume(_ value: Double, suffix: String) -> String {
        let number = value >= 10_000
            ? value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
            : Int(value.rounded()).formatted()
        return "\(number) \(suffix)"
    }
}

// MARK: - Chrome

/// The row every home-screen widget opens with: a tinted glyph and an
/// uppercase caption, with an optional trailing figure. One header means
/// a stack of Atlas widgets reads as one family.
struct WidgetHeader: View {
    let glyph: String
    let title: LocalizedStringKey
    let tint: Color
    var trailing: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Plain system background with a faint wash of the widget's own colour
/// from the top corner, so each widget is recognisable at a glance
/// without a gradient fill on the content. The system removes container
/// backgrounds in tinted and clear modes, so this costs those modes
/// nothing.
struct WidgetBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [tint.opacity(0.14), tint.opacity(0)],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
    }
}

extension View {
    func widgetBackdrop(_ tint: Color) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { WidgetBackdrop(tint: tint) }
    }

    /// Lock-screen families draw on the system's own material.
    func accessoryBackdrop() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Progress

/// A progress ring. The arc is accentable and the track isn't, so in a
/// tinted home screen the two still read as filled and empty instead of
/// flattening to one tone.
struct WidgetRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(WidgetPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        // Strokes straddle the path; keep the whole ring inside the frame.
        .padding(lineWidth / 2)
    }
}

/// Thin horizontal bar; the macro rows and the dose pips use it.
struct WidgetBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}
