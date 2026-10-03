import Foundation
import CloudKit
import CryptoKit

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var content: String
    var senderID: UUID
    var senderName: String
    var timestamp: Date
    var isRead: Bool
    var notifyScope: String
    var mentionedIDs: [UUID]
    /// "family" = family group chat. "private-<uuid>-<uuid>" = private thread.
    var threadID: String
    /// Per-user read receipts: maps userID.uuidString → ISO8601 date string
    var readBy: [String: String]

    init(
        id: UUID = UUID(),
        content: String,
        senderID: UUID,
        senderName: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        notifyScope: String = "all",
        mentionedIDs: [UUID] = [],
        threadID: String = "family",
        readBy: [String: String] = [:]
    ) {
        self.id = id
        self.content = content
        self.senderID = senderID
        self.senderName = senderName
        self.timestamp = timestamp
        self.isRead = isRead
        self.notifyScope = notifyScope
        self.mentionedIDs = mentionedIDs
        self.threadID = threadID
        self.readBy = readBy
    }

    static let recordType = "ChatMessage"

    // MARK: - Read receipts

    /// Mark this message as read by a user
    mutating func markRead(by userID: UUID) {
        readBy[userID.uuidString] = ISO8601DateFormatter().string(from: Date())
        if userID == senderID { isRead = true }
    }

    /// Check if a specific user has read this message
    func isRead(by userID: UUID) -> Bool {
        readBy[userID.uuidString] != nil
    }

    /// Receipt status for sender's UI (✓ sent, ✓✓ read by all participants)
    func receiptStatus(participants: [UUID]) -> ReceiptStatus {
        let others = participants.filter { $0 != senderID }
        if others.isEmpty { return .sent }
        let allRead = others.allSatisfy { isRead(by: $0) }
        let anyRead = others.contains { isRead(by: $0) }
        if allRead { return .readAll }
        if anyRead { return .readSome }
        return .sent
    }

    enum ReceiptStatus {
        case sent       // ✓  grey
        case readSome   // ✓✓ grey
        case readAll    // ✓✓ blue
    }

    // MARK: - CloudKit

    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["content"]      = content
        record["senderID"]     = senderID.uuidString
        record["senderName"]   = senderName
        record["timestamp"]    = timestamp
        record["isRead"]       = isRead
        record["notifyScope"]  = notifyScope
        record["mentionedIDs"] = mentionedIDs.map(\.uuidString).joined(separator: ",")
        record["threadID"]     = threadID
        // Encode readBy as "uuid1:date1,uuid2:date2"
        record["readBy"]       = readBy.map { "\($0.key):\($0.value)" }.joined(separator: ",")
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> ChatMessage? {
        guard
            let content    = record["content"]    as? String,
            let senderName = record["senderName"] as? String
        else { return nil }

        let id       = UUID(uuidString: record.recordID.recordName) ?? UUID()
        let senderID = UUID(uuidString: record["senderID"] as? String ?? "") ?? UUID()

        let mentioned: [UUID]
        if let list = record["mentionedIDs"] as? [String] {
            mentioned = list.compactMap(UUID.init)
        } else {
            mentioned = (record["mentionedIDs"] as? String ?? "")
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        }

        // Decode readBy
        var readBy: [String: String] = [:]
        if let raw = record["readBy"] as? String, !raw.isEmpty {
            for pair in raw.split(separator: ",") {
                let parts = pair.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    readBy[String(parts[0])] = String(parts[1])
                }
            }
        }

        return ChatMessage(
            id: id,
            content: content,
            senderID: senderID,
            senderName: senderName,
            timestamp: record["timestamp"] as? Date ?? Date(),
            isRead: record["isRead"] as? Bool ?? false,
            notifyScope: record["notifyScope"] as? String ?? (mentioned.isEmpty ? "all" : "mention"),
            mentionedIDs: mentioned,
            threadID: record["threadID"] as? String ?? "family",
            readBy: readBy
        )
    }

    // MARK: - Thread helpers

    /// Stable private thread ID - same regardless of who initiates
    static func privateThreadID(between id1: UUID, and id2: UUID) -> String {
        let sorted = [id1.uuidString, id2.uuidString].sorted()
        return "private-\(sorted[0])-\(sorted[1])"
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
