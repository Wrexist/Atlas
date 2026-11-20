import SwiftUI

/// Today's greeting. The profile entry lives in the navigation bar, as on
/// every other tab, so the header's only control is the Log pill.
struct WelcomeHeader: View {
    let greeting: String
    let name: String
    let date: String
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
                    greetingStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.md) {
                    greetingStack
                    Spacer(minLength: 0)
                    if let logButton { logButton }
                }
            }
        }
    }

    private var greetingStack: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if displayName.isEmpty {
                Text(greeting)
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.textPrimary)
            } else {
                // Beside the pill the comma leads into the name; on a line
                // of its own at accessibility sizes it just dangles.
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(greeting)
                    } else {
                        Text("\(greeting),")
                    }
                }
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)

                Text(displayName)
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.textPrimary)
            }

            Text(date)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        // Past AX2 a large-title name broke mid-word a few letters a line;
        // the page title stops growing where the rest of the text keeps on.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

#Preview("With Name") {
    WelcomeHeader(
        greeting: "Good evening",
        name: "Alex",
        date: "Thursday, April 10",
        logButton: TodayLogButton(isOpen: false, includesDose: false, action: {})
    )
    .padding(Spacing.screenPadding)
    .background(AppColor.background)
}

#Preview("No Name") {
    WelcomeHeader(greeting: "Good evening", name: "", date: "Thursday, April 10")
        .padding(Spacing.screenPadding)
        .background(AppColor.background)
}
