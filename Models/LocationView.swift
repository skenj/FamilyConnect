import SwiftUI
import MapKit
import CoreLocation

struct LocationView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @StateObject private var locationManager = LocationManager()
    @State private var showRequestSheet = false
    @State private var showApprovalSheet = false
    @State private var selectedMember: FamilyMember?
    @State private var approvalDuration = 60
    @State private var mapPosition: MapCameraPosition = .automatic

    private var currentUser: FamilyMember? { cloudKitService.currentUser }
    private var isParent: Bool { currentUser?.isParent ?? false }

    private var visibleMembers: [FamilyMember] {
        guard let me = currentUser else { return [] }
        if isParent {
            return cloudKitService.familyMembers
        } else {
            return cloudKitService.familyMembers.filter { $0.id == me.id || $0.isParent }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Map
            Map(position: $mapPosition) {
                ForEach(visibleMembers) { member in
                    if let lat = member.latitude, let lon = member.longitude {
                        Annotation(member.displayName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                            VStack(spacing: 2) {
                                Image(systemName: member.isParent ? "person.fill" : "person.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(member.isParent ? .blue : .green)
                                    .padding(8)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 3)
                                Text(member.displayName)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.9))
                                    .cornerRadius(6)
                            }
                            .onTapGesture { selectedMember = member }
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea(edges: .top)

            // Bottom panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Family Locations")
                            .font(.headline)
                        Text(isParent ? "Parent view" : "Child view")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !isParent {
                        Button(action: { showRequestSheet = true }) {
                            Label("Request", systemImage: "hand.raised.fill")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    if isParent {
                        let pending = cloudKitService.locationRequests.filter { $0.status == .pending }
                        if !pending.isEmpty {
                            Button(action: { showApprovalSheet = true }) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: "bell.fill")
                                        .foregroundColor(.orange)
                                    Text("\(pending.count)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                        .padding(3)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 6, y: -6)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))

                Divider()

                // Member list
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(visibleMembers) { member in
                            MemberLocationRow(
                                member: member,
                                isSelected: selectedMember?.id == member.id
                            )
                            .onTapGesture { selectedMember = member }
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(Color(.systemBackground))
            }
            .cornerRadius(16, corners: [.topLeft, .topRight])
            .shadow(radius: 8)
        }
        .onAppear {
            locationManager.startUpdatingLocation()
            if isParent, let me = currentUser {
                Task { await cloudKitService.fetchPendingLocationRequests(for: me.id) }
            }
        }
        .onChange(of: locationManager.hasLocation) {
            guard locationManager.hasLocation else { return }
            Task {
                await cloudKitService.updateMemberLocation(
                    latitude: locationManager.latitude,
                    longitude: locationManager.longitude
                )
            }
        }
        .sheet(isPresented: $showRequestSheet) {
            LocationRequestSheet(
                currentUser: currentUser,
                availableParents: cloudKitService.familyMembers.filter { $0.isParent },
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
    }
}

// MARK: - Corner radius helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Member Row
struct MemberLocationRow: View {
    let member: FamilyMember
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: member.isParent ? "person.fill" : "person.circle.fill")
                .foregroundColor(member.isParent ? .blue : .green)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .fontWeight(.semibold)
                if let lat = member.latitude, let lon = member.longitude {
                    Text(String(format: "%.4f, %.4f", lat, lon))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Location unavailable")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            if let lastUpdate = member.lastLocationUpdate {
                Text(timeAgo(lastUpdate))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
    }

    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "Now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}

// MARK: - Request Sheet (Child)
struct LocationRequestSheet: View {
    let currentUser: FamilyMember?
    let availableParents: [FamilyMember]
    let cloudKitService: CloudKitService
    @Binding var isPresented: Bool
    @State private var selectedParent: FamilyMember?

    var body: some View {
        NavigationView {
            Group {
                if availableParents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No parents found")
                        Text("A parent must be added to the family first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(availableParents) { parent in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(parent.displayName)
                            Spacer()
                            if selectedParent?.id == parent.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedParent = parent }
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
                        guard let me = currentUser, let parent = selectedParent else { return }
                        Task {
                            await cloudKitService.createLocationRequest(
                                from: me.id,
                                childName: me.displayName,
                                to: parent.id,
                                parentName: parent.displayName
                            )
                        }
                        isPresented = false
                    }
                    .disabled(selectedParent == nil || currentUser == nil)
                }
            }
        }
    }
}

// MARK: - Approval Sheet (Parent)
struct LocationApprovalSheet: View {
    let requests: [LocationRequest]
    let cloudKitService: CloudKitService
    @Binding var approvalDuration: Int
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            Group {
                if requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("No pending requests")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(requests) { request in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.requestingChildName)
                                        .fontWeight(.semibold)
                                    Text("Requesting location access")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(timeAgo(request.requestedDate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Picker("Duration", selection: $approvalDuration) {
                                Text("30 min").tag(30)
                                Text("1 hour").tag(60)
                                Text("2 hours").tag(120)
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 12) {
                                Button("Deny") {
                                    Task { await cloudKitService.denyLocationRequest(requestID: request.id) }
                                }
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.bordered)
                                .tint(.red)

                                Button("Approve") {
                                    Task { await cloudKitService.approveLocationRequest(requestID: request.id, for: approvalDuration) }
                                }
                                .frame(maxWidth: .infinity)
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 6)
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

    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}

#Preview {
    LocationView()
        .environmentObject(CloudKitService())
}
