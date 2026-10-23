import SwiftUI

struct ProfileHeader: View {
    let name: String
    let memberSince: Date
    let protocolCount: Int
    let daysLogged: Int
    var workoutCount: Int = 0
    var avatarImageData: Data? = nil
    var bio: String = ""
    /// Opens the photo / name / bio editor. Both the avatar and the
    /// pencil button route here.
    var onEdit: (() -> Void)? = nil

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    private var trimmedBio: String {
        bio.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.lg) {
                editableAvatar

                VStack(spacing: Spacing.xs) {
                    nameLine

                    Text("Member since \(memberSince, format: .dateTime.month(.wide).year())")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if !trimmedBio.isEmpty {
                    Text(trimmedBio)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.sm)
                }

                // Training and days are everyone's stats; Protocols joins
                // them only for users who run one, so it never shows a zero.
                HStack(spacing: Spacing.xxl) {
                    ProfileStat(value: workoutCount, label: "Workouts")
                    ProfileStat(value: daysLogged, label: "Days")
                    if protocolCount > 0 {
                        ProfileStat(value: protocolCount, label: "Protocols")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if let onEdit {
                    GlassIconButton(icon: "pencil", accessibilityLabel: "Edit profile", size: 32, action: onEdit)
                }
            }
        }
    }

    /// A missing name is an invitation to add one, not a placeholder.
    @ViewBuilder
    private var nameLine: some View {
        if !displayName.isEmpty {
            Text(displayName)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        } else if let onEdit {
            Button("Add your name", action: onEdit)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textSecondary)
                .minimumHitArea()
        }
    }

    /// The avatar is a second, larger target for the same edit action;
    /// hidden from VoiceOver because the pencil button already offers it.
    @ViewBuilder
    private var editableAvatar: some View {
        if let onEdit {
            Button(action: onEdit) { avatar }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
        } else {
            avatar
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = avatarImageData, let uiImage = AvatarImageCache.shared.image(for: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(avatarBorder)
                .liquidGlass(.circle)
                .accessibilityLabel(Text("Profile photo"))
        } else {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(avatarBorder)

                if displayName.isEmpty {
                    Image(systemName: "person.fill")
                        .font(AppFont.scaled(32, weight: .semibold, relativeTo: .title1))
                        .foregroundStyle(AppColor.accentLight)
                } else {
                    Text(String(displayName.prefix(1)))
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.accentLight)
                }
            }
            .liquidGlass(.circle)
            // Decorative — the name is shown as text in the header, so
            // the initial/placeholder glyph is redundant to VoiceOver.
            .accessibilityHidden(true)
        }
    }

    private var avatarBorder: some View {
        Circle()
            .strokeBorder(AppColor.glassBorderActive, lineWidth: 1.5)
    }
}

private struct ProfileStat: View {
    let value: Int
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text(value, format: .number)
                .font(AppFont.title2)
                .foregroundStyle(AppColor.accentLight)
                .contentTransition(.numericText())
                .appAnimation(AppAnimation.springSnappy, value: value)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("With Name") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProfileHeader(
            name: "Alex",
            memberSince: .now.addingTimeInterval(-90 * 86_400),
            protocolCount: 4,
            daysLogged: 45,
            bio: "Optimizing recovery and sleep."
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}

#Preview("New User") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProfileHeader(name: "", memberSince: .now, protocolCount: 0, daysLogged: 0)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
