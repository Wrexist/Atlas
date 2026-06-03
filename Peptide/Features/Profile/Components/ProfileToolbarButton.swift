import SwiftUI

/// Top-right avatar button that opens the Profile + settings sheet from
/// any tab. Profile was demoted from the tab bar in the training pivot,
/// which left it reachable only from the Today header — this gives every
/// tab the same one-tap entry by flipping `AppState.showProfile`, which a
/// single app-level sheet observes.
struct ProfileToolbarButton: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            Haptics.impact(.light)
            appState.showProfile = true
        } label: {
            ZStack {
                Circle()
                    .fill(AppColor.surfaceSecondary)
                    .overlay {
                        Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                if let data = dataStore.profile.avatarImageData,
                   let uiImage = AvatarImageCache.shared.image(for: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile")
    }
}
