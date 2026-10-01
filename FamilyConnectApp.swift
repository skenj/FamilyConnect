import SwiftUI
import CloudKit
import UIKit
import UserNotifications

@main
struct FamilyConnectApp: App {
    @UIApplicationDelegateAdaptor(CloudKitShareDelegate.self) var appDelegate
    @StateObject private var cloudKitService = CloudKitService()

    var body: some Scene {
        WindowGroup {
            RootView()
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
                    UNUserNotificationCenter.current().setBadgeCount(0)
                    Task { await cloudKitService.fetchPendingInvites() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .familyInvitePushReceived)) { _ in
                    Task { await cloudKitService.fetchPendingInvites() }
                }
                .task {
                    await cloudKitService.subscribeToFamilyInvites()
                    await cloudKitService.fetchPendingInvites()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService

    var body: some View {
        Group {
            if !cloudKitService.isSignedIn {
                AuthView()
            } else if !cloudKitService.pendingInvites.isEmpty && cloudKitService.isShareOwner && !cloudKitService.familyMembers.contains(where: { $0.isCurrentUser && $0.inviteStatus == "Accepted" && $0.iCloudUserRecordName != nil }) {
                InviteDecisionView()
            } else {
                ContentView()
            }
        }
    }
}

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
        NotificationCenter.default.post(name: .familyInvitePushReceived, object: nil)
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

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

extension Notification.Name {
    static let familyCloudKitShareAccepted = Notification.Name("familyCloudKitShareAccepted")
    static let familyCloudKitShareFailed = Notification.Name("familyCloudKitShareFailed")
    static let familyInvitePushReceived = Notification.Name("familyInvitePushReceived")
}
struct RootView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService

    var body: some View {
        Group {
            if !cloudKitService.isSignedIn {
                AuthView()
            } else if !cloudKitService.pendingInvites.isEmpty && !cloudKitService.belongsToSomeoneElsesFamily {
                InviteDecisionView()
            } else {
                ContentView()
            }
        }
    }
}
