import UIKit
import CloudKit

final class CloudKitShareDelegate: NSObject, UIApplicationDelegate {
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

extension Notification.Name {
    static let familyCloudKitShareAccepted = Notification.Name("familyCloudKitShareAccepted")
    static let familyCloudKitShareFailed = Notification.Name("familyCloudKitShareFailed")
}
