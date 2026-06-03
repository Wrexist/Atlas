import SwiftUI
import PhotosUI

/// Compact grid picker for the built-in symbol-on-gradient avatars.
/// Lives in its own file (split out from `ProfileCustomizationSheet`)
/// because the parent was past 1,200 lines; the sheet's purpose is
/// distinct enough — pick a preset, hand it back — that the file
/// boundary doesn't introduce coupling.
struct AvatarPresetPickerSheet: View {
    let onPick: (AvatarPreset) -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: Spacing.md)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(AvatarPreset.all) { preset in
                        Button {
                            Haptics.impact(.light)
                            onPick(preset)
                        } label: {
                            tile(for: preset)
                        }
                        .buttonStyle(ScalePressStyle())
                    }
                }
                .padding(Spacing.lg)
            }
            .background(AppColor.background)
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func tile(for preset: AvatarPreset) -> some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: preset.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 1)
                    }
                Image(systemName: preset.symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .liquidGlass(.circle)
        }
        .frame(maxWidth: .infinity)
    }
}
