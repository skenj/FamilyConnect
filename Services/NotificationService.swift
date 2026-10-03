import Foundation
import UIKit
import UserNotifications
import CloudKit

// MARK: - NotificationService
// Manages all push and local notifications for FamilyConnect.
// Add this file to Services/ in Xcode.

@MainActor
class NotificationService: ObservableObject {

    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()
    private let container = CKContainer(identifier: "iCloud.com.personal.FamilyConnect")

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    func permissionStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - CloudKit Subscriptions (cross-device push)

    /// Subscribe to incoming location requests for a parent.
    /// Triggers when a child creates a LocationRequest targeting this parent.
    func subscribeToLocationRequests(for parentID: UUID) async {
        let predicate = NSPredicate(
            format: "approvingParentID == %@ AND status == %@",
            parentID.uuidString,
            "pending"
        )
        let subscription = CKQuerySubscription(
            recordType: "LocationRequest",
            predicate: predicate,
            subscriptionID: "location-request-parent-\(parentID.uuidString)",
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "%1$@ wants location access"
        info.titleLocalizationArgs = ["requestingChildName"]
        info.alertBody = "Tap to approve or deny in FamilyConnect."
        info.soundName = "default"
        info.shouldBadge = true
        info.shouldSendContentAvailable = true
        info.desiredKeys = ["requestingChildName", "approvingParentID", "status"]
        subscription.notificationInfo = info

        do {
            _ = try await container.privateCloudDatabase.save(subscription)
            print("✅ Subscribed to location requests for parent \(parentID)")
        } catch {
            // Duplicate subscription is fine
            print("Location request subscription: \(error.localizedDescription)")
        }
    }

    /// Subscribe to location request status changes for a child.
    /// Triggers when a parent approves or denies the child's request.
    func subscribeToLocationRequestUpdates(for childID: UUID) async {
        let predicate = NSPredicate(
            format: "requestingChildID == %@",
            childID.uuidString
        )
        let subscription = CKQuerySubscription(
            recordType: "LocationRequest",
            predicate: predicate,
            subscriptionID: "location-request-child-\(childID.uuidString)",
            options: [.firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.desiredKeys = ["status", "requestingChildID", "durationMinutes", "approvingParentName"]
        subscription.notificationInfo = info

        do {
            _ = try await container.privateCloudDatabase.save(subscription)
            print("✅ Subscribed to location request updates for child \(childID)")
        } catch {
            print("Location request update subscription: \(error.localizedDescription)")
        }
    }

    /// Remove all location-related subscriptions (e.g. on sign out)
    func removeLocationSubscriptions(for memberID: UUID) async {
        let ids = [
            "location-request-parent-\(memberID.uuidString)",
            "location-request-child-\(memberID.uuidString)"
        ]
        for id in ids {
            try? await container.privateCloudDatabase.deleteSubscription(withID: id)
        }
    }

    // MARK: - Local Notifications (on-device)

    /// Schedule a local notification warning the child that their location
    /// access is about to expire. Fires 5 minutes before expiry.
    func scheduleLocationExpiryWarning(requestID: UUID, expirationDate: Date, parentName: String) {
        // Cancel any existing warning for this request
        cancelLocationExpiryWarning(requestID: requestID)

        let warningDate = expirationDate.addingTimeInterval(-5 * 60) // 5 min before
        guard warningDate > Date() else { return } // Already too close

        let content = UNMutableNotificationContent()
        content.title = "Location access expiring soon"
        content.body = "Your location access approved by \(parentName) expires in 5 minutes."
        content.sound = .default
        content.userInfo = ["requestID": requestID.uuidString, "type": "location_expiry_warning"]

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: warningDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(
            identifier: "location-expiry-warning-\(requestID.uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error { print("Expiry warning scheduling error: \(error)") }
            else { print("✅ Scheduled expiry warning for \(warningDate)") }
        }
    }

    /// Schedule a local notification when location access actually expires.
    func scheduleLocationExpiredNotification(requestID: UUID, expirationDate: Date, parentName: String) {
        cancelLocationExpiredNotification(requestID: requestID)
        guard expirationDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Location access ended"
        content.body = "Your location access approved by \(parentName) has expired."
        content.sound = .default
        content.userInfo = ["requestID": requestID.uuidString, "type": "location_expired"]

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: expirationDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(
            identifier: "location-expired-\(requestID.uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error { print("Expiry notification scheduling error: \(error)") }
        }
    }

    /// Fire an immediate local notification when a parent approves a request.
    /// Called by the child's device when it receives the CloudKit push.
    func notifyChildOfApproval(requestID: UUID, durationMinutes: Int, parentName: String) {
        let hours = durationMinutes / 60
        let mins = durationMinutes % 60
        let durationText: String
        if hours > 0 && mins > 0 {
            durationText = "\(hours)h \(mins)m"
        } else if hours > 0 {
            durationText = "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            durationText = "\(mins) minutes"
        }

        let content = UNMutableNotificationContent()
        content.title = "Location access approved ✅"
        content.body = "\(parentName) approved your location for \(durationText)."
        content.sound = .default
        content.userInfo = ["requestID": requestID.uuidString, "type": "location_approved"]

        let request = UNNotificationRequest(
            identifier: "location-approved-\(requestID.uuidString)",
            content: content,
            trigger: nil // Immediate
        )
        center.add(request) { error in
            if let error { print("Approval notification error: \(error)") }
        }
    }

    /// Fire an immediate local notification when a parent denies a request.
    func notifyChildOfDenial(requestID: UUID, parentName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Location access denied"
        content.body = "\(parentName) declined your location request."
        content.sound = .default
        content.userInfo = ["requestID": requestID.uuidString, "type": "location_denied"]

        let request = UNNotificationRequest(
            identifier: "location-denied-\(requestID.uuidString)",
            content: content,
            trigger: nil // Immediate
        )
        center.add(request) { error in
            if let error { print("Denial notification error: \(error)") }
        }
    }

    // MARK: - Cancellation

    func cancelLocationExpiryWarning(requestID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "location-expiry-warning-\(requestID.uuidString)"
        ])
    }

    func cancelLocationExpiredNotification(requestID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "location-expired-\(requestID.uuidString)"
        ])
    }

    func cancelAllLocationNotifications(requestID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            "location-expiry-warning-\(requestID.uuidString)",
            "location-expired-\(requestID.uuidString)",
            "location-approved-\(requestID.uuidString)",
            "location-denied-\(requestID.uuidString)"
        ])
    }

    // MARK: - Chat Subscriptions

    /// Subscribe to new messages in the family chat.
    /// Fires a push to all family members when anyone sends a message.
    func subscribeToFamilyChat() async {
        let subscription = CKQuerySubscription(
            recordType: "ChatMessage",
            predicate: NSPredicate(format: "threadID == %@", "family"),
            subscriptionID: "family-chat-messages",
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "%1$@"
        info.titleLocalizationArgs = ["senderName"]
        info.alertBody = "New message in Family Chat"
        info.soundName = "default"
        info.shouldBadge = true
        info.shouldSendContentAvailable = true
        info.desiredKeys = ["senderName", "content", "threadID", "senderID"]
        subscription.notificationInfo = info

        do {
            _ = try await container.sharedCloudDatabase.save(subscription)
            print("✅ Subscribed to family chat messages")
        } catch {
            print("Family chat subscription: \(error.localizedDescription)")
        }
    }

    /// Subscribe to new private messages sent to this user.
    /// Fires a push when someone sends a DM containing your user ID in the threadID.
    func subscribeToPrivateMessages(for userID: UUID) async {
        // CloudKit can't do CONTAINS queries, so we subscribe to all private
        // ChatMessages and filter on receipt. The predicate uses BEGINSWITH
        // to catch both orderings of the thread ID.
        let uuidStr = userID.uuidString

        // Two subscriptions — one for each possible position in the thread ID
        // "private-<myID>-<theirID>" and "private-<theirID>-<myID>"
        let predicate = NSPredicate(
            format: "threadID BEGINSWITH %@ OR threadID ENDSWITH %@",
            "private-\(uuidStr)",
            uuidStr
        )
        let subscription = CKQuerySubscription(
            recordType: "ChatMessage",
            predicate: predicate,
            subscriptionID: "private-chat-\(uuidStr)",
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.shouldBadge = true
        // Alert shown when app is backgrounded/locked
        info.alertLocalizationKey = "%1$@"
        info.alertLocalizationArgs = ["senderName"]
        info.soundName = "default"
        info.desiredKeys = ["senderName", "content", "threadID", "senderID"]
        subscription.notificationInfo = info

        do {
            _ = try await container.sharedCloudDatabase.save(subscription)
            print("✅ Subscribed to private messages for \(uuidStr)")
        } catch {
            print("Private chat subscription: \(error.localizedDescription)")
        }
    }

    /// Remove chat subscriptions (e.g. on sign out)
    func removeChatSubscriptions(for userID: UUID) async {
        let ids = ["family-chat-messages", "private-chat-\(userID.uuidString)"]
        for id in ids {
            try? await container.sharedCloudDatabase.deleteSubscription(withID: id)
        }
    }

    // MARK: - Chat local notifications

    /// Fire a local notification when a private message arrives in background.
    func notifyNewPrivateMessage(senderName: String, content: String, threadID: String) {
        let notifContent = UNMutableNotificationContent()
        notifContent.title = senderName
        notifContent.body = content.count > 80 ? String(content.prefix(80)) + "…" : content
        notifContent.sound = .default
        notifContent.badge = 1
        notifContent.userInfo = [
            "type": "private_message",
            "threadID": threadID,
            "senderName": senderName
        ]

        let request = UNNotificationRequest(
            identifier: "chat-\(threadID)-\(UUID().uuidString)",
            content: notifContent,
            trigger: nil // immediate
        )
        center.add(request) { error in
            if let error { print("Chat notification error: \(error)") }
        }
    }

    /// Fire a local notification for a new family chat message.
    func notifyNewFamilyMessage(senderName: String, content: String) {
        let notifContent = UNMutableNotificationContent()
        notifContent.title = "Family Chat"
        notifContent.body = "\(senderName): \(content.count > 60 ? String(content.prefix(60)) + "…" : content)"
        notifContent.sound = .default
        notifContent.userInfo = [
            "type": "family_message",
            "threadID": "family"
        ]

        let request = UNNotificationRequest(
            identifier: "family-chat-\(UUID().uuidString)",
            content: notifContent,
            trigger: nil
        )
        center.add(request) { error in
            if let error { print("Family chat notification error: \(error)") }
        }
    }

    // MARK: - Badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
