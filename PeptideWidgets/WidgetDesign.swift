import WidgetKit
import SwiftUI
import UIKit
import OSLog

/// Deep-link targets for widget taps, routed by the app's
/// `DeepLinkRouter`. Before these, every home-screen widget tap just
/// foregrounded the app on whatever tab was last open — a nutrition
/// widget tap could land on Biology. `widgetURL` needs no
/// CFBundleURLTypes registration for same-app links, but the scheme
/// is registered anyway so notification and Shortcuts links resolve.
enum WidgetDeepLink {
    static let today = URL(string: "peptidex://today")
    static let meals = URL(string: "peptidex://meals")
    static let train = URL(string: "peptidex://train")
}

// MARK: - Palette

/// Colour tokens for the widget extension. The extension can't import the
/// app module, so the brand values it needs are reproduced here once, each
/// next to the `AppColor` token it mirrors, instead of per widget.
///
/// Every value is a light/dark pair, like the app's: a widget follows the
/// home screen's appearance, not the app's Display setting.
enum WidgetPalette {
    /// `AppColor.accentPrimary`: the theme accent the phone stored in the
    /// App Group, emerald until it has. Read per render so a theme change
    /// reaches the next timeline without restarting the extension.
    static var accent: Color {
        let stored = ThemeAccent.stored()
        return dynamic(light: stored.light, dark: stored.dark)
    }
    /// `AppColor.macroCalories` — a data colour, so it stays emerald under
    /// every theme, like the app's calorie ring.
    static let calories = dynamic(light: 0x077A55, dark: WatchPalette.calories)
    /// `AppColor.macroWater` — the same blue the Watch uses for training.
    static let training = dynamic(light: 0x1F6FC0, dark: WatchPalette.training)
    /// `WatchPalette.protocolDose`, darkened in light mode for contrast.
    static let protocolDose = dynamic(light: 0x6D4FD1, dark: WatchPalette.protocolDose)
    /// `AppColor.positive`.
    static let done = dynamic(light: 0x23784A, dark: 0x66C78C)
    /// `AppColor.warning`.
    static let over = dynamic(light: 0x9A6B00, dark: 0xFFB800)

    /// `AppColor.macroProtein`, `.macroCarbs`, `.macroFat`.
    static let protein = dynamic(light: 0x955B07, dark: WatchPalette.protein)
    static let carbs = dynamic(light: 0x6D4FC2, dark: 0xA78BFA)
    static let fat = dynamic(light: 0x9E4055, dark: 0xE8899F)

    /// `AppColor.mealBreakfast`, `.mealLunch`, `.mealDinner`, `.mealSnack`.
    /// Darkened in light mode: the dark-mode yellow is unreadable on white.
    static let breakfast = dynamic(light: 0xB85A12, dark: 0xFF9E4D)
    static let lunch = dynamic(light: 0x7F6110, dark: 0xFAC733)
    static let dinner = dynamic(light: 0x5A5FCF, dark: 0x7A80EB)
    static let snack = dynamic(light: 0x2A7A47, dark: 0x5CC78C)

    /// Track behind a ring or bar fill.
    static let track = Color.primary.opacity(0.10)

