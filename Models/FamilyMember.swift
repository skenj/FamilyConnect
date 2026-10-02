import Foundation
import CloudKit

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var email: String
    var phoneNumber: String
    var profileImageURL: String?
    var role: String // "parent" or "child"
    var dateAdded: Date
    var latitude: Double?
    var longitude: Double?
    var lastLocationUpdate: Date?
    
    init(name: String, email: String, phoneNumber: String, role: String) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.phoneNumber = phoneNumber
        self.role = role
        self.dateAdded = Date()
        self.latitude = nil
        self.longitude = nil
        self.lastLocationUpdate = nil
    }
    
    var isParent: Bool {
        return role.lowercased() == "parent"
    }
    
    var isChild: Bool {
        return role.lowercased() == "child"
    }
    
    mutating func updateLocation(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.lastLocationUpdate = Date()
    }
    
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "FamilyMember")
        record["name"] = name
        record["email"] = email
        record["phoneNumber"] = phoneNumber
        record["profileImageURL"] = profileImageURL
        record["role"] = role
        record["dateAdded"] = dateAdded
        record["latitude"] = latitude as NSNumber?
        record["longitude"] = longitude as NSNumber?
        record["lastLocationUpdate"] = lastLocationUpdate
        return record
    }
}
