//
//  ChatMessage.swift
//  FamilyConnect
//
//  Created by Nick Skewes on 16/9/2026.
//


import Foundation
import CloudKit

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var content: String
    var senderID: UUID // FamilyMember ID
    var senderName: String
    var timestamp: Date
    var isRead: Bool = false
    
    init(content: String, senderID: UUID, senderName: String) {
        self.id = UUID()
        self.content = content
        self.senderID = senderID
        self.senderName = senderName
        self.timestamp = Date()
    }
    
    // Convert to CloudKit CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "ChatMessage")
        record["content"] = content
        record["senderID"] = senderID.uuidString
        record["senderName"] = senderName
        record["timestamp"] = timestamp
        record["isRead"] = isRead
        return record
    }
}