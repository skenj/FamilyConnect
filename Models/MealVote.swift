import Foundation
import CloudKit

struct MealVote: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var requestedByID: UUID
    var requestedByName: String
    var voterIDs: [UUID]
    var isOpen: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        requestedByID: UUID,
        requestedByName: String,
        voterIDs: [UUID] = [],
        isOpen: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.requestedByID = requestedByID
        self.requestedByName = requestedByName
        self.voterIDs = voterIDs
        self.isOpen = isOpen
        self.createdAt = createdAt
    }

    var voteCount: Int { voterIDs.count }

    static let recordType = "MealVote"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["title"] = title
        record["requestedByID"] = requestedByID.uuidString
        record["requestedByName"] = requestedByName
        record["voterIDs"] = voterIDs.map(\.uuidString)
        record["isOpen"] = isOpen
        record["createdAt"] = createdAt
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> MealVote? {
        guard let title = record["title"] as? String else { return nil }
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        let requestedByID = (record["requestedByID"] as? String).flatMap(UUID.init) ?? UUID()
        let voterStrings = record["voterIDs"] as? [String] ?? []
        return MealVote(
            id: id,
            title: title,
            requestedByID: requestedByID,
            requestedByName: record["requestedByName"] as? String ?? "",
            voterIDs: voterStrings.compactMap(UUID.init),
            isOpen: record["isOpen"] as? Bool ?? true,
            createdAt: record["createdAt"] as? Date ?? Date()
        )
    }
}
