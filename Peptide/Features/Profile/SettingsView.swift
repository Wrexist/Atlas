import SwiftUI

/// Settings pushed from Profile, so Profile itself stays about the user —
/// identity, progress, goals, body and health — and the switches live here.
/// Five titled sections, everyday first — Training, Reminders, Appearance,
/// Data, About — and last, on its own, the two irreversible deletes, so they
/// never sit beside an everyday control.
struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showRestoreBackup = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                section("Training") { TrainingSettingsSection() }

                section("Reminders") { DailyRemindersSection() }

                section("Appearance") { AppearanceSettings() }

                section("Data") {
                    AccountSection()

                    aiPrivacySection

                    ExportSection()

                    RestoreBackupEntryRow(onTap: { showRestoreBackup = true })
                }

                section("About") { AboutSection() }

                DeleteDataSection()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
            .readableContentWidth()
        }
        .pageBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .solidTopScrollEdge()
        .sheet(isPresented: $showRestoreBackup) {
            RestoreBackupSheet()
                .environment(dataStore)
        }
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Spacing.md) {
            HomeSectionHeader(title: title)
            content()
        }
    }

    /// The switches that decide what leaves the device, under one title
    /// instead of three untitled rows floating between cards. Plain rows
    /// split by rules, so the card isn't a card of cards.
    private var aiPrivacySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("AI & privacy", systemImage: "lock.shield.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.bottom, Spacing.xxs)

                WeeklySummaryToggleRow()

                OnDeviceSummaryToggleRow()

                Divider().overlay(AppColor.glassBorder)

                CrashReportToggleRow()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
