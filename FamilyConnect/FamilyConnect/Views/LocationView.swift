//
//  LocationView.swift
//  FamilyConnect
//
//  Created by Nick Skewes on 16/9/2026.
//


import SwiftUI
import MapKit

struct LocationView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var position: MapCameraPosition = .automatic
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            VStack {
                Map(position: $position) {
                    ForEach(0..<cloudKitService.familyMembers.count, id: \.self) { index in
                        let member = cloudKitService.familyMembers[index]
                        Annotation(member.name, coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)) {
                            VStack {
                                Image(systemName: "location.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                                Text(member.name)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .mapStyle(.standard)
                .frame(maxHeight: .infinity)
                
                VStack {
                    Text("Family Members")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    List {
                        ForEach(cloudKitService.familyMembers) { member in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.headline)
                                    Text(member.role)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "location.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 150)
                }
            }
            .navigationTitle("Family Locations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                LocationSettingsSheet(isPresented: $showingSettings)
            }
        }
    }
}

struct LocationSettingsSheet: View {
    @Binding var isPresented: Bool
    @State private var shareLocationEnabled = true
    @State private var updateFrequency = "Every 5 minutes"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Location Sharing") {
                    Toggle("Share My Location", isOn: $shareLocationEnabled)
                }
                
                Section("Update Frequency") {
                    Picker("How often to update", selection: $updateFrequency) {
                        Text("Real-time").tag("real-time")
                        Text("Every minute").tag("1min")
                        Text("Every 5 minutes").tag("5min")
                        Text("Every 30 minutes").tag("30min")
                    }
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
}

#Preview {
    LocationView()
        .environmentObject(CloudKitService())
}