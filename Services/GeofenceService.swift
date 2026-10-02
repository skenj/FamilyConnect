import Foundation
import CoreLocation
import UserNotifications
import Combine

// MARK: - GeofenceService
// Manages CLCircularRegion monitoring for family zones.
// Works in background and when app is killed (iOS handles region events at OS level).
// Add to Services/ in Xcode.

@MainActor
class GeofenceService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = GeofenceService()

    @Published var monitoredZones: [FamilyZone] = []
    @Published var currentZoneIDs: Set<UUID> = [] // zones the user is currently inside
    @Published var error: String?

    private let locationManager = CLLocationManager()
    private var zoneMap: [String: FamilyZone] = [:] // region identifier → zone

    // iOS allows max 20 monitored regions per app
    private let maxRegions = 20

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Setup

    /// Start monitoring all active zones for a family member (child).
    /// Called after zones are fetched from CloudKit.
    func startMonitoring(zones: [FamilyZone]) {
        // Stop existing monitoring first
        stopAllMonitoring()

        let activeZones = zones.filter(\.isActive).prefix(maxRegions)
        for zone in activeZones {
            let region = zone.region
            locationManager.startMonitoring(for: region)
            zoneMap[zone.id.uuidString] = zone
        }
        monitoredZones = Array(activeZones)
        print("✅ Monitoring \(activeZones.count) zones")
    }

    func stopAllMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        zoneMap.removeAll()
        monitoredZones = []
        currentZoneIDs = []
    }

    func stopMonitoring(zone: FamilyZone) {
        let region = zone.region
        locationManager.stopMonitoring(for: region)
        zoneMap.removeValue(forKey: zone.id.uuidString)
        monitoredZones.removeAll { $0.id == zone.id }
    }

    /// Request always-on location authorization (required for background geofencing).
    func requestAlwaysAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // Upgrade to always — iOS will prompt user
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            guard let zone = zoneMap[region.identifier] else { return }
            currentZoneIDs.insert(zone.id)
            await fireGeofenceNotification(zone: zone, event: .enter)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            guard let zone = zoneMap[region.identifier] else { return }
            currentZoneIDs.remove(zone.id)
            await fireGeofenceNotification(zone: zone, event: .leave)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Task { @MainActor in
            self.error = "Zone monitoring error: \(error.localizedDescription)"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                self.error = nil
                print("✅ Always authorization granted — geofencing active")
            case .authorizedWhenInUse:
                self.error = "Enable 'Always' location access for zone alerts when app is closed"
            case .denied, .restricted:
                self.error = "Location access denied — zone alerts won't work"
                stopAllMonitoring()
            default:
                break
            }
        }
    }

    // MARK: - Notifications

    private enum GeofenceEvent { case enter, leave }

    private func fireGeofenceNotification(zone: FamilyZone, event: GeofenceEvent) async {
        // Respect zone's trigger mode
        switch zone.triggerMode {
        case .enter where event == .leave: return
        case .leave where event == .enter: return
        default: break
        }

        let content = UNMutableNotificationContent()
        switch event {
        case .enter:
            content.title = "📍 \(zone.name)"
            content.body  = "Arrived at \(zone.name)."
        case .leave:
            content.title = "🚶 \(zone.name)"
            content.body  = "Left \(zone.name)."
        }
        content.sound = .default
        content.userInfo = [
            "type": "geofence",
            "zoneID": zone.id.uuidString,
            "event": event == .enter ? "enter" : "leave"
        ]

        let request = UNNotificationRequest(
            identifier: "geofence-\(zone.id.uuidString)-\(event == .enter ? "enter" : "leave")",
            content: content,
            trigger: nil // immediate
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - State query

    func isInsideZone(_ zone: FamilyZone) -> Bool {
        currentZoneIDs.contains(zone.id)
    }
}
