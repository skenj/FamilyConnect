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

        // Location subscriptions (role-based)
        if me.isParent {
            await NotificationService.shared.subscribeToLocationRequests(for: me.id)
        } else {
            await NotificationService.shared.subscribeToLocationRequestUpdates(for: me.id)
        }

        // Chat subscriptions (all users)
        await NotificationService.shared.subscribeToFamilyChat()
        await NotificationService.shared.subscribeToPrivateMessages(for: me.id)

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

    // MARK: - Handle incoming chat push

    func handleChatPush(userInfo: [AnyHashable: Any]) async {
        guard let me = currentUser else { return }

        // CloudKit wraps payload under "ck" → "sub" → fields
        // Try both top-level and nested locations
        func field(_ key: String) -> String? {
            if let v = userInfo[key] as? String { return v }
            if let ck = userInfo["ck"] as? [String: Any],
               let fields = ck["sub"] as? [String: Any],
               let v = fields[key] as? String { return v }
            return nil
        }

        let senderName = field("senderName") ?? "Someone"
        let content    = field("content")    ?? "New message"
        let threadID   = field("threadID")   ?? "family"
        let senderID   = field("senderID")   ?? ""

        // Don't notify for your own messages
        guard senderID != me.id.uuidString else { return }

        // Fetch latest messages to update app state
        await refreshAll()

        // Fire local notification — shows as banner when app is background/foreground
        // When phone is locked, the CloudKit push payload itself shows the banner
        // (configured via NotificationInfo.alertLocalizationKey in the subscription)
        // This local notification is the fallback for when app is in background but open
        if threadID == "family" {
            NotificationService.shared.notifyNewFamilyMessage(
                senderName: senderName,
                content: content
            )
        } else if threadID.contains(me.id.uuidString) {
            // Only notify if this DM is for me
            NotificationService.shared.notifyNewPrivateMessage(
                senderName: senderName,
                content: content,
                threadID: threadID
            )
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
