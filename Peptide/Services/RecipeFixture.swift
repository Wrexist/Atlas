#if DEBUG
import Foundation

/// Screenshot runs only: `--recipe-fixture <id>` opens that recipe on the
/// Meals tab, so a capture lands on the recipe without scrolling the tab
/// for its shelf.
enum RecipeFixture {
    static var recipe: LibraryRecipe? {
        let arguments = ProcessInfo.processInfo.arguments
        guard UserDefaults.standard.bool(forKey: "com.peptidesai.app.screenshotMode.enabled"),
              let flag = arguments.firstIndex(of: "--recipe-fixture"),
              arguments.indices.contains(flag + 1) else { return nil }
        let id = arguments[flag + 1]
        return RecipeLibraryEngine.bundled.first { $0.id == id }
    }
}
#endif
