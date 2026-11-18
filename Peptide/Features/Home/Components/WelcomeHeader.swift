import SwiftUI

struct WelcomeHeader: View {
    let greeting: String
    let name: String
    let date: String
    var avatarImageData: Data? = nil
    var onAvatarTap: (() -> Void)? = nil
    /// Today's quick-log button, shown left of the avatar when set.
    var logButton: TodayLogButton? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The Log pill's height at the default size, so the two trailing
    /// controls line up; scales so the initial stays inside its circle.
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = Spacing.minimumHitTarget
    @State private var hasGreeted = false
    @State private var greetTrigger = 0
    @State private var iconBounce = 0

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    var body: some View {
        Group {
            // At accessibility sizes the controls take their own row above
            // the greeting; beside it they squeezed the text to a few
            // letters a line and pushed the header past both screen edges.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Spacer(minLength: 0)
                        controls
                    }
                    greetingStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    greetingStack
                    Spacer()
                    controls
                }
            }
        }
        .padding(.top, Spacing.sm)
    }

    private var greetingStack: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if displayName.isEmpty {
                Text(greeting)
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColor.textPrimary)
            } else {
                // Beside the controls the comma leads into the name; on a
                // line of its own at accessibility sizes it just dangles.
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
        // Past AX2 a large-title name broke mid-word a few letters a line;
        // the page title stops growing where the rest of the text keeps on.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var controls: some View {
        HStack(spacing: Spacing.sm) {
            if let logButton { logButton }
            avatarButton
        }
    }

    @ViewBuilder
    private var avatarButton: some View {
        if let onAvatarTap {
            Button(action: onAvatarTap) {
                avatarBadge
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9, pressedOpacity: 0.85))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Profile")
            .accessibilityHint("Opens your profile and settings.")
            .accessibilityAddTraits(.isButton)
        } else {
            avatarBadge
        }
    }

    private var avatarBadge: some View {
        ZStack {
            if let data = avatarImageData, let uiImage = AvatarImageCache.shared.image(for: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .accessibilityIgnoresInvertColors()
                    .scaledToFill()
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 1.5)
                    }
            } else {
                Circle()
                    .fill(LinearGradient(colors: [AppColor.tileTop, AppColor.tileBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.paperEdge, lineWidth: 0.5)
                    }

                if displayName.isEmpty {
                    Image(systemName: "person.fill")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(AppColor.textPrimary)
                        .symbolEffect(.bounce, value: iconBounce)
                } else {
                    Text(String(displayName.prefix(1)))
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.textPrimary)
                }
            }
        }
        .liquidGlass(.circle)
        .phaseAnimator([1.0, 1.08], trigger: greetTrigger) { avatar, scale in
            avatar.scaleEffect(scale)
        } animation: { _ in
            AppAnimation.springBouncy
        }
        .onAppear {
            guard !hasGreeted else { return }
            hasGreeted = true
            guard !reduceMotion else { return }
            iconBounce &+= 1
            greetTrigger &+= 1
        }
    }
}

#Preview("With Name") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        WelcomeHeader(
            greeting: "Good evening",
            name: "Alex",
            date: "Thursday, April 10",
            avatarImageData: nil,
            onAvatarTap: {}
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("No Name") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        WelcomeHeader(
            greeting: "Good evening",
            name: "",
            date: "Thursday, April 10",
            onAvatarTap: {}
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
