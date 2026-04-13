import Foundation

struct UserProfile: Codable {
    var name: String
    var goals: [String]
    var memberSince: Date
    var healthConnected: Bool
    var hapticFeedbackEnabled: Bool = true
    var doseRemindersEnabled: Bool = false

    static var fresh: UserProfile {
        UserProfile(
            name: "",
            goals: [],
            memberSince: Date(),
            healthConnected: false
        )
    }
}
