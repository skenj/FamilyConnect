import Foundation
import CloudKit
import CoreLocation

struct FamilyZone: Identifiable, Codable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double // metres (min 100, max 5000)
    var triggerMode: TriggerMode
    var color: String  // hex color for map overlay
    var createdByID: UUID
    var createdByName: String
    var createdDate: Date
    var isActive: Bool

    enum TriggerMode: String, Codable, CaseIterable {
        case enter  = "enter"
        case leave  = "leave"
        case both   = "both"

        var displayName: String {
            switch self {
            case .enter: return "On arrival"
            case .leave: return "On departure"
            case .both:  return "Arrival & departure"
            }
        }

        var systemImage: String {
            switch self {
            case .enter: return "arrow.down.circle.fill"
            case .leave: return "arrow.up.circle.fill"
            case .both:  return "arrow.up.arrow.down.circle.fill"
            }
        }
    }

    static let recordType = "FamilyZone"

    init(
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 200,
        triggerMode: TriggerMode = .both,
        color: String = "#FF6B6B",
        createdByID: UUID,
        createdByName: String
    ) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = max(100, min(5000, radius))
        self.triggerMode = triggerMode
        self.color = color
        self.createdByID = createdByID
        self.createdByName = createdByName
        self.createdDate = Date()
        self.isActive = true
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var region: CLCircularRegion {
        let region = CLCircularRegion(
            center: coordinate,
            radius: radius,
            identifier: id.uuidString
        )
        region.notifyOnEntry = triggerMode == .enter || triggerMode == .both
        region.notifyOnExit  = triggerMode == .leave || triggerMode == .both
        return region
    }

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["name"]          = name
        record["latitude"]      = latitude
        record["longitude"]     = longitude
        record["radius"]        = radius
        record["triggerMode"]   = triggerMode.rawValue
        record["color"]         = color
        record["createdByID"]   = createdByID.uuidString
        record["createdByName"] = createdByName
        record["createdDate"]   = createdDate
        record["isActive"]      = isActive ? 1 : 0
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> FamilyZone? {
        guard
            let name      = record["name"]          as? String,
            let latitude  = record["latitude"]       as? Double,
            let longitude = record["longitude"]      as? Double,
            let radius    = record["radius"]         as? Double,
            let modeRaw   = record["triggerMode"]    as? String,
            let byIDStr   = record["createdByID"]    as? String,
            let byID      = UUID(uuidString: byIDStr),
            let byName    = record["createdByName"]  as? String
        else { return nil }

        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        var zone = FamilyZone(
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            triggerMode: TriggerMode(rawValue: modeRaw) ?? .both,
            color: record["color"] as? String ?? "#FF6B6B",
            createdByID: byID,
            createdByName: byName
        )
        // Override generated id/date with stored values
        // (Swift structs: reassign via a new init trick)
        var z = FamilyZone(
            name: name, latitude: latitude, longitude: longitude,
            radius: radius,
            triggerMode: TriggerMode(rawValue: modeRaw) ?? .both,
            color: record["color"] as? String ?? "#FF6B6B",
            createdByID: byID, createdByName: byName
        )
        z.isActive = (record["isActive"] as? Int ?? 1) == 1
        return z
    }
}
