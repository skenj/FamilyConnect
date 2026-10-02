import Foundation
import CloudKit

struct LocationRequest: Identifiable, Codable {
    let id: UUID
    var requestingChildID: UUID
    var requestingChildName: String
    var approvingParentID: UUID
    var approvingParentName: String
    var status: RequestStatus
    var requestedDate: Date
    var approvedDate: Date?
    var expirationDate: Date?
    var durationMinutes: Int

    enum RequestStatus: String, Codable {
        case pending = "pending"
        case approved = "approved"
        case expired = "expired"
        case denied = "denied"
    }

    init(requestingChildID: UUID, requestingChildName: String, approvingParentID: UUID, approvingParentName: String) {
        self.id = UUID()
        self.requestingChildID = requestingChildID
        self.requestingChildName = requestingChildName
        self.approvingParentID = approvingParentID
        self.approvingParentName = approvingParentName
        self.status = .pending
        self.requestedDate = Date()
        self.approvedDate = nil
        self.expirationDate = nil
        self.durationMinutes = 60
    }

    mutating func approve(for durationMinutes: Int) {
        guard durationMinutes >= 1 && durationMinutes <= 120 else { return }
        self.status = .approved
        self.approvedDate = Date()
        self.durationMinutes = durationMinutes
        self.expirationDate = Date().addingTimeInterval(Double(durationMinutes * 60))
    }

    mutating func deny() {
        self.status = .denied
    }

    mutating func checkExpiration() {
        if status == .approved, let expiration = expirationDate, Date() > expiration {
            self.status = .expired
        }
    }

    var isActive: Bool {
        if status == .approved, let expiration = expirationDate {
            return Date() <= expiration
        }
        return false
    }

    var timeRemaining: String {
        guard isActive, let expiration = expirationDate else { return "Expired" }
        let remaining = expiration.timeIntervalSince(Date())
        if remaining <= 0 { return "Expired" }
        let minutes = Int(remaining / 60)
        let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "LocationRequest", recordID: CKRecord.ID(recordName: id.uuidString))
        record["requestingChildID"] = requestingChildID.uuidString
        record["requestingChildName"] = requestingChildName
        record["approvingParentID"] = approvingParentID.uuidString
        record["approvingParentName"] = approvingParentName
        record["status"] = status.rawValue
        record["requestedDate"] = requestedDate
        record["approvedDate"] = approvedDate
        record["expirationDate"] = expirationDate
        record["durationMinutes"] = durationMinutes
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> LocationRequest? {
        guard
            let childIDString = record["requestingChildID"] as? String,
            let childID = UUID(uuidString: childIDString),
            let childName = record["requestingChildName"] as? String,
            let parentIDString = record["approvingParentID"] as? String,
            let parentID = UUID(uuidString: parentIDString),
            let parentName = record["approvingParentName"] as? String
        else { return nil }

        var request = LocationRequest(
            requestingChildID: childID,
            requestingChildName: childName,
            approvingParentID: parentID,
            approvingParentName: parentName
        )
        request.status = RequestStatus(rawValue: record["status"] as? String ?? "pending") ?? .pending
        request.requestedDate = record["requestedDate"] as? Date ?? Date()
        request.approvedDate = record["approvedDate"] as? Date
        request.expirationDate = record["expirationDate"] as? Date
        request.durationMinutes = record["durationMinutes"] as? Int ?? 60
        return request
    }
}
