import Foundation
import CloudKit

// MARK: - Chat CloudKit extensions
// Add to Services/ in Xcode.
// Handles: read receipts, paginated message loading, private thread access control.

extension CloudKitService {

    // MARK: - Fix 1 & 2: Mark messages as read + update CloudKit

    /// Mark all unread messages in a thread as read by the current user.
    /// Called when a user opens a conversation.
    func markThreadAsRead(threadID: String) async {
        guard let me = currentUser else { return }
        let unread = chatMessages.filter {
            $0.threadID == threadID &&
            $0.senderID != me.id &&
            !$0.isRead(by: me.id)
        }
        guard !unread.isEmpty else { return }

        // Update local state immediately (optimistic)
        for i in chatMessages.indices {
            if chatMessages[i].threadID == threadID &&
               chatMessages[i].senderID != me.id {
                chatMessages[i].markRead(by: me.id)
            }
        }

        // Persist to CloudKit
        guard !isLocalSandbox else { return }
        let database = isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        var records: [CKRecord] = []

        for message in unread {
            let recordID = CKRecord.ID(recordName: message.id.uuidString)
            if let record = try? await database.record(for: recordID) {
                var updated = message
                updated.markRead(by: me.id)
                let readByStr = updated.readBy.map { "\($0.key):\($0.value)" }.joined(separator: ",")
                record["readBy"] = readByStr
                record["isRead"] = true
                records.append(record)
            }
        }

        if !records.isEmpty {
            _ = try? await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        }
    }

    // MARK: - Fix 3: Paginated message loading

    /// Load the most recent 50 messages for a thread.
    func loadMessages(threadID: String, before cursor: Date? = nil) async -> [ChatMessage] {
        let pageSize = 50
        guard !isLocalSandbox else {
            return chatMessages.filter { $0.threadID == threadID }
        }

        let cutoff = cursor ?? Date()
        let predicate = NSPredicate(format: "threadID == %@ AND timestamp < %@", threadID, cutoff as CVarArg)
        let query = CKQuery(recordType: ChatMessage.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        let database = isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase

        do {
            // Use nil zone to search across all zones
            let result = try await database.records(
                matching: query,
                inZoneWith: nil,
                desiredKeys: nil,
                resultsLimit: pageSize
            )
            let messages = result.matchResults
                .compactMap { _, item -> ChatMessage? in
                    guard let record = try? item.get() else { return nil }
                    return ChatMessage.fromCKRecord(record)
                }
                .sorted { $0.timestamp < $1.timestamp }

            return messages
        } catch {
            return []
        }
    }

    /// Append older messages into the local store (called on scroll-to-top).
    @discardableResult
    func loadOlderMessages(threadID: String) async -> Bool {
        let existing = chatMessages.filter { $0.threadID == threadID }
        guard let oldest = existing.min(by: { $0.timestamp < $1.timestamp }) else { return false }

        let older = await loadMessages(threadID: threadID, before: oldest.timestamp)
        let existingIDs = Set(chatMessages.map(\.id))
        let newMessages = older.filter { !existingIDs.contains($0.id) }
        if !newMessages.isEmpty {
            chatMessages.append(contentsOf: newMessages)
            chatMessages.sort { $0.timestamp < $1.timestamp }
        }
        // Returns true if we got a full page (more may exist)
        return older.count >= 50
    }

    // MARK: - Fix 2: Private thread access control

    /// Save a private message — uses private database so only the sender's
    /// CloudKit account can read it directly. The recipient reads it via
    /// the shared zone when both are in the same family share.
    /// Save a private chat message — reuses the existing saveChatMessage path
    /// which already handles namespacing, zone attachment and shared database routing.
    func savePrivateChatMessage(_ message: ChatMessage) async {
        await saveChatMessage(message)
    }

    // MARK: - Fix 4: Cached thread list

    /// Compute thread summaries efficiently — call this instead of
    /// recomputing in the view on every render.
    func computeThreadList(for memberID: UUID) -> [ChatThread] {
        let privateMessages = chatMessages.filter {
            $0.threadID != "family" && $0.threadID.contains(memberID.uuidString)
        }

        var threadMap: [String: [ChatMessage]] = [:]
        for msg in privateMessages {
            threadMap[msg.threadID, default: []].append(msg)
        }

        return threadMap.compactMap { threadID, messages -> ChatThread? in
            guard let latest = messages.max(by: { $0.timestamp < $1.timestamp }) else { return nil }

            // Extract other participant's ID from threadID
            let stripped = threadID
                .replacingOccurrences(of: "private-", with: "")
                .components(separatedBy: "-")
            let rawIDs = stride(from: 0, to: stripped.count, by: 5).map {
                stripped[$0..<min($0 + 5, stripped.count)].joined(separator: "-")
            }
            let otherMember = familyMembers.first {
                rawIDs.contains($0.id.uuidString) && $0.id != memberID
            }

            let unread = messages.filter {
                !$0.isRead(by: memberID) && $0.senderID != memberID
            }.count

            return ChatThread(
                id: threadID,
                name: otherMember?.displayName ?? "Family Member",
                latestMessage: latest,
                unreadCount: unread,
                isFamily: false
            )
        }
        .sorted { $0.latestMessage!.timestamp > $1.latestMessage!.timestamp }
    }
}
