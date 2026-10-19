import SwiftUI

/// Preferences, data tools, account and app info, pushed from Profile so the
/// Profile scroll stays about the user rather than mixing in configuration.
struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showRestoreBackup = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                TrainingSettingsSection()
                    .sectionAppear(index: 0)

                WeeklySummaryToggleRow()
                    .sectionAppear(index: 1)

                AppearanceSettings()
                    .sectionAppear(index: 2)

                ExportSection()
                    .sectionAppear(index: 3)

                RestoreBackupEntryRow(onTap: { showRestoreBackup = true })
                    .scrollReveal()

                #if DEBUG
                ScreenshotModeRow()
                    .scrollReveal()
                #endif

                AccountSection()
                    .scrollReveal()

                DiagnosticsSection()
                    .scrollReveal()

                AboutSection()
                    .scrollReveal()
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.bottom, Spacing.xxxxl)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(AppColor.background)
        .navigationTitle("Settings")
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
