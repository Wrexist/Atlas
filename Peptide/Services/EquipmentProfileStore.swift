import Foundation
import Observation

/// The equipment profile of each training place and which place the user
/// trains at today. Kept on this device: it describes the room the phone
/// is in, not the account.
@MainActor
@Observable
final class EquipmentProfileStore {
    static let shared = EquipmentProfileStore()

    @ObservationIgnored private let defaults: UserDefaults
    private static let locationKey = "equipmentProfile.location.v1"
    private static let profilesKey = "equipmentProfile.profiles.v1"

    private(set) var location: TrainingLocation
    private(set) var profiles: [TrainingLocation: EquipmentProfile]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        location = defaults.string(forKey: Self.locationKey).flatMap(TrainingLocation.init(rawValue:)) ?? .gym
        profiles = defaults.data(forKey: Self.profilesKey)
            .flatMap { try? JSONDecoder().decode([TrainingLocation: EquipmentProfile].self, from: $0) } ?? [:]
    }

    var current: EquipmentProfile { profile(for: location) }

    func profile(for location: TrainingLocation) -> EquipmentProfile {
        profiles[location] ?? .standard(for: location)
    }

    func select(_ location: TrainingLocation) {
        self.location = location
        defaults.set(location.rawValue, forKey: Self.locationKey)
    }

    func set(_ profile: EquipmentProfile, for location: TrainingLocation) {
        profiles[location] = profile
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
    }

    /// A backup's places, merged by `DeviceLocalBackup`.
    func restore(location: TrainingLocation, profiles: [TrainingLocation: EquipmentProfile]) {
        select(location)
        self.profiles = profiles
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
    }

    func deleteAll() {
        location = .gym
        profiles = [:]
        defaults.removeObject(forKey: Self.locationKey)
        defaults.removeObject(forKey: Self.profilesKey)
    }
}
