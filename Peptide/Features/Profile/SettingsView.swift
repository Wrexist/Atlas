import SwiftUI

/// Settings pushed from Profile, so Profile itself stays about the user —
/// identity, progress, goals, body and health — and the switches live here.
/// Each card carries its own title, in the order Training, Reminders,
/// Preferences, AI & privacy, Data, Account, About — and last, on its own,
/// the two irreversible deletes, so they never sit beside an everyday control.
struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showRestoreBackup = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                TrainingSettingsSection()

                DailyRemindersSection()

                AppearanceSettings()

                aiPrivacySection

                // Export and its round trip, restore, read as one group.
                VStack(spacing: Spacing.sm) {
                    ExportSection()

                    RestoreBackupEntryRow(onTap: { showRestoreBackup = true })
                }

                // Developer surfaces stay out of customer builds.
                #if DEBUG
                DiagnosticsSection()

                ScreenshotModeRow()
                #endif

                AccountSection()

                AboutSection()

                DeleteDataSection()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
            .readableContentWidth()
        }
        .background(AppColor.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRestoreBackup) {
            RestoreBackupSheet()
                .environment(dataStore)
        }
    }

    /// The switches that decide what leaves the device, under one title
    /// instead of three untitled rows floating between cards.
    private var aiPrivacySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("AI & privacy", systemImage: "lock.shield.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.bottom, Spacing.xxs)

                WeeklySummaryToggleRow()

                OnDeviceSummaryToggleRow()

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
