import Foundation

struct UserProfile {
    var name: String
    var goals: [String]
    var memberSince: Date
    var healthConnected: Bool
    var hapticFeedbackEnabled: Bool = true
    var doseRemindersEnabled: Bool = false
}
