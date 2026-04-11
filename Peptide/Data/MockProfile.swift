import Foundation

enum MockProfile {
    static let current = UserProfile(
        name: "Alex",
        goals: ["Muscle Recovery", "Better Sleep", "Cognitive Enhancement", "Anti-Aging"],
        memberSince: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
        healthConnected: false
    )
}
