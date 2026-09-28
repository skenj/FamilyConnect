import Foundation

enum RecipeImportRouter {
    static let appGroupID = "group.com.personal.FamilyConnect"
    static let pendingKey = "pendingRecipeURL"

    @MainActor
    static func consume(_ url: URL, into service: CloudKitService) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            let host = url.host?.lowercased() ?? ""
            if host.contains("icloud.com") { return false }
            service.pendingRecipeURL = url.absoluteString
            return true
        }
        guard scheme == "familyconnect" else { return false }
        let host = url.host?.lowercased() ?? ""
        if host == "import" || url.path.lowercased().contains("import") {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            if let raw = items?.first(where: { $0.name == "url" })?.value,
               let decoded = raw.removingPercentEncoding,
               !decoded.isEmpty {
                service.pendingRecipeURL = decoded
            }
            consumePendingSharedURL(into: service)
            return true
        }
        return false
    }

    @MainActor
    static func consumePendingSharedURL(into service: CloudKitService) {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        guard let raw = defaults.string(forKey: pendingKey), !raw.isEmpty else { return }
        defaults.removeObject(forKey: pendingKey)
        service.pendingRecipeURL = raw
    }

    static func storePendingURL(_ value: String) {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.set(value, forKey: pendingKey)
        defaults.synchronize()
    }
}
