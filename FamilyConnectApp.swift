import SwiftUI
import CloudKit
import UIKit
import UserNotifications
import AuthenticationServices

// MARK: - FamilyConnectApp
// Updated to handle silent push notifications for location requests.

@main
struct FamilyConnectApp: App {
    @UIApplicationDelegateAdaptor(CloudKitShareDelegate.self) var appDelegate
    @StateObject private var cloudKitService = CloudKitService()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(cloudKitService)
                .onOpenURL { url in
                    Task { await cloudKitService.acceptShare(from: url) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .familyCloudKitShareAccepted)) { _ in
                    Task { await cloudKitService.finishJoiningShare() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .familyCloudKitShareFailed)) { note in
                    if let text = note.object as? String {
                        cloudKitService.error = text
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    NotificationService.shared.clearBadge()
                    Task {
                        await cloudKitService.fetchPendingInvites()
                        await cloudKitService.validateAppleCredentialState()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .familyInvitePushReceived)) { _ in
                    Task { await cloudKitService.fetchPendingInvites() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .locationRequestPushReceived)) { note in
                    Task {
                        let userInfo = note.userInfo as? [AnyHashable: Any] ?? [:]
                        await cloudKitService.handleLocationRequestPush(userInfo: userInfo)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .chatMessagePushReceived)) { note in
                    Task {
                        let userInfo = note.userInfo as? [AnyHashable: Any] ?? [:]
                        await cloudKitService.handleChatPush(userInfo: userInfo)
                    }
                }
                .task {
                    await cloudKitService.validateAppleCredentialState()
                    await cloudKitService.subscribeToFamilyInvites()
                    await cloudKitService.fetchPendingInvites()
                    // Bootstrap notifications after sign-in state is known
                    if cloudKitService.isSignedIn {
                        await cloudKitService.bootstrapNotifications()
                    }
                }
                .onChange(of: cloudKitService.isSignedIn) {
                    if cloudKitService.isSignedIn {
                        Task { await cloudKitService.bootstrapNotifications() }
                    }
                }
        }
    }
}

struct AppRootView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService

    var body: some View {
        Group {
            if !cloudKitService.isSignedIn {
                AuthView()
            } else if !cloudKitService.pendingInvites.isEmpty &&
                      cloudKitService.isShareOwner &&
                      !cloudKitService.familyMembers.contains(where: {
                          $0.isCurrentUser &&
                          $0.inviteStatus == "Accepted" &&
                          $0.iCloudUserRecordName != nil
                      }) {
                InviteDecisionView()
            } else {
                ContentView()
            }
        }
    }
}

// MARK: - App Delegate (handles push + CloudKit share)

final class CloudKitShareDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Decode which CloudKit subscription fired
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            switch ckNotification.subscriptionID {
            case let id where id?.hasPrefix("location-request") == true:
                // Location request push
                NotificationCenter.default.post(
                    name: .locationRequestPushReceived,
                    object: nil,
                    userInfo: userInfo
                )
            case let id where id == "family-chat-messages" || id?.hasPrefix("private-chat-") == true:
                // Chat message push
                NotificationCenter.default.post(
                    name: .chatMessagePushReceived,
                    object: nil,
                    userInfo: userInfo
                )
            default:
                // Family invite push
                NotificationCenter.default.post(name: .familyInvitePushReceived, object: nil)
            }
        } else {
            NotificationCenter.default.post(name: .familyInvitePushReceived, object: nil)
        }
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            do {
                let container = CKContainer(identifier: "iCloud.com.personal.FamilyConnect")
                _ = try await container.accept(cloudKitShareMetadata)
                NotificationCenter.default.post(name: .familyCloudKitShareAccepted, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .familyCloudKitShareFailed,
                    object: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - Notification Delegate (foreground display)

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Handle tapping a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? ""

        switch type {
        case "location_approved", "location_expiry_warning", "location_expired":
            NotificationCenter.default.post(name: .navigateToLocation, object: nil)
        case "location_denied":
            NotificationCenter.default.post(name: .navigateToLocation, object: nil)
        case "private_message", "family_message":
            // Tapping a chat notification opens Chat tab
            NotificationCenter.default.post(name: .navigateToChat, object: nil)
        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let familyCloudKitShareAccepted = Notification.Name("familyCloudKitShareAccepted")
    static let familyCloudKitShareFailed   = Notification.Name("familyCloudKitShareFailed")
    static let familyInvitePushReceived    = Notification.Name("familyInvitePushReceived")
    static let locationRequestPushReceived = Notification.Name("locationRequestPushReceived")
    static let navigateToLocation          = Notification.Name("navigateToLocation")
    static let navigateToChat              = Notification.Name("navigateToChat")
    static let chatMessagePushReceived     = Notification.Name("chatMessagePushReceived")
}
