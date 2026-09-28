import Foundation
import CloudKit

struct CalendarEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var startDate: Date
    var endDate: Date
    var familyMemberID: UUID
    var assignedMemberID: UUID?
    var isFamilyWide: Bool

    init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        startDate: Date,
        endDate: Date,
        familyMemberID: UUID = UUID(),
        assignedMemberID: UUID? = nil,
        isFamilyWide: Bool = true
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.familyMemberID = familyMemberID
        self.assignedMemberID = assignedMemberID
        self.isFamilyWide = isFamilyWide
    }

    static let recordType = "CalendarEvent"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["title"] = title
        record["eventDescription"] = description
        record["startDate"] = startDate
        record["endDate"] = endDate
        record["familyMemberID"] = familyMemberID.uuidString
        if let assignedMemberID {
            record["assignedMemberID"] = assignedMemberID.uuidString
        }
        record["isFamilyWide"] = isFamilyWide
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> CalendarEvent? {
        guard let title = record["title"] as? String else { return nil }
        let start = record["startDate"] as? Date ?? Date()
        let end = record["endDate"] as? Date ?? start.addingTimeInterval(3600)
        let familyID = (record["familyMemberID"] as? String).flatMap(UUID.init) ?? UUID()
        let assigned = (record["assignedMemberID"] as? String).flatMap(UUID.init)
        let wide = record["isFamilyWide"] as? Bool ?? (assigned == nil)
        return CalendarEvent(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            title: title,
            description: (record["eventDescription"] as? String) ?? (record["description"] as? String) ?? "",
            startDate: start,
            endDate: end,
            familyMemberID: familyID,
            assignedMemberID: assigned,
            isFamilyWide: wide
        )
    }
}
