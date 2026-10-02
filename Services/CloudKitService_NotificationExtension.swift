import Foundation
import CloudKit
import UserNotifications

// MARK: - Notification-aware CloudKit operations
// Drop this file into Services/ alongside CloudKitService_AuthExtension.swift

extension CloudKitService {

    // MARK: - Bootstrap notifications

    func bootstrapNotifications() async {
        guard let me = currentUser else { return }
        let granted = await NotificationService.shared.requestPermission()
        guard granted else { return }

        if me.isParent {
            await NotificationService.shared.subscribeToLocationRequests(for: me.id)
        } else {
            await NotificationService.shared.subscribeToLocationRequestUpdates(for: me.id)
        }
        await rescheduleActiveLocationTimers()
    }

    func rescheduleActiveLocationTimers() async {
        guard let me = currentUser else { return }
        for request in locationRequests where request.isActive {
            guard let expiry = request.expirationDate,
                  request.requestingChildID == me.id else { continue }
            NotificationService.shared.scheduleLocationExpiryWarning(
                requestID: request.id,
                expirationDate: expiry,
                parentName: request.approvingParentName
            )
            NotificationService.shared.scheduleLocationExpiredNotification(
                requestID: request.id,
                expirationDate: expiry,
                parentName: request.approvingParentName
            )
        }
    }

    // MARK: - Approve with notification

    func approveLocationRequestWithNotification(requestID: UUID, for durationMinutes: Int) async {
        guard durationMinutes >= 1 && durationMinutes <= 120 else { return }
        guard let index = locationRequests.firstIndex(where: { $0.id == requestID }) else { return }

        locationRequests[index].approve(for: durationMinutes)
        let request = locationRequests[index]

        // Use the existing public approveLocationRequest which handles CloudKit save
        await approveLocationRequest(requestID: requestID, for: durationMinutes)

        // Schedule expiry notification on parent's device
        if let expiry = request.expirationDate {
            NotificationService.shared.scheduleLocationExpiryWarning(
                requestID: request.id,
                expirationDate: expiry,
                parentName: request.approvingParentName
            )
        }
    }

    // MARK: - Deny with notification

    func denyLocationRequestWithNotification(requestID: UUID) async {
        // Use the existing public denyLocationRequest which handles CloudKit save
        await denyLocationRequest(requestID: requestID)
        NotificationService.shared.cancelAllLocationNotifications(requestID: requestID)
    }

    // MARK: - Handle incoming CloudKit push

    func handleLocationRequestPush(userInfo: [AnyHashable: Any]) async {
        guard let me = currentUser else { return }
        if me.isParent {
            await fetchPendingLocationRequests(for: me.id)
        } else {
            await fetchAndProcessChildLocationUpdates(for: me.id)
        }
    }

    func fetchAndProcessChildLocationUpdates(for childID: UUID) async {
        guard !isLocalSandbox else { return }

        let predicate = NSPredicate(format: "requestingChildID == %@", childID.uuidString)
        let query = CKQuery(recordType: "LocationRequest", predicate: predicate)

        // Use the public container property instead of private activeDatabase
        let database = isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        guard let result = try? await database.records(matching: query) else { return }

        let fetched = result.matchResults.compactMap { _, item -> LocationRequest? in
            guard let record = try? item.get() else { return nil }
            return LocationRequest.fromCKRecord(record)
        }

        for updated in fetched {
            let existing = locationRequests.first(where: { $0.id == updated.id })

            if existing?.status == .pending && updated.status == .approved {
                NotificationService.shared.notifyChildOfApproval(
                    requestID: updated.id,
                    durationMinutes: updated.durationMinutes,
                    parentName: updated.approvingParentName
                )
                if let expiry = updated.expirationDate {
                    NotificationService.shared.scheduleLocationExpiryWarning(
                        requestID: updated.id,
                        expirationDate: expiry,
                        parentName: updated.approvingParentName
                    )
                    NotificationService.shared.scheduleLocationExpiredNotification(
                        requestID: updated.id,
                        expirationDate: expiry,
                        parentName: updated.approvingParentName
                    )
                }
            }

            if existing?.status == .pending && updated.status == .denied {
                NotificationService.shared.notifyChildOfDenial(
                    requestID: updated.id,
                    parentName: updated.approvingParentName
                )
            }

            if let index = locationRequests.firstIndex(where: { $0.id == updated.id }) {
                locationRequests[index] = updated
            } else {
                locationRequests.append(updated)
            }
        }
    }
}

