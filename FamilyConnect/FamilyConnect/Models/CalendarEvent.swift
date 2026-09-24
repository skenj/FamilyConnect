import Foundation
import CloudKit

struct CalendarEvent: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var startDate: Date
    var endDate: Date
    var location: String?
    var familyMemberID: UUID // Who created it
    var createdDate: Date
    var color: String // For color coding
    
    init(title: String, description: String, startDate: Date, endDate: Date, familyMemberID: UUID) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.familyMemberID = familyMemberID
        self.createdDate = Date()
        self.color = "blue"
    }
    
    // Convert to CloudKit CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "CalendarEvent")
        record["title"] = title
        record["description"] = description
        record["startDate"] = startDate
        record["endDate"] = endDate
        record["location"] = location
        record["familyMemberID"] = familyMemberID.uuidString
        record["createdDate"] = createdDate
        record["color"] = color
        return record
    }
}
