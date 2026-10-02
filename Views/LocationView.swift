import SwiftUI
import MapKit
import CoreLocation

struct LocationView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @StateObject private var locationManager = LocationManager()
    @State private var visibleMembers: [FamilyMember] = []
    @State private var selectedMember: FamilyMember?
    @State private var showRequestSheet = false
    @State private var showApprovalSheet = false
    @State private var selectedRequestID: UUID?
    @State private var selectedParentForRequest: FamilyMember?
    @State private var approvalDuration = 60
    
    // Current user (would be set from auth system)
    @State private var currentUserID = UUID()
    @State private var currentUserRole = "parent" // "parent" or "child"
    
    var body: some View {
        ZStack {
            if visibleMembers.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("No locations available")
                    Text("Turn on location permissions to share your location")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                MapView(members: visibleMembers, selectedMember: $selectedMember)
            }
            
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Family Locations")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(currentUserRole.capitalized)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    
                    if currentUserRole == "child" {
                        Button(action: { showRequestSheet = true }) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                
                Spacer()
                
                // Member List
                VStack(spacing: 0) {
                    ForEach(visibleMembers) { member in
                        MemberLocationRow(
                            member: member,
                            isSelected: selectedMember?.id == member.id,
                            onTap: { selectedMember = member }
                        )
                        .onTapGesture {
                            selectedMember = member
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding()
            }
        }
        .background(Color(.systemGray6))
        .onAppear {
            locationManager.startUpdatingLocation()
            updateVisibleMembers()
        }
        .onChange(of: locationManager.currentLocation) { newLocation in
            if let location = newLocation {
                cloudKitService.updateMemberLocation(memberID: currentUserID, latitude: location.latitude, longitude: location.longitude)
            }
        }
        .sheet(isPresented: $showRequestSheet) {
            LocationRequestSheet(
                currentUserID: currentUserID,
                currentUserName: "Current User",
                availableParents: visibleMembers.filter { $0.isParent && $0.id != currentUserID },
                cloudKitService: cloudKitService,
                isPresented: $showRequestSheet
            )
        }
        .sheet(isPresented: $showApprovalSheet) {
            LocationApprovalSheet(
                requests: cloudKitService.locationRequests.filter { $0.status == .pending },
                cloudKitService: cloudKitService,
                approvalDuration: $approvalDuration,
                isPresented: $showApprovalSheet
            )
        }
        .onAppear {
            if currentUserRole == "parent" {
                cloudKitService.fetchPendingLocationRequests(for: currentUserID)
            }
        }
    }
    
    private func updateVisibleMembers() {
        if currentUserRole == "parent" {
            // Parents see all family members
            visibleMembers = cloudKitService.familyMembers
        } else {
            // Kids see themselves and all parents
            visibleMembers = cloudKitService.familyMembers.filter { 
                $0.id == currentUserID || $0.isParent
            }
        }
    }
}

struct MemberLocationRow: View {
    let member: FamilyMember
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: member.isParent ? "person.fill" : "person.circle.fill")
                .foregroundColor(member.isParent ? .blue : .green)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .fontWeight(.semibold)
                    Spacer()
                    if let lastUpdate = member.lastLocationUpdate {
                        Text(timeAgo(lastUpdate))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                if let latitude = member.latitude, let longitude = member.longitude {
                    Text(String(format: "%.4f, %.4f", latitude, longitude))
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Text("Location unavailable")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "Now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

struct LocationRequestSheet: View {
    let currentUserID: UUID
    let currentUserName: String
    let availableParents: [FamilyMember]
    let cloudKitService: CloudKitService
    @Binding var isPresented: Bool
    
    @State private var selectedParent: FamilyMember?
    
    var body: some View {
        NavigationView {
            VStack {
                if availableParents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No parents found")
                        Text("Add a parent to request location access")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    List(availableParents) { parent in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(parent.name)
                            Spacer()
                            if selectedParent?.id == parent.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedParent = parent
                        }
                    }
                }
            }
            .navigationTitle("Request Location Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send Request") {
                        if let parent = selectedParent {
                            cloudKitService.createLocationRequest(
                                from: currentUserID,
                                childName: currentUserName,
                                to: parent.id,
                                parentName: parent.name
                            )
                            isPresented = false
                        }
                    }
                    .disabled(selectedParent == nil)
                }
            }
        }
    }
}

struct LocationApprovalSheet: View {
    let requests: [LocationRequest]
    let cloudKitService: CloudKitService
    @Binding var approvalDuration: Int
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                if requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("No pending requests")
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    List(requests) { request in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(request.requestingChildName)
                                        .fontWeight(.semibold)
                                    Text("Requested location access")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Text(request.timeRemaining)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Duration")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Picker("", selection: $approvalDuration) {
                                        Text("30 min").tag(30)
                                        Text("1 hour").tag(60)
                                        Text("2 hours").tag(120)
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: { cloudKitService.denyLocationRequest(requestID: request.id) }) {
                                    Text("Deny")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                                
                                Button(action: { cloudKitService.approveLocationRequest(requestID: request.id, for: approvalDuration) }) {
                                    Text("Approve")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Location Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

struct MapView: View {
    let members: [FamilyMember]
    @Binding var selectedMember: FamilyMember?
    
    @State private var position: MapCameraPosition = .automatic
    
    var body: some View {
        ZStack {
            Map(position: $position) {
                ForEach(members) { member in
                    if let latitude = member.latitude, let longitude = member.longitude {
                        Annotation(member.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                            VStack {
                                Image(systemName: member.isParent ? "person.fill" : "person.circle.fill")
                                    .font(.title)
                                    .foregroundColor(member.isParent ? .blue : .green)
                                    .padding(8)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                            .onTapGesture {
                                selectedMember = member
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard)
        }
    }
}

#Preview {
    LocationView()
        .environmentObject(CloudKitService())
}
