import Foundation
import CloudKit

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var content: String
    var senderID: UUID
    var senderName: String
    var timestamp: Date
    var isRead: Bool
    /// "all" notifies every family member except the sender. "mention" notifies only @tagged members.
    var notifyScope: String
    var mentionedIDs: [UUID]

    init(
        id: UUID = UUID(),
        content: String,
        senderID: UUID,
        senderName: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        notifyScope: String = "all",
        mentionedIDs: [UUID] = []
    ) {
        self.id = id
        self.content = content
        self.senderID = senderID
        self.senderName = senderName
        self.timestamp = timestamp
        self.isRead = isRead
        self.notifyScope = notifyScope
        self.mentionedIDs = mentionedIDs
    }

    static let recordType = "ChatMessage"

    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["content"] = content
        record["senderID"] = senderID.uuidString
        record["senderName"] = senderName
        record["timestamp"] = timestamp
        record["isRead"] = isRead
        record["notifyScope"] = notifyScope
        record["mentionedIDs"] = mentionedIDs.map(\.uuidString).joined(separator: ",")
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> ChatMessage? {
        guard
            let content = record["content"] as? String,
            let senderName = record["senderName"] as? String
        else { return nil }

        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        let senderID = UUID(uuidString: record["senderID"] as? String ?? "") ?? UUID()
        let mentioned = (record["mentionedIDs"] as? String ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        return ChatMessage(
            id: id,
            content: content,
            senderID: senderID,
            senderName: senderName,
            timestamp: record["timestamp"] as? Date ?? Date(),
            isRead: record["isRead"] as? Bool ?? false,
            notifyScope: record["notifyScope"] as? String ?? (mentioned.isEmpty ? "all" : "mention"),
            mentionedIDs: mentioned
        )
    }

    static func mentionedMembers(in text: String, members: [FamilyMember]) -> [FamilyMember] {
        let sorted = members.sorted { $0.name.count > $1.name.count }
        var hits: [FamilyMember] = []
        for member in sorted where !member.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let needle = "@\(member.name)"
            if text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                hits.append(member)
            }
        }
        return hits
    }

    func shouldNotify(userID: UUID?) -> Bool {
        guard let userID, userID != senderID else { return false }
        if notifyScope == "mention" || !mentionedIDs.isEmpty {
            return mentionedIDs.contains(userID)
        }
        return true
    }
}
