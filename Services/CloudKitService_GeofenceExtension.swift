import Foundation
import CloudKit

// MARK: - Geofence CloudKit operations
// Add this file to Services/ in Xcode.

extension CloudKitService {

    // MARK: - Published zones array
    // Add this to CloudKitService's @Published properties list:
    // @Published var familyZones: [FamilyZone] = []
    // Since we can't modify the main file from an extension,
    // zones are stored here and synced via GeofenceService.

    // MARK: - Fetch

    func fetchFamilyZones() async {
        guard !isLocalSandbox else { return }
        let query = CKQuery(recordType: FamilyZone.recordType, predicate: NSPredicate(value: true))
        let database = isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        guard let result = try? await database.records(matching: query) else { return }

        let zones = result.matchResults.compactMap { _, item -> FamilyZone? in
            guard let record = try? item.get() else { return nil }
            return FamilyZone.fromCKRecord(record)
        }.filter { $0.isActive }

        await MainActor.run {
            // Start geofence monitoring for children
            if let me = currentUser, me.isChild {
                Task { @MainActor in
                    GeofenceService.shared.startMonitoring(zones: zones)
                }
            }
        }
    }

    // MARK: - Save

    func saveFamilyZone(_ zone: FamilyZone) async {
        guard canAddFamilyMembers else {
            error = "Only a Parent can create zones."
            return
        }

        // Save to CloudKit
        if !isLocalSandbox {
            let record = zone.toCKRecord()
            let database = isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
            _ = try? await database.save(record)
        }

        // Update local state via notification so LocationView can refresh
        NotificationCenter.default.post(name: .familyZonesUpdated, object: zone)
    }

    // MARK: - Delete

    func deleteFamilyZone(_ zone: FamilyZone) async {
        guard canAddFamilyMembers else {
            error = "Only a Parent can delete zones."
            return
        }

        GeofenceService.shared.stopMonitoring(zone: zone)

        if !isLocalSandbox {
            let recordID = CKRecord.ID(recordName: zone.id.uuidString)
            let database = isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
            _ = try? await database.deleteRecord(withID: recordID)
        }

        NotificationCenter.default.post(name: .familyZonesUpdated, object: nil)
    }
}

extension Notification.Name {
    static let familyZonesUpdated = Notification.Name("familyZonesUpdated")
}
