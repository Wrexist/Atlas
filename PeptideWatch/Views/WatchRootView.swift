import SwiftUI

enum WatchPage: Hashable {
    case today, recovery, sleep, nutrition, protocols
}

/// Vertical pager in the shape of the watchOS 10 system apps: one
/// glanceable page per domain, each blooming its own colour over black,
/// paged with the Digital Crown. Each page learns when it is on screen so
/// its rings and numbers can replay their entrance.
///
/// Pages appear only when the phone sent their data, so a user without
/// Apple Health or a protocol never scrolls past an empty page. The
/// selection is bound to a stable tag so a page arriving mid-session
/// doesn't throw the pager back to the top.
struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var selection: WatchPage = .today

    private var pages: [WatchPage] {
        let data = store.watchData
        var pages: [WatchPage] = [.today]
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
        .onChange(of: pages) { _, pages in
            if !pages.contains(selection) { selection = .today }
        }
    }

    @ViewBuilder
    private func content(for page: WatchPage) -> some View {
        let data = store.watchData
        switch page {
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
