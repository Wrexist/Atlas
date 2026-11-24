import Foundation

/// The user's records that never sync: they live in files and defaults on
/// this device only, so they belong to whoever used it. Delete All Data and
/// the user's Remove answer to the iCloud account-change prompt both erase
/// this one list, so neither can leave a store behind the other covers.
/// Never call it without such an explicit choice.
@MainActor
enum DeviceLocalData {
    static func eraseAll() {
        PersistenceService.shared.clearAll()
        ProgressPhotoStorage.deleteAll()
        LabReportStorage.deleteAll()
        HealthJournalStore.shared.deleteAll()
        WeeklyPrepStore.shared.deleteAll()
        PantryStore.shared.deleteAll()
        GroceryChecklistStore.shared.deleteAll()
        FridgeStore.shared.deleteAll()
        TableMomentStore.shared.deleteAll()
        EquipmentProfileStore.shared.deleteAll()
        WorkoutTypeOverrideStore.deleteLegacy()
        AdaptiveTDEESettings.followedTargets = nil
        BackupSnapshotService.deleteAll()
        ExportService.shared.clearExports()
        AchievementService.shared.eraseAll()
        ScanCorrectionMemory.shared.eraseAll()
        Task {
            await BarcodeScanHistory.shared.removeAll()
            await BarcodeProductCache.shared.clear()
            await FoodSpotlightService.shared.removeAll()
        }
    }
}
