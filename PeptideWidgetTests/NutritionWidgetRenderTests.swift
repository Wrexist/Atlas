import XCTest
import SwiftUI
import WidgetKit

/// Renders the nutrition widget's home-screen layouts to images so a
/// layout change can be reviewed without a device: the medium widget
/// from the screenshot that showed "1 279" running over the ring, the
/// figures that stress it hardest, and both appearances. The images are
/// kept on success; the screenshots workflow exports them.
@MainActor
final class NutritionWidgetRenderTests: XCTestCase {
    private static let mediumSize = CGSize(width: 338, height: 158)
    private static let smallSize = CGSize(width: 158, height: 158)

    func test_mediumWidget_rendersEveryStressCase() throws {
        for (name, entry) in Self.cases {
            for scheme in [ColorScheme.dark, .light] {
                let image = try render(MediumNutritionView(entry: entry), size: Self.mediumSize, scheme: scheme)
                attach(image, name: "widget-medium-\(name)-\(scheme == .dark ? "dark" : "light")")
            }
        }
    }

    func test_smallWidget_rendersEveryStressCase() throws {
        for (name, entry) in Self.cases {
            let image = try render(SmallNutritionView(entry: entry), size: Self.smallSize, scheme: .dark)
            attach(image, name: "widget-small-\(name)-dark")
        }
    }

    func test_mediumWidget_atLargestTextSize_stillRenders() throws {
        let image = try render(
            MediumNutritionView(entry: Self.cases[0].1)
                .environment(\.dynamicTypeSize, .accessibility5),
            size: Self.mediumSize,
            scheme: .dark
        )
        attach(image, name: "widget-medium-ax5-dark")
    }

    // MARK: - Cases

    /// The first case is the reported screenshot: 1 296 of 2 575 kcal, lunch
    /// only, fat past its target.
    private static let cases: [(String, NutritionEntry)] = [
        ("screenshot", makeEntry(calories: 1296, target: 2575, protein: (68, 175), carbs: (62, 300), fat: (86, 75), meals: [0, 1296, 0, 0])),
        ("all-meals", makeEntry(calories: 2380, target: 2575, protein: (182, 175), carbs: (240, 300), fat: (70, 75), meals: [520, 840, 760, 260])),
        ("over-target", makeEntry(calories: 3120, target: 2575, protein: (190, 175), carbs: (360, 300), fat: (110, 75), meals: [640, 1040, 1180, 260])),
        ("huge-figures", makeEntry(calories: 1200, target: 13500, protein: (1888, 1999), carbs: (2888, 2999), fat: (888, 999), meals: [0, 0, 1200, 0])),
        ("empty-day", makeEntry(calories: 0, target: 2575, protein: (0, 175), carbs: (0, 300), fat: (0, 75), meals: [0, 0, 0, 0])),
        ("no-target", makeEntry(calories: 1850, target: 0, protein: (120, 0), carbs: (180, 0), fat: (60, 0), meals: [400, 900, 550, 0])),
    ]

    // MARK: - Rendering

    /// WidgetKit isn't running, so its frame, 16pt content margins and
    /// container background are drawn here by hand.
    private func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme) throws -> UIImage {
        let widget = view
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetBackdrop(tint: WidgetPalette.accent))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(12)
            .background(scheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: widget)
        renderer.scale = 3
        return try XCTUnwrap(renderer.uiImage, "the widget rendered nothing")
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Fixtures

private func makeMeals(_ calories: [Int]) -> [WidgetMealSlot] {
    zip(["Breakfast", "Lunch", "Dinner", "Snack"], calories).map {
        WidgetMealSlot(category: $0, calories: $1, entryCount: $1 > 0 ? 1 : 0)
    }
}

private func makeEntry(
    calories: Int, target: Int,
    protein: (Int, Int), carbs: (Int, Int), fat: (Int, Int),
    meals: [Int]
) -> NutritionEntry {
    NutritionEntry(
        date: .now, calories: calories, target: target,
        protein: protein.0, carbs: carbs.0, fat: fat.0,
        proteinTarget: protein.1, carbsTarget: carbs.1, fatTarget: fat.1,
        meals: makeMeals(meals)
    )
}
