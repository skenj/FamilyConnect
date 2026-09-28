import Foundation
import UIKit
import CloudKit

struct FamilyMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var nickname: String
    var email: String
    var phoneNumber: String
    var profileImageURL: String?
    var role: String
    var dateAdded: Date
    var iCloudUserRecordName: String?
    var latitude: Double?
    var longitude: Double?
    var isCurrentUser: Bool
    var inviteStatus: String

    init(
        id: UUID = UUID(),
        name: String,
        nickname: String = "",
        email: String,
        phoneNumber: String,
        role: String,
        dateAdded: Date = Date(),
        profileImageURL: String? = nil,
        iCloudUserRecordName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isCurrentUser: Bool = false,
        inviteStatus: String = "Accepted"
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.email = email
        self.phoneNumber = phoneNumber
        self.role = role
        self.dateAdded = dateAdded
        self.profileImageURL = profileImageURL
        self.iCloudUserRecordName = iCloudUserRecordName
        self.latitude = latitude
        self.longitude = longitude
        self.isCurrentUser = isCurrentUser
        self.inviteStatus = inviteStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        email = try c.decode(String.self, forKey: .email)
        phoneNumber = try c.decode(String.self, forKey: .phoneNumber)
        profileImageURL = try c.decodeIfPresent(String.self, forKey: .profileImageURL)
        role = try c.decode(String.self, forKey: .role)
        dateAdded = try c.decode(Date.self, forKey: .dateAdded)
        iCloudUserRecordName = try c.decodeIfPresent(String.self, forKey: .iCloudUserRecordName)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        isCurrentUser = try c.decodeIfPresent(Bool.self, forKey: .isCurrentUser) ?? false
        inviteStatus = try c.decodeIfPresent(String.self, forKey: .inviteStatus) ?? "Accepted"
    }

    var firstName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    var displayName: String {
        let nick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return nick.isEmpty ? firstName : nick
    }

    var initials: String {
        let base = displayName
        let parts = base.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(base.prefix(2)).uppercased()
    }

    var coordinateAvailable: Bool {
        latitude != nil && longitude != nil
    }

    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["name"] = name
        record["nickname"] = nickname
        record["email"] = email
        record["phoneNumber"] = phoneNumber
        record["profileImageURL"] = profileImageURL
        if let photoURL = MemberPhotoStore.fileURL(for: id), FileManager.default.fileExists(atPath: photoURL.path) {
            record["profilePhoto"] = CKAsset(fileURL: photoURL)
        }
        record["role"] = role
        record["dateAdded"] = dateAdded
        record["iCloudUserRecordName"] = iCloudUserRecordName
        if let latitude { record["latitude"] = latitude }
        if let longitude { record["longitude"] = longitude }
        record["isCurrentUser"] = isCurrentUser
        record["inviteStatus"] = inviteStatus
        return record
    }

    static let recordType = "FamilyMember"

    static func fromCKRecord(_ record: CKRecord) -> FamilyMember? {
        guard let name = record["name"] as? String else { return nil }
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        let member = FamilyMember(
            id: id,
            name: name,
            nickname: record["nickname"] as? String ?? "",
            email: record["email"] as? String ?? "",
            phoneNumber: record["phoneNumber"] as? String ?? "",
            role: record["role"] as? String ?? "Family",
            dateAdded: record["dateAdded"] as? Date ?? Date(),
            profileImageURL: record["profileImageURL"] as? String,
            iCloudUserRecordName: record["iCloudUserRecordName"] as? String,
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            isCurrentUser: record["isCurrentUser"] as? Bool ?? false,
            inviteStatus: record["inviteStatus"] as? String ?? "Accepted"
        )
        if let asset = record["profilePhoto"] as? CKAsset, let url = asset.fileURL {
            MemberPhotoStore.save(from: url, memberID: id)
        }
        return member
    }
}

enum MemberPhotoStore {
    static func fileURL(for id: UUID) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FamilyConnect", isDirectory: true)
            .appendingPathComponent("member-\(id.uuidString).jpg")
    }

    static func image(for id: UUID) -> UIImage? {
        guard let url = fileURL(for: id), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(image: UIImage, memberID: UUID) {
        guard let url = preparedURL(for: memberID) else { return }
        let resized = resized(image, maxLength: 400)
        guard let data = resized.jpegData(compressionQuality: 0.72) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func save(from source: URL, memberID: UUID) {
        guard let url = preparedURL(for: memberID) else { return }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.copyItem(at: source, to: url)
    }

    static func delete(memberID: UUID) {
        if let url = fileURL(for: memberID) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func preparedURL(for id: UUID) -> URL? {
        guard let url = fileURL(for: id) else { return nil }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    private static func resized(_ image: UIImage, maxLength: CGFloat) -> UIImage {
        let longest = Swift.max(image.size.width, image.size.height)
        guard longest > maxLength else { return image }
        let scale = maxLength / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
