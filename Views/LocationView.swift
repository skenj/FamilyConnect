//
//  LocationView.swift
//  FamilyConnect
//

import SwiftUI
import MapKit
import CoreLocation

struct LocationView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var locationManager = LocationManager()
    @State private var position: MapCameraPosition = .automatic
    @State private var showingSettings = false

    private var membersWithCoordinates: [FamilyMember] {
        cloudKitService.familyMembers.filter(\.coordinateAvailable)
    }

    var body: some View {
        NavigationStack {
            VStack {
                Map(position: $position) {
                    ForEach(membersWithCoordinates) { member in
                        if let lat = member.latitude, let lon = member.longitude {
                            Annotation(member.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                                VStack {
                                    Image(systemName: member.isCurrentUser ? "location.circle.fill" : "person.crop.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(member.isCurrentUser ? .blue : .red)
                                    Text(member.name)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading) {
                    HStack {
                        Text("Family Members")
                            .font(.headline)
                        Spacer()
                        Button("Share my location") {
                            Task { await publishMyLocation() }
                        }
                        .font(.caption)
                        .disabled(locationManager.lastLocation == nil)
                    }
                    .padding(.horizontal)

                    if cloudKitService.familyMembers.isEmpty {
                        Text("Add family members to see them here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    List(cloudKitService.familyMembers) { member in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                    .font(.headline)
                                Text(member.coordinateAvailable ? member.role : "\(member.role) · location off")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: member.coordinateAvailable ? "location.fill" : "location.slash")
                                .font(.caption)
                                .foregroundStyle(member.coordinateAvailable ? .green : .secondary)
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 150)
                }
            }
            .navigationTitle("Family Locations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                LocationSettingsSheet(isPresented: $showingSettings, locationManager: locationManager)
            }
            .onAppear {
                locationManager.requestPermission()
            }
        }
    }

    private func publishMyLocation() async {
        guard let loc = locationManager.lastLocation else { return }
        await cloudKitService.updateMemberLocation(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude
        )
    }
}

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var lastLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocation = location
        }
    }
}

struct LocationSettingsSheet: View {
    @Binding var isPresented: Bool
    var locationManager: LocationManager
    @State private var shareLocationEnabled = true
    @State private var updateFrequency = "5min"

    var body: some View {
        NavigationStack {
            Form {
                Section("Location Sharing") {
                    Toggle("Share My Location", isOn: $shareLocationEnabled)
                    LabeledContent("Permission") {
                        Text(permissionLabel)
                    }
                }

                Section("Update Frequency") {
                    Picker("How often to update", selection: $updateFrequency) {
                        Text("Real-time").tag("real-time")
                        Text("Every minute").tag("1min")
                        Text("Every 5 minutes").tag("5min")
                        Text("Every 30 minutes").tag("30min")
                    }
                }

                Section {
                    Text("Location is only written to iCloud when you tap Share my location. Other family members will not see it until CloudKit sharing is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Location Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private var permissionLabel: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "Allowed"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not asked"
        @unknown default: return "Unknown"
        }
    }
}

#Preview {
    LocationView()
        .environmentObject(CloudKitService())
}
