import SwiftUI
import UserNotifications

@main
struct PeptideApp: App {
    @State private var appState = AppState()
    @State private var dataStore = DataStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var notificationDelegate: NotificationDelegate?
    @State private var isUnlocked = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .environment(dataStore)
                    .preferredColorScheme(.dark)
                    .tint(AppColor.accentPrimary)
            } else if dataStore.profile.biometricLockEnabled, !isUnlocked {
                LockScreenView { isUnlocked = true }
                    .preferredColorScheme(.dark)
                    .tint(AppColor.accentPrimary)
            } else {
                mainContent
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, dataStore.profile.biometricLockEnabled {
                isUnlocked = false
            }
        }
        .task(id: dataStore.profile.healthConnected) {
            if dataStore.profile.healthConnected {
                await HealthKitService.shared.startBackgroundDelivery()
            } else {
                HealthKitService.shared.stopBackgroundDelivery()
            }
        }
    }

    private var mainContent: some View {
        TabView(selection: $appState.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView()
            }
            Tab("Peptides", systemImage: "flask.fill", value: .database) {
                PeptideListView()
            }
            Tab("Protocols", systemImage: "list.clipboard.fill", value: .protocols) {
                ProtocolListView()
            }
            Tab("Analytics", systemImage: "chart.bar.fill", value: .analytics) {
                AnalyticsView()
            }
            Tab("Profile", systemImage: "person.fill", value: .profile) {
                ProfileView()
            }
        }
        .tabViewBottomAccessory {
            NextDoseAccessoryView()
        }
        .environment(appState)
        .environment(dataStore)
        .preferredColorScheme(.dark)
        .tint(AppColor.accentPrimary)
        .task {
            let delegate = NotificationDelegate(dataStore: dataStore)
            notificationDelegate = delegate
            UNUserNotificationCenter.current().delegate = delegate
            NotificationService.shared.registerCategories()

            guard dataStore.profile.doseRemindersEnabled else {
                NotificationService.shared.cancelAll()
                return
            }

            let status = await NotificationService.shared.checkAuthorization()
            if status == .notDetermined {
                let granted = await NotificationService.shared.requestAuthorization()
                if !granted {
                    dataStore.profile.doseRemindersEnabled = false
                    dataStore.persistProfile()
                    NotificationService.shared.cancelAll()
                    return
                }
            } else if status == .denied {
                dataStore.profile.doseRemindersEnabled = false
                dataStore.persistProfile()
                NotificationService.shared.cancelAll()
                return
            }

            NotificationService.shared.scheduleNotifications(for: dataStore.activeProtocols)
        }
    }
}

struct NextDoseAccessoryView: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let next = dataStore.nextDose {
                Image(systemName: "syringe.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.accentPrimary)
                Text("Next: \(next.peptide.abbreviation) \u{2022} \(next.dose)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(next.date.formatted(.dateTime.hour().minute()))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accentLight)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.accentPrimary)
                Text("All doses completed for today")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }
}
