//
//  CloudKitService.swift
//  FamilyConnect
//
//  Created by Nick Skewes on 16/9/2026.
//


import Foundation
import CloudKit
import Combine

class CloudKitService: NSObject, ObservableObject {
    @Published var familyMembers: [FamilyMember] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let container = CKContainer.default()
    
    override init() {
        super.init()
        checkCloudKitAvailability()
    }
    
    func checkCloudKitAvailability() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("CloudKit is available")
                case .noAccount:
                    self?.error = "No iCloud account signed in"
                case .restricted:
                    self?.error = "CloudKit is restricted"
                case .couldNotDetermine:
                    self?.error = "Could not determine CloudKit status"
                case .temporarilyUnavailable:
                    self?.error = "CloudKit temporarily unavailable"
                @unknown default:
                    self?.error = "Unknown CloudKit status"
                }
            }
        }
    }
    
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
    
    func saveCalendarEvent(_ event: CalendarEvent) {
        isLoading = true
        let record = event.toCKRecord()
        
        container.privateCloudDatabase.save(record) { [weak self] record, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.error = "Failed to save event: \(error.localizedDescription)"
                } else {
                    self?.calendarEvents.append(event)
                }
            }
        }
    }
    
    func saveChatMessage(_ message: ChatMessage) {
        isLoading = true
        let record = message.toCKRecord()
        
        container.privateCloudDatabase.save(record) { [weak self] record, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.error = "Failed to save message: \(error.localizedDescription)"
                } else {
                    self?.chatMessages.append(message)
                }
            }
        }
    }
}
