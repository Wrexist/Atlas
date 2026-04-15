import Foundation

struct UserProfile: Codable {
    var name: String
    var goals: [String]
    var memberSince: Date
    var healthConnected: Bool
    var hapticFeedbackEnabled: Bool
    var doseRemindersEnabled: Bool
    var biometricLockEnabled: Bool

    init(name: String, goals: [String], memberSince: Date, healthConnected: Bool, hapticFeedbackEnabled: Bool = true, doseRemindersEnabled: Bool = false, biometricLockEnabled: Bool = false) {
        self.name = name
        self.goals = goals
        self.memberSince = memberSince
        self.healthConnected = healthConnected
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.doseRemindersEnabled = doseRemindersEnabled
        self.biometricLockEnabled = biometricLockEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        goals = try container.decode([String].self, forKey: .goals)
        memberSince = try container.decode(Date.self, forKey: .memberSince)
        healthConnected = try container.decode(Bool.self, forKey: .healthConnected)
        hapticFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedbackEnabled) ?? true
        doseRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .doseRemindersEnabled) ?? false
        biometricLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .biometricLockEnabled) ?? false
    }

    static var fresh: UserProfile {
        UserProfile(
            name: "",
            goals: [],
            memberSince: Date(),
            healthConnected: false
        )
    }
}
