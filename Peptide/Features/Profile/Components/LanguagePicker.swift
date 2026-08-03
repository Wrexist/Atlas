import SwiftUI

struct LanguagePickerRow: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(DataStore.self) private var dataStore
    @State private var isPresented = false

    var body: some View {
        Button {
            Haptics.impact(.light)
            isPresented = true
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "character.bubble.fill")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 24)

                Text("Language")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)

                Spacer()

                HStack(spacing: Spacing.xs) {
                    Text(currentFlag)
                        .font(AppFont.scaled(16))
                    Text(currentName)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            LanguagePickerSheet()
                .liquidGlassPresentation(detents: [.large])
        }
    }

    private var currentFlag: String {
        localization.selectedLanguage?.flag ?? "🌐"
    }

    private var currentName: String {
        localization.selectedLanguage?.nativeName ?? String(localized: "System Default")
    }
}

struct LanguagePickerSheet: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.sm) {
                        LanguageRow(
                            flag: "🌐",
                            nativeName: String(localized: "System Default"),
                            englishName: nil,
                            isSelected: localization.selectedCode == nil,
                            isSystemDefault: true,
                            action: { select(nil) }
                        )

                        Divider()
                            .foregroundStyle(AppColor.glassBorder)
                            .padding(.vertical, Spacing.xs)

                        ForEach(AppLanguage.allCases) { language in
                            LanguageRow(
                                flag: language.flag,
                                nativeName: language.nativeName,
                                englishName: language.englishName,
                                isSelected: localization.selectedCode == language.rawValue,
                                isSystemDefault: false,
                                action: { select(language.rawValue) }
                            )
                        }
                    }
                    .padding(Spacing.screenPadding)
                }
            }
            .navigationTitle(Text("Choose Language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(AppFont.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                }
            }
        }
        .tint(AppColor.accentPrimary)
    }

    private func select(_ code: String?) {
        guard localization.selectedCode != code else { return }
        Haptics.selection()
        withAnimation(.snappy(duration: 0.2)) {
            localization.selectedCode = code
        }
    }
}

private struct LanguageRow: View {
    let flag: String
    let nativeName: String
    let englishName: String?
    let isSelected: Bool
    let isSystemDefault: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCardCompact(tinted: isSelected) {
                HStack(spacing: Spacing.md) {
                    Text(flag)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(AppColor.cardOverlay)
                        )

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(nativeName)
                            .font(AppFont.body.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)

                        if let englishName {
                            Text(englishName)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                                .lineLimit(1)
                        } else if isSystemDefault {
                            Text(systemLanguageDescription)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(AppFont.scaled(20, weight: .regular))
                        .foregroundStyle(
                            isSelected ? AppColor.accentPrimary : AppColor.glassBorder
                        )
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var systemLanguageDescription: String {
        let locale = Locale.autoupdatingCurrent
        guard let code = locale.language.languageCode?.identifier,
              let name = locale.localizedString(forLanguageCode: code) else {
            return ""
        }
        return name.capitalized
    }
}

#Preview {
    LanguagePickerSheet()
        .environment(LocalizationManager.shared)
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
