import SwiftUI

/// Vertical pager in the shape of the watchOS 10 system apps: one
/// glanceable page per domain, each blooming its own colour over black,
/// paged with the Digital Crown. Each page learns when it is on screen so
/// its rings and numbers can replay their entrance.
///
/// Pages appear only when the phone sent their data, so a user without
/// Apple Health or a protocol never scrolls past an empty page. The
/// selection is bound to a stable tag so a page arriving mid-session
/// doesn't throw the pager back to the top. The one exception is the
/// Workout page: a workout starting on the phone brings it to the front,
/// since that is why the user raised their wrist. A complication tap
/// opens the page that complication summarises.
struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: WatchPage = .today

    private var pages: [WatchPage] {
        let data = store.watchData
        var pages: [WatchPage] = data.workout == nil ? [.today] : [.workout, .today]
        if data.vitals != nil { pages.append(.recovery) }
        if data.vitals?.sleep != nil { pages.append(.sleep) }
        if data.nutrition != nil { pages.append(.nutrition) }
        if data.totalToday > 0 || (data.totalDosesLogged ?? 0) > 0 { pages.append(.protocols) }
        return pages
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(pages, id: \.self) { page in
                    content(for: page)
                        .environment(\.watchPageIsActive, selection == page)
                        .tag(page)
                }
            }
            .tabViewStyle(.verticalPage)
        }
        .onAppear {
            if store.watchData.workout != nil { selection = .workout }
        }
        .onChange(of: store.watchData.workout?.sessionId) { _, session in
            if session != nil { selection = .workout }
        }
        .onOpenURL { url in
            if let page = WatchPage(url: url), pages.contains(page) { selection = page }
        }
        .onChange(of: pages) { _, pages in
            if !pages.contains(selection) { selection = .today }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshForNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.refreshForNow()
        }
    }

    @ViewBuilder
    private func content(for page: WatchPage) -> some View {
        let data = store.watchData
        switch page {
        case .workout:
            if let workout = data.workout { WorkoutPage(workout: workout) }
        case .today:
            TodayPage()
        case .recovery:
            if let vitals = data.vitals { RecoveryPage(vitals: vitals) }
        case .sleep:
            if let sleep = data.vitals?.sleep { SleepPage(sleep: sleep) }
        case .nutrition:
            if let nutrition = data.nutrition { NutritionPage(nutrition: nutrition) }
        case .protocols:
            ProtocolPage()
        }
    }
}
