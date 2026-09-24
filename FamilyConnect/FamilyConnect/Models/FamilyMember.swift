import Foundation
import CloudKit

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var email: String
    var phoneNumber: String
    var profileImageURL: String?
    var role: String // "Parent", "Child", "Guardian", etc.
    var dateAdded: Date
    
    init(name: String, email: String, phoneNumber: String, role: String) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.phoneNumber = phoneNumber
        self.role = role
        self.dateAdded = Date()
    }
    
    // Convert to CloudKit CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "FamilyMember")
        record["name"] = name
        record["email"] = email
        record["phoneNumber"] = phoneNumber
        record["profileImageURL"] = profileImageURL
        record["role"] = role
        record["dateAdded"] = dateAdded
        return record
    }
}
