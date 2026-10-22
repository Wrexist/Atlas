import SwiftUI

/// Settings pushed from Profile, so Profile itself stays about the user —
/// identity, progress, goals, body and health — and the switches live here.
/// Each card carries its own title, in the order Training, Reminders, Notifications,
/// Preferences, Data, Account, About.
struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showRestoreBackup = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                TrainingSettingsSection()

                DailyRemindersSection()

                WeeklySummaryToggleRow()

                AppearanceSettings()

                ExportSection()

                RestoreBackupEntryRow(onTap: { showRestoreBackup = true })

                // Developer surfaces stay out of customer builds.
                #if DEBUG
                DiagnosticsSection()

                ScreenshotModeRow()
                #endif

                AccountSection()

                AboutSection()
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
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(DataStore(seedSampleData: true))
    .preferredColorScheme(.dark)
}
