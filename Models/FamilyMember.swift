import Foundation
import CloudKit

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var nickname: String
    var email: String
    var phoneNumber: String
    var profileImageURL: String?
    var role: String
    var dateAdded: Date
    var inviteStatus: String
    var isCurrentUser: Bool
    var iCloudUserRecordName: String?

    // MARK: - Location (NEW)
    var latitude: Double?
    var longitude: Double?
    var lastLocationUpdate: Date?

    static let recordType = "FamilyMember"

    init(
        id: UUID = UUID(),
        name: String,
        email: String,
        phoneNumber: String,
        role: String,
        nickname: String = "",
        inviteStatus: String = "",
        iCloudUserRecordName: String? = nil,
        isCurrentUser: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        lastLocationUpdate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.phoneNumber = phoneNumber
        self.role = role
        self.nickname = nickname
        self.dateAdded = Date()
        self.inviteStatus = inviteStatus
        self.iCloudUserRecordName = iCloudUserRecordName
        self.isCurrentUser = isCurrentUser
        self.latitude = latitude
        self.longitude = longitude
        self.lastLocationUpdate = lastLocationUpdate
    }

    var displayName: String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isParent: Bool {
        role.caseInsensitiveCompare("Parent") == .orderedSame
    }

    var isChild: Bool {
        role.caseInsensitiveCompare("Child") == .orderedSame
    }

    mutating func updateLocation(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.lastLocationUpdate = Date()
    }

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["name"] = name
        record["nickname"] = nickname
        record["email"] = email
        record["phoneNumber"] = phoneNumber
        record["profileImageURL"] = profileImageURL
        record["role"] = role
        record["dateAdded"] = dateAdded
        record["inviteStatus"] = inviteStatus
        record["isCurrentUser"] = isCurrentUser
        record["iCloudUserRecordName"] = iCloudUserRecordName
        record["latitude"] = latitude as NSNumber?
        record["longitude"] = longitude as NSNumber?
        record["lastLocationUpdate"] = lastLocationUpdate
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> FamilyMember? {
        guard let name = record["name"] as? String else { return nil }
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        var member = FamilyMember(
            id: id,
            name: name,
            email: record["email"] as? String ?? "",
            phoneNumber: record["phoneNumber"] as? String ?? "",
            role: record["role"] as? String ?? "Family",
            nickname: record["nickname"] as? String ?? "",
            inviteStatus: record["inviteStatus"] as? String ?? "",
            iCloudUserRecordName: record["iCloudUserRecordName"] as? String,
            isCurrentUser: record["isCurrentUser"] as? Bool ?? false,
            latitude: (record["latitude"] as? NSNumber).map { Double(truncating: $0) },
            longitude: (record["longitude"] as? NSNumber).map { Double(truncating: $0) },
            lastLocationUpdate: record["lastLocationUpdate"] as? Date
        )
        member.profileImageURL = record["profileImageURL"] as? String
        return member
    }
}
