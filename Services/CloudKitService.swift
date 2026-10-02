import Foundation
import CloudKit
import Combine

class CloudKitService: NSObject, ObservableObject {
    @Published var familyMembers: [FamilyMember] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var locationRequests: [LocationRequest] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let container = CKContainer.default()
    private var locationUpdateTimer: Timer?
    
    override init() {
        super.init()
        #if !DEBUG
        checkCloudKitAvailability()
        #else
        if !ProcessInfo.processInfo.environment.keys.contains("XCODE_RUNNING_FOR_PREVIEWS") {
            checkCloudKitAvailability()
        }
        #endif
    }
    
    func checkCloudKitAvailability() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available: print("CloudKit is available")
                case .noAccount: self?.error = "No iCloud account signed in"
                case .restricted: self?.error = "CloudKit is restricted"
                case .couldNotDetermine: self?.error = "Could not determine CloudKit status"
                case .temporarilyUnavailable: self?.error = "CloudKit temporarily unavailable"
                @unknown default: self?.error = "Unknown CloudKit status"
                }
            }
        }
    }
    
    // MARK: - Family Member Management
    
    func saveFamilyMember(_ member: FamilyMember) {
        isLoading = true
        let record = member.toCKRecord()
        container.privateCloudDatabase.save(record) { [weak self] record, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error { 
                    self?.error = "Failed to save family member: \(error.localizedDescription)" 
                } else { 
                    self?.familyMembers.append(member)
                }
            }
        }
    }
    
    // MARK: - Location Management
    
    func updateMemberLocation(memberID: UUID, latitude: Double, longitude: Double) {
        isLoading = true
        let predicate = NSPredicate(format: "id = %@", memberID.uuidString)
        let query = CKQuery(recordType: "FamilyMember", predicate: predicate)
        
        container.privateCloudDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            guard let record = records?.first else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.error = "Member not found"
                }
                return
            }
            
            record["latitude"] = NSNumber(value: latitude)
            record["longitude"] = NSNumber(value: longitude)
            record["lastLocationUpdate"] = Date()
            
            self?.container.privateCloudDatabase.save(record) { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        self?.error = "Failed to update location: \(error.localizedDescription)"
                    } else {
                        // Update local member
                        if let index = self?.familyMembers.firstIndex(where: { $0.id == memberID }) {
                            self?.familyMembers[index].updateLocation(latitude: latitude, longitude: longitude)
                        }
                    }
                }
            }
        }
    }
    
    func startLocationUpdates(for memberID: UUID) {
        // Update location every 5 minutes
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            // This will be triggered by the LocationManager when location changes
            // The actual update happens when LocationView calls updateMemberLocation
        }
    }
    
    func stopLocationUpdates() {
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    // MARK: - Location Request Management
    
    func createLocationRequest(from childID: UUID, childName: String, to parentID: UUID, parentName: String) {
        isLoading = true
        var request = LocationRequest(requestingChildID: childID, requestingChildName: childName, approvingParentID: parentID, approvingParentName: parentName)
        let record = request.toCKRecord()
        
        container.privateCloudDatabase.save(record) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.error = "Failed to create location request: \(error.localizedDescription)"
                } else {
                    self?.locationRequests.append(request)
                }
            }
        }
    }
    
    func fetchPendingLocationRequests(for parentID: UUID) {
        isLoading = true
        let predicate = NSPredicate(format: "approvingParentID = %@ AND status = %@", parentID.uuidString, LocationRequest.RequestStatus.pending.rawValue)
        let query = CKQuery(recordType: "LocationRequest", predicate: predicate)
        
        container.privateCloudDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.error = "Failed to fetch requests: \(error.localizedDescription)"
                    return
                }
                
                let requests = records?.compactMap { record -> LocationRequest? in
                    guard let childID = UUID(uuidString: record["requestingChildID"] as? String ?? ""),
                          let parentID = UUID(uuidString: record["approvingParentID"] as? String ?? "") else { return nil }
                    
                    var req = LocationRequest(requestingChildID: childID, requestingChildName: record["requestingChildName"] as? String ?? "", approvingParentID: parentID, approvingParentName: record["approvingParentName"] as? String ?? "")
                    req.status = LocationRequest.RequestStatus(rawValue: record["status"] as? String ?? "pending") ?? .pending
                    req.requestedDate = record["requestedDate"] as? Date ?? Date()
                    req.approvedDate = record["approvedDate"] as? Date
                    req.expirationDate = record["expirationDate"] as? Date
                    req.durationMinutes = record["durationMinutes"] as? Int ?? 60
                    return req
                } ?? []
                
                self?.locationRequests = requests
            }
        }
    }
    
    func approveLocationRequest(requestID: UUID, for durationMinutes: Int) {
        guard durationMinutes >= 1 && durationMinutes <= 120 else { return }
        
        isLoading = true
        let predicate = NSPredicate(format: "id = %@", requestID.uuidString)
        let query = CKQuery(recordType: "LocationRequest", predicate: predicate)
        
        container.privateCloudDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            guard let record = records?.first else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.error = "Request not found"
                }
                return
            }
            
            record["status"] = LocationRequest.RequestStatus.approved.rawValue
            record["approvedDate"] = Date()
            record["expirationDate"] = Date().addingTimeInterval(Double(durationMinutes * 60))
            record["durationMinutes"] = durationMinutes
            
            self?.container.privateCloudDatabase.save(record) { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        self?.error = "Failed to approve request: \(error.localizedDescription)"
                    } else {
                        // Update local request
                        if let index = self?.locationRequests.firstIndex(where: { $0.id == requestID }) {
                            self?.locationRequests[index].approve(for: durationMinutes)
                        }
                    }
                }
            }
        }
    }
    
    func denyLocationRequest(requestID: UUID) {
        isLoading = true
        let predicate = NSPredicate(format: "id = %@", requestID.uuidString)
        let query = CKQuery(recordType: "LocationRequest", predicate: predicate)
        
        container.privateCloudDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            guard let record = records?.first else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.error = "Request not found"
                }
                return
            }
            
            record["status"] = LocationRequest.RequestStatus.denied.rawValue
            
            self?.container.privateCloudDatabase.save(record) { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        self?.error = "Failed to deny request: \(error.localizedDescription)"
                    } else {
                        if let index = self?.locationRequests.firstIndex(where: { $0.id == requestID }) {
                            self?.locationRequests[index].deny()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Calendar Events
    
    func saveCalendarEvent(_ event: CalendarEvent) {
        isLoading = true
        let record = event.toCKRecord()
        container.privateCloudDatabase.save(record) { [weak self] record, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error { self?.error = "Failed to save event: \(error.localizedDescription)" }
                else { self?.calendarEvents.append(event) }
            }
        }
    }
    
    // MARK: - Chat Messages
    
    func saveChatMessage(_ message: ChatMessage) {
        isLoading = true
        let record = message.toCKRecord()
        container.privateCloudDatabase.save(record) { [weak self] record, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error { self?.error = "Failed to save message: \(error.localizedDescription)" }
                else { self?.chatMessages.append(message) }
            }
        }
    }
}
