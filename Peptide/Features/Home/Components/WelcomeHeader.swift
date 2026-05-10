import SwiftUI

struct WelcomeHeader: View {
    let greeting: String
    let name: String
    let date: String
    var avatarImageData: Data? = nil
    var onAvatarTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasGreeted = false
    @State private var avatarScale: CGFloat = 1.0
    @State private var iconBounce = 0

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if displayName.isEmpty {
                    Text(greeting)
                        .font(AppFont.largeTitle)
                        .foregroundStyle(AppColor.textPrimary)
                } else {
                    Text("\(greeting),")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)

                    Text(displayName)
                        .font(AppFont.largeTitle)
                        .foregroundStyle(AppColor.accentLight)
                }

                Text(date)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            avatarButton
        }
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder
    private var avatarButton: some View {
        if let onAvatarTap {
            Button(action: onAvatarTap) {
                avatarBadge
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9, pressedOpacity: 0.85))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Customize profile")
            .accessibilityHint("Edit your name, photo, goals, and stacks.")
            .accessibilityAddTraits(.isButton)
        } else {
            avatarBadge
        }
    }

    private var avatarBadge: some View {
        ZStack {
            if let data = avatarImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 1.5)
                    }
            } else {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.2))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                    }

                if displayName.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColor.accentLight)
                        .symbolEffect(.bounce, value: iconBounce)
                } else {
                    Text(String(displayName.prefix(1)))
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.accentLight)
                }
            }

            if onAvatarTap != nil {
                editIndicator
            }
        }
        .liquidGlass(.circle)
        .scaleEffect(avatarScale)
        .onAppear {
            guard !hasGreeted else { return }
            hasGreeted = true
            guard !reduceMotion else { return }
            iconBounce &+= 1
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
                avatarScale = 1.08
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    avatarScale = 1.0
                }
            }
        }
    }

    /// Small pencil badge in the bottom-right of the avatar so users discover
    /// the tap-to-customize affordance. Hidden when the avatar isn't tappable
    /// (e.g. legacy callers that don't pass `onAvatarTap`).
    private var editIndicator: some View {
        Image(systemName: "pencil")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(AppColor.background)
            .frame(width: 18, height: 18)
            .background {
                Circle()
                    .fill(AppColor.accentPrimary)
                    .overlay {
                        Circle().strokeBorder(AppColor.background, lineWidth: 1.5)
                    }
            }
            .offset(x: 18, y: 18)
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
