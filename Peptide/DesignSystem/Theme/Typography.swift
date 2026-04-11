import SwiftUI

enum AppFont {
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .semibold)
    static let title3 = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17, weight: .regular)
    static let callout = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let footnote = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)

    static let statValue = Font.system(size: 48, weight: .bold, design: .rounded)
    static let statValueSmall = Font.system(size: 32, weight: .bold, design: .rounded)
    static let scoreLarge = Font.system(size: 64, weight: .bold, design: .rounded)
}
