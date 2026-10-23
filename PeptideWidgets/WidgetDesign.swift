import WidgetKit
import SwiftUI
import UIKit
import OSLog

// MARK: - Palette

/// Colour tokens for the widget extension. The extension can't import the
/// app module, so the brand values it needs are reproduced here once, each
/// next to the `AppColor` token it mirrors, instead of per widget.
///
/// Every value is a light/dark pair, like the app's: a widget follows the
/// home screen's appearance, not the app's Display setting.
enum WidgetPalette {
    /// `AppTheme.teal.primary`, the default brand emerald.
    static let brand = dynamic(light: 0x077A55, dark: WatchPalette.calories)
    /// `AppColor.macroWater` — the same blue the Watch uses for training.
    static let training = dynamic(light: 0x1F6FC0, dark: WatchPalette.training)
    /// `WatchPalette.protocolDose`, darkened in light mode for contrast.
    static let protocolDose = dynamic(light: 0x6D4FD1, dark: WatchPalette.protocolDose)
    /// `AppColor.positive`.
    static let done = dynamic(light: 0x2F8F5B, dark: 0x66C78C)
    /// `AppColor.warning`.
    static let over = dynamic(light: 0x9A6B00, dark: 0xFFB800)

    /// `AppColor.macroProtein`, `.macroCarbs`, `.macroFat`.
    static let protein = dynamic(light: 0xB56F0B, dark: WatchPalette.protein)
    static let carbs = dynamic(light: 0x2A6F55, dark: 0x5FD3A0)
    static let fat = dynamic(light: 0x9E4055, dark: 0xE8899F)

    /// `AppColor.mealBreakfast`, `.mealLunch`, `.mealDinner`, `.mealSnack`.
    /// Darkened in light mode: the dark-mode yellow is unreadable on white.
    static let breakfast = dynamic(light: 0xB85A12, dark: 0xFF9E4D)
    static let lunch = dynamic(light: 0x9C7714, dark: 0xFAC733)
    static let dinner = dynamic(light: 0x5A5FCF, dark: 0x7A80EB)
    static let snack = dynamic(light: 0x2A7A47, dark: 0x5CC78C)

    /// Track behind a ring or bar fill.
    static let track = Color.primary.opacity(0.10)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Dark value taken from `WatchPalette` where the wrist already
    /// defines the same colour, so the hex lives in one place.
    private static func dynamic(light: UInt32, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(hex: light)
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
        case .breakfast: WidgetPalette.breakfast
        case .lunch: WidgetPalette.lunch
        case .dinner: WidgetPalette.dinner
        case .snack: WidgetPalette.snack
        }
    }
}

// MARK: - Data

/// What `WidgetStore.load` found. A file that exists but can't be read
/// is kept apart from no file at all: before the first unlock after a
/// reboot the payload is still encrypted, and showing the empty state
/// then would tell the user they have no protocol, meals or workouts.
enum WidgetPayload {
    case loaded(WidgetData)
    /// The app hasn't written one yet: the empty state is the truth.
    case missing
    /// Still protected, or no longer decodes.
    case unreadable
}

/// Reads the payload the app writes to the App Group container. One
/// loader for every widget, so a schema or path change is one edit.
enum WidgetStore {
    /// How soon a widget that couldn't read the payload tries again —
    /// soon enough to recover shortly after the device is unlocked.
    static let unreadableRetryMinutes = 5

    private static let log = Logger(subsystem: "com.peptidesai.app", category: "WidgetStore")

    static func load() -> WidgetPayload {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("widget-data.json") else {
            log.error("App Group container unavailable; widget payload unreadable")
            return .unreadable
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .loaded(try decoder.decode(WidgetData.self, from: data))
        } catch {
            log.error("widget payload unreadable: \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
    }
}

extension WidgetPayload {
    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// When a timeline built from this payload should reload: soon after
    /// a failed read, so the widget recovers once the device unlocks;
    /// otherwise on the usual schedule.
    func reloadDate(after now: Date, minutes: Int = 15) -> Date {
        if case .unreadable = self {
            return now.addingTimeInterval(TimeInterval(WidgetStore.unreadableRetryMinutes * 60))
        }
        return WidgetData.nextRefresh(after: now, minutes: minutes)
    }
}

enum WidgetFormat {
    /// "58m", "1h 12m".
    static func duration(minutes: Int) -> String {
        format(minutes: minutes, width: .narrow)
    }

    /// "58 minutes", "1 hour, 12 minutes" — the narrow form can be read
    /// aloud as "58 meters".
    static func spokenDuration(minutes: Int) -> String {
        format(minutes: minutes, width: .wide)
    }

    private static func format(minutes: Int, width: Duration.UnitsFormatStyle.UnitWidth) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: width))
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
    /// The trailing figure as it should be spoken: "2/4" reads as "two
    /// slash four".
    var trailingAccessibilityLabel: Text?

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
                    .accessibilityLabel(trailingAccessibilityLabel ?? Text(trailing))
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

// MARK: - Colour helpers

/// Black or white, whichever reads better on `fill`. Vial tints run from
/// deep to pale, and the late and resting amber is light, so a fixed
/// white label fails contrast on some of the fills a Live Activity button
/// takes. The palette colours are light/dark pairs, so `fill` is resolved
/// against the scheme the view draws in, not whatever trait collection is
/// current.
func labelColor(on fill: Color, in colorScheme: ColorScheme) -> Color {
    let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard UIColor(fill).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
    func linear(_ channel: CGFloat) -> Double {
        let c = Double(channel)
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    // Above this, black text out-contrasts white (WCAG relative luminance).
    return luminance > 0.179 ? .black : .white
}
