import SwiftUI

@Observable
final class ProfileViewModel {
    var profile = MockProfile.current
    var selectedGoals: Set<String>

    init() {
        selectedGoals = Set(MockProfile.current.goals)
    }

    let availableGoals = [
        "Muscle Recovery",
        "Better Sleep",
        "Cognitive Enhancement",
        "Anti-Aging",
        "Fat Loss",
        "Immune Support",
        "Joint Health",
        "Stress Reduction",
    ]

    var memberDuration: String {
        let months = Calendar.current.dateComponents([.month], from: profile.memberSince, to: Date()).month ?? 0
        return months <= 1 ? "1 month" : "\(months) months"
    }

    var daysLogged: Int {
        let calendar = Calendar.current
        let uniqueDays = Set(MockEntries.allEntries.filter(\.completed).map {
            calendar.startOfDay(for: $0.date)
        })
        return uniqueDays.count
    }

    func toggleGoal(_ goal: String) {
        withAnimation(AppAnimation.springSnappy) {
            if selectedGoals.contains(goal) {
                selectedGoals.remove(goal)
            } else {
                selectedGoals.insert(goal)
            }
        }
    }
}
