import Foundation

/// The stores that never sync, carried in an Atlas backup so the backup
/// file is their portable copy: the health journal, fridge and pantry,
/// weekly prep, shopping-list ticks, equipment profiles, Apple Health
/// workout-type picks and table moments.
///
/// Photos stay out — fridge cut-outs and table stickers are files, not
/// JSON. A restored product or dish whose file isn't on the device shows
/// without its picture, as it does on a device that never had it.
///
/// Every member is optional: nil (an older backup, or a member this build
/// can't read) leaves that store as it is, and so does an empty one, so a
/// backup taken while a store was unreadable can't wipe it. Replace swaps
/// each carried store for the backup's; Merge keeps the current record on
/// a conflict and adds what only the backup holds.
struct DeviceLocalBackup: Codable, Sendable {
    var healthJournal: [HealthJournalEntry]?
    var fridgeProducts: [FridgeProduct]?
    var fridgeItems: [FridgeItem]?
    var pantryKeys: [String]?
    var prepPlans: [PrepWeek]?
    var prepBoxes: [PrepBoxBatch]?
    var prepEatenBoxes: [UUID: PrepBoxBatch]?
    var groceryChecked: [String]?
    var groceryCleared: [String]?
    var trainingLocation: TrainingLocation?
    var equipmentProfiles: [TrainingLocation: EquipmentProfile]?
    var workoutTypeOverrides: [String: String]?
    var tableMoments: [TableMoment]?

    /// What this device's stores hold now.
    @MainActor
    static func current() -> DeviceLocalBackup {
        let fridge = FridgeStore.shared
        let prep = WeeklyPrepStore.shared
        let grocery = GroceryChecklistStore.shared
        let equipment = EquipmentProfileStore.shared
        return DeviceLocalBackup(
            healthJournal: HealthJournalStore.shared.entries,
            fridgeProducts: fridge.products,
            fridgeItems: fridge.items,
            pantryKeys: PantryStore.shared.manualKeys.sorted(),
            prepPlans: prep.plans,
            prepBoxes: prep.boxes,
            prepEatenBoxes: prep.eatenBoxes,
            groceryChecked: grocery.checked.sorted(),
            groceryCleared: grocery.cleared.sorted(),
            trainingLocation: equipment.location,
            equipmentProfiles: equipment.profiles,
            workoutTypeOverrides: WorkoutTypeOverrideStore.shared.overrides,
            tableMoments: TableMomentStore.shared.moments
        )
    }

    /// Writes each carried store back into this device's.
    @MainActor
    func restore(replacing: Bool) {
        if let healthJournal {
            let journal = HealthJournalStore.shared
            journal.restore(Self.merged(journal.entries, healthJournal, replacing: replacing, by: \.dayKey))
        }
        if fridgeProducts != nil || fridgeItems != nil {
            let fridge = FridgeStore.shared
            fridge.restore(
                products: Self.merged(fridge.products, fridgeProducts ?? [], replacing: replacing, by: \.id),
                items: Self.merged(fridge.items, fridgeItems ?? [], replacing: replacing, by: \.id)
            )
        }
        if let pantryKeys {
            let pantry = PantryStore.shared
            pantry.restore(manualKeys: Self.merged(pantry.manualKeys, Set(pantryKeys), replacing: replacing))
        }
        if prepPlans != nil || prepBoxes != nil {
            let prep = WeeklyPrepStore.shared
            prep.restore(
                plans: Self.merged(prep.plans, prepPlans ?? [], replacing: replacing, by: \.weekStart),
                boxes: Self.merged(prep.boxes, prepBoxes ?? [], replacing: replacing, by: \.id),
                eatenBoxes: Self.merged(prep.eatenBoxes, prepEatenBoxes ?? [:], replacing: replacing)
            )
        }
        if groceryChecked != nil || groceryCleared != nil {
            let grocery = GroceryChecklistStore.shared
            grocery.restore(
                checked: Self.merged(grocery.checked, Set(groceryChecked ?? []), replacing: replacing),
                cleared: Self.merged(grocery.cleared, Set(groceryCleared ?? []), replacing: replacing)
            )
        }
        if trainingLocation != nil || equipmentProfiles != nil {
            let equipment = EquipmentProfileStore.shared
            equipment.restore(
                location: replacing ? trainingLocation ?? equipment.location : equipment.location,
                profiles: Self.merged(equipment.profiles, equipmentProfiles ?? [:], replacing: replacing)
            )
        }
        if let workoutTypeOverrides {
            let overrides = WorkoutTypeOverrideStore.shared
            overrides.restore(Self.merged(overrides.overrides, workoutTypeOverrides, replacing: replacing))
        }
        if let tableMoments {
            let tables = TableMomentStore.shared
            tables.restore(Self.merged(tables.moments, tableMoments, replacing: replacing, by: \.id))
        }
    }

    // MARK: - Merge rules

    /// Replace: the backup's records. Merge: the current ones, then each
    /// backup record whose key the current ones don't hold. An empty
    /// backup member keeps the current records either way.
    static func merged<Record, Key: Hashable>(
        _ current: [Record], _ restored: [Record], replacing: Bool, by key: (Record) -> Key
    ) -> [Record] {
        guard !restored.isEmpty else { return current }
        guard !replacing else { return restored }
        let known = Set(current.map(key))
        return current + restored.filter { !known.contains(key($0)) }
    }

    static func merged<Element: Hashable>(_ current: Set<Element>, _ restored: Set<Element>, replacing: Bool) -> Set<Element> {
        guard !restored.isEmpty else { return current }
        return replacing ? restored : current.union(restored)
    }

    static func merged<Key: Hashable, Value>(_ current: [Key: Value], _ restored: [Key: Value], replacing: Bool) -> [Key: Value] {
        guard !restored.isEmpty else { return current }
        return replacing ? restored : current.merging(restored) { mine, _ in mine }
    }
}

extension DeviceLocalBackup {
    /// Each member decodes on its own: one this build can't read is left
    /// out (nil, so its store stays as it is) instead of failing the whole
    /// backup. In an extension so the memberwise init stays.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        healthJournal = try? c.decodeIfPresent([HealthJournalEntry].self, forKey: .healthJournal)
        fridgeProducts = try? c.decodeIfPresent([FridgeProduct].self, forKey: .fridgeProducts)
        fridgeItems = try? c.decodeIfPresent([FridgeItem].self, forKey: .fridgeItems)
        pantryKeys = try? c.decodeIfPresent([String].self, forKey: .pantryKeys)
        prepPlans = try? c.decodeIfPresent([PrepWeek].self, forKey: .prepPlans)
        prepBoxes = try? c.decodeIfPresent([PrepBoxBatch].self, forKey: .prepBoxes)
        prepEatenBoxes = try? c.decodeIfPresent([UUID: PrepBoxBatch].self, forKey: .prepEatenBoxes)
        groceryChecked = try? c.decodeIfPresent([String].self, forKey: .groceryChecked)
        groceryCleared = try? c.decodeIfPresent([String].self, forKey: .groceryCleared)
        trainingLocation = try? c.decodeIfPresent(TrainingLocation.self, forKey: .trainingLocation)
        equipmentProfiles = try? c.decodeIfPresent([TrainingLocation: EquipmentProfile].self, forKey: .equipmentProfiles)
        workoutTypeOverrides = try? c.decodeIfPresent([String: String].self, forKey: .workoutTypeOverrides)
        tableMoments = try? c.decodeIfPresent([TableMoment].self, forKey: .tableMoments)
    }
}