    /// The raised finish the app's rings carry (`AppColor.ringSheen`,
    /// `.ringShade`, `.ringCrest`, `.ringGroove`, `.ringGrooveLip`, and
    /// `AppShadow.ringRaise`'s ink). On a near-black card a shadow barely
    /// shows, so dark-mode depth comes mostly from the light.
    static let sheen = Color.white.opacity(0.2)
    static let shade = adaptive(light: .black.opacity(0.08), dark: .black.opacity(0.26))
    static let crest = adaptive(light: .white.opacity(0.12), dark: .white.opacity(0.24))
    static let groove = adaptive(light: .black.opacity(0.12), dark: .black.opacity(0.55))
    static let grooveLip = adaptive(light: .white.opacity(0.7), dark: .white.opacity(0.16))
    static let raise = adaptive(light: .black.opacity(0.14), dark: .black.opacity(0.6))

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
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
    /// A styled trailing figure, used instead of `trailing` when part of
    /// it needs to stand out.
    var trailingText: Text?

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
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if let trailing = trailingText ?? trailing.map({ Text($0) }) {
                trailing
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(trailingAccessibilityLabel ?? trailing)
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
/// flattening to one tone. In full colour it carries the app's raised
/// finish: a groove for the track and a lit arc standing out of it.
struct WidgetRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        let fill = min(max(progress, 0), 1)
        ZStack {
            RingGroove(lineWidth: lineWidth)
            RaisedArc(progress: fill, lineWidth: lineWidth) {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: fill)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

/// A ring's track, sunk into the card: a shadow under its upper wall and
/// a faint lit lower lip (`RaisedRingFinish.groove`). Strokes inside the
/// frame, so the ring's outer edge is the frame's edge.
struct RingGroove: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let lineWidth: CGFloat

    var body: some View {
        let track = Circle().inset(by: lineWidth / 2)
        if renderingMode == .fullColor {
            track.stroke(
                WidgetPalette.track
                    .shadow(.inner(color: WidgetPalette.groove, radius: lineWidth * 0.12, y: lineWidth * 0.14))
                    .shadow(.inner(color: WidgetPalette.grooveLip, radius: lineWidth * 0.06, y: -lineWidth * 0.06)),
                lineWidth: lineWidth
            )
        } else {
            track.stroke(WidgetPalette.track, lineWidth: lineWidth)
        }
    }
}

/// An arc from 12 o'clock to `progress`, lifted off its groove the way
/// the app's `RaisedRingFinish` lifts a ring: a drop shadow, a sheen that
/// is lit top-left and shaded bottom-right, and a soft crest along the
/// tube. `arc` draws the colour; the finish is laid over the whole arc so
/// meal segments get one continuous light. Tinted and clear home screens
/// flatten colour anyway, so there the arc is drawn plain.
struct RaisedArc<Arc: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let progress: Double
    let lineWidth: CGFloat
    @ViewBuilder let arc: Arc

    /// Keeps the crest off the caps, so it reads as light on a rounded
    /// tube rather than a painted stripe.
    private static let crestInset = 0.03

    var body: some View {
        if renderingMode == .fullColor, progress > 0 {
            ZStack {
                arc.shadow(color: WidgetPalette.raise, radius: lineWidth * 0.35, y: lineWidth * 0.18)
                LinearGradient(
                    colors: [WidgetPalette.sheen, .clear, WidgetPalette.shade],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .mask { arc }
                LinearGradient(
                    colors: [WidgetPalette.crest, .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .mask { crest }
            }
            .widgetAccentable()
        } else {
            arc.widgetAccentable()
        }
    }

    private var crest: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: Self.crestInset, to: max(Self.crestInset, progress - Self.crestInset))
            .stroke(style: StrokeStyle(lineWidth: lineWidth * 0.22, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .blur(radius: lineWidth * 0.08)
    }
}

extension View {
    /// Centres `label` over a ring in the largest 4:3 box that fits its
    /// hole: the box's corners touch the ring's inner edge, so a figure
    /// scaled to fit the box can't reach the stroke. Padding the label by
    /// a fixed amount instead left the full ring width minus a few points,
    /// wider than the hole, and "1 279" ran over the ring. The ring's
    /// frame must be its outer edge. Dynamic Type is capped because the
    /// ring itself doesn't grow: past it the label only shrinks back.
    func ringLabel<Center: View>(lineWidth: CGFloat, @ViewBuilder _ label: () -> Center) -> some View {
        let content = label()
        return overlay {
            GeometryReader { proxy in
                let hole = max(0, min(proxy.size.width, proxy.size.height) - 2 * lineWidth)
                content
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .frame(width: hole * 0.8, height: hole * 0.6)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }

    /// A small round chip raised off the card: lit from above, shaded
    /// below, with a bright upper rim and a soft shadow. Plain in tinted
    /// and clear modes, where the system recolours it anyway.
    func raisedDisc(_ fill: Color) -> some View {
        modifier(RaisedDisc(fill: fill))
    }
}

private struct RaisedDisc: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let fill: Color

    func body(content: Content) -> some View {
        content.background {
            if renderingMode == .fullColor {
                Circle()
                    .fill(fill)
                    .overlay {
                        Circle().fill(LinearGradient(
                            colors: [WidgetPalette.sheen.opacity(0.6), .clear, WidgetPalette.shade],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    }
                    .overlay {
                        Circle().strokeBorder(
                            LinearGradient(colors: [WidgetPalette.crest, .clear], startPoint: .top, endPoint: .center),
                            lineWidth: 0.75
                        )
                    }
                    .shadow(color: WidgetPalette.raise.opacity(0.5), radius: 2, y: 1)
            } else {
                Circle().fill(fill)
            }
        }
    }
}

/// Thin horizontal bar; the macro rows and the dose pips use it. With
/// `showsOverflow`, a fill past the target keeps the bar full and draws
/// the part beyond the target in a deeper shade of the same colour, the
/// way the app's rings run a second lap instead of borrowing another
/// metric's colour.
struct WidgetBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let progress: Double
    let tint: Color
    var height: CGFloat = 4
    var showsOverflow = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                track
                if progress > 0 {
                    fill(width: width * min(progress, 1))
                }
                if showsOverflow, progress > 1 {
                    // The target sits where 1 / progress of the bar is.
                    let excess = width * (1 - 1 / progress)
                    Capsule()
                        .fill(tint.mix(with: .black, by: 0.35))
                        .frame(width: max(excess, height))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private var track: some View {
        if renderingMode == .fullColor {
            Capsule().fill(
                WidgetPalette.track
                    .shadow(.inner(color: WidgetPalette.groove, radius: height * 0.2, y: height * 0.2))
            )
        } else {
            Capsule().fill(WidgetPalette.track)
        }
    }

    private func fill(width: CGFloat) -> some View {
        Capsule()
            .fill(tint)
            .overlay {
                if renderingMode == .fullColor {
                    Capsule().fill(LinearGradient(
                        colors: [WidgetPalette.sheen, .clear, WidgetPalette.shade],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
            }
            .frame(width: max(width, height))
            .shadow(color: renderingMode == .fullColor ? WidgetPalette.raise.opacity(0.5) : .clear, radius: 1, y: 0.5)
            .widgetAccentable()
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
