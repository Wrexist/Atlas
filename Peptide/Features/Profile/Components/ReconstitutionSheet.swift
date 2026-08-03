import SwiftUI

/// Sheet wrapper around `ReconstitutionCalculator`. Lives behind a
/// settings-row tap (or a Spotlight intent in the future), keeps
/// the standalone calculator view free of navigation chrome so it
/// can also be embedded inline elsewhere (e.g. a future first-time-
/// reconstitution onboarding step).
struct ReconstitutionSheet: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    intro
                    ReconstitutionCalculator()
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle("Reconstitution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calculator")
                .font(AppFont.scaled(13, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.accentLight.opacity(0.85))
            Text("Reconstitution helper")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
            Text("Powder + water + target dose → exact U-100 syringe units. Use the sliders or tap a quick-pick to set each input.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
