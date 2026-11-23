import SwiftUI

/// Today's greeting, on one line beside the Log pill. The profile entry
/// lives in the navigation bar, as on every other tab, and the date sits
/// in `TodayDayRow` right below.
struct WelcomeHeader: View {
    let greeting: String
    let name: String
    /// Today's quick-log button, shown trailing the greeting when set.
    var logButton: TodayLogButton? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            // At accessibility sizes the pill takes its own row above the
            // greeting; beside it it squeezed the text to a few letters a
            // line and pushed the header past both screen edges.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let logButton {
                        HStack {
                            Spacer(minLength: 0)
                            logButton
                        }
                    }
                    greetingText
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.md) {
                    greetingText
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if let logButton { logButton }
                }
            }
        }
    }

    /// Both halves are already localized; only the comma joins them.
    private var greetingText: some View {
        Text(verbatim: displayName.isEmpty ? greeting : "\(greeting), \(displayName)")
            .font(AppFont.title)
            .foregroundStyle(AppColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
            // Past AX2 the name broke mid-word a few letters a line; the
            // page title stops growing where the rest of the text keeps on.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

#Preview("With Name") {
    WelcomeHeader(
        greeting: "Good evening",
        name: "Alex",
        logButton: TodayLogButton(isOpen: false, includesDose: false, action: {})
    )
    .padding(Spacing.screenPadding)
    .background(AppColor.background)
}

#Preview("No Name") {
    WelcomeHeader(greeting: "Good evening", name: "")
        .padding(Spacing.screenPadding)
        .background(AppColor.background)
}
