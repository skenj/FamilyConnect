import SwiftUI
import MapKit
import CoreLocation

struct LocationView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @StateObject private var locationManager = LocationManager()
    @StateObject private var geofenceService = GeofenceService.shared
    @State private var showRequestSheet = false
    @State private var showApprovalSheet = false
    @State private var showZoneManager = false
    @State private var selectedMember: FamilyMember?
    @State private var approvalDuration = 60
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var familyZones: [FamilyZone] = []
    @State private var showAddZone = false
    @State private var isProcessingTap = false
    @State private var tapCoordinate: CLLocationCoordinate2D?

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
            // MARK: - Map with zones + member pins
            MapReader { proxy in
                Map(position: $mapPosition) {
                    // Zone overlays
                    ForEach(familyZones) { zone in
                        MapCircle(
                            center: zone.coordinate,
                            radius: zone.radius
                        )
                        .foregroundStyle(zoneColor(zone).opacity(0.15))
                        .stroke(zoneColor(zone), lineWidth: 2)

                        Annotation(zone.name, coordinate: zone.coordinate) {
                            ZonePin(zone: zone)
                        }
                    }

                    // Family member pins
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
                .onTapGesture { location in
                    // Parent can tap map to create a zone (debounced)
                    guard isParent, !isProcessingTap else { return }
                    guard let coordinate = proxy.convert(location, from: .local) else { return }
                    isProcessingTap = true
                    tapCoordinate = coordinate
                    showAddZone = true
                    // Reset after short delay so rapid taps are ignored
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isProcessingTap = false
                    }
                }
            }

            // MARK: - Bottom Panel
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Family Locations")
                            .font(.headline)
                        Text(isParent ? "Parent view" : "Child view")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    // Zone manager button (parents only)
                    if isParent {
                        Button(action: { showZoneManager = true }) {
                            Image(systemName: "mappin.circle")
                                .foregroundColor(.purple)
                                .font(.title3)
                        }
                        .padding(.trailing, 4)
                    }

                    // Child: request location access
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

                    // Parent: pending location request badge
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
                .frame(maxHeight: 200)
                .background(Color(.systemBackground))

                // Zone hint for parents
                if isParent && familyZones.isEmpty {
                    Text("Tap the map to add a family zone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                }
            }
            .cornerRadius(16, corners: [.topLeft, .topRight])
            .shadow(radius: 8)
        }
        .onAppear {
            locationManager.startUpdatingLocation()
            if isParent {
                GeofenceService.shared.requestAlwaysAuthorization()
                if let me = currentUser {
                    Task { await cloudKitService.fetchPendingLocationRequests(for: me.id) }
                }
            } else {
                GeofenceService.shared.requestAlwaysAuthorization()
            }
            Task { await cloudKitService.fetchFamilyZones() }
            loadZonesFromNotification()
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
        .onReceive(NotificationCenter.default.publisher(for: .navigateToLocation)) { _ in
            if isParent, let me = currentUser {
                Task { await cloudKitService.fetchPendingLocationRequests(for: me.id) }
                showApprovalSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .familyZonesUpdated)) { _ in
            Task { await cloudKitService.fetchFamilyZones() }
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
        .sheet(isPresented: $showZoneManager) {
            ZoneManagerSheet(
                zones: familyZones,
                cloudKitService: cloudKitService,
                isPresented: $showZoneManager
            )
        }
        .sheet(isPresented: $showAddZone, onDismiss: {
            tapCoordinate = nil
            isProcessingTap = false
        }) {
            if let coordinate = tapCoordinate {
                AddZoneSheet(
                    coordinate: coordinate,
                    cloudKitService: cloudKitService,
                    onSave: { zone in
                        familyZones.append(zone)
                        showAddZone = false
                    },
                    onCancel: { showAddZone = false }
                )
            }
        }
    }

    private func loadZonesFromNotification() {
        // Zones are populated via fetchFamilyZones → GeofenceService
        // Local UI state updated via .familyZonesUpdated notification
    }

    private func zoneColor(_ zone: FamilyZone) -> Color {
        Color(hex: zone.color) ?? .purple
    }
}

// MARK: - Zone Pin
struct ZonePin: View {
    let zone: FamilyZone
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(Color(hex: zone.color) ?? .purple)
                .font(.title2)
                .background(Color.white.clipShape(Circle()))
        }
    }
}

// MARK: - Coordinate wrapper for sheet
struct CoordinateWrapper: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Add Zone Sheet
struct AddZoneSheet: View {
    let coordinate: CLLocationCoordinate2D
    let cloudKitService: CloudKitService
    let onSave: (FamilyZone) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var radius: Double = 200
    @State private var triggerMode: FamilyZone.TriggerMode = .both
    @State private var selectedColor = "#FF6B6B"
    @State private var isSaving = false

    private let colorOptions = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8"]
    private let radiusOptions: [(String, Double)] = [
        ("100m", 100), ("200m", 200), ("500m", 500), ("1km", 1000), ("2km", 2000)
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Zone name") {
                    TextField("e.g. Home, School, Sports field", text: $name)
                }

                Section("Trigger") {
                    Picker("Notify me when", selection: $triggerMode) {
                        ForEach(FamilyZone.TriggerMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Radius") {
                    Picker("Zone size", selection: $radius) {
                        ForEach(radiusOptions, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Colour") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex) ?? .purple)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColor == hex ? 3 : 0)
                                    )
                                    .onTapGesture { selectedColor = hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Location")
                }
            }
            .navigationTitle("New Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                                  let me = cloudKitService.currentUser else { return }
                            isSaving = true
                            let zone = FamilyZone(
                                name: name,
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude,
                                radius: radius,
                                triggerMode: triggerMode,
                                color: selectedColor,
                                createdByID: me.id,
                                createdByName: me.displayName
                            )
                            Task {
                                await cloudKitService.saveFamilyZone(zone)
                                isSaving = false
                                onSave(zone)
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - Zone Manager Sheet
struct ZoneManagerSheet: View {
    let zones: [FamilyZone]
    let cloudKitService: CloudKitService
    @Binding var isPresented: Bool
    @State private var deleting: UUID?

    var body: some View {
        NavigationView {
            Group {
                if zones.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "mappin.slash.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No zones yet")
                            .font(.headline)
                        Text("Tap anywhere on the map to create a family zone.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(zones) { zone in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: zone.color) ?? .purple)
                                    .frame(width: 14, height: 14)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(zone.name)
                                        .fontWeight(.semibold)
                                    HStack(spacing: 4) {
                                        Image(systemName: zone.triggerMode.systemImage)
                                            .font(.caption2)
                                        Text(zone.triggerMode.displayName)
                                            .font(.caption)
                                        Text("·")
                                            .font(.caption)
                                        Text(radiusLabel(zone.radius))
                                            .font(.caption)
                                    }
                                    .foregroundColor(.secondary)
                                }

                                Spacer()

                                if deleting == zone.id {
                                    ProgressView()
                                } else {
                                    Button(action: {
                                        deleting = zone.id
                                        Task {
                                            await cloudKitService.deleteFamilyZone(zone)
                                            deleting = nil
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Family Zones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }

    private func radiusLabel(_ radius: Double) -> String {
        if radius >= 1000 { return String(format: "%.0fkm", radius / 1000) }
        return "\(Int(radius))m radius"
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
                            Image(systemName: "person.fill").foregroundColor(.blue)
                            Text(parent.displayName)
                            Spacer()
                            if selectedParent?.id == parent.id {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
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
                                from: me.id, childName: me.displayName,
                                to: parent.id, parentName: parent.displayName
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
    @State private var processing: UUID?

    var body: some View {
        NavigationView {
            Group {
                if requests.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("No pending requests")
                            .font(.headline)
                        Text("Location requests from your children will appear here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(requests) { request in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.orange).font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.requestingChildName).fontWeight(.semibold)
                                    Text("Requesting location access")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(timeAgo(request.requestedDate))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allow access for:").font(.caption).foregroundColor(.secondary)
                                Picker("Duration", selection: $approvalDuration) {
                                    Text("30 min").tag(30)
                                    Text("1 hour").tag(60)
                                    Text("90 min").tag(90)
                                    Text("2 hours").tag(120)
                                }
                                .pickerStyle(.segmented)
                            }
                            HStack(spacing: 12) {
                                Button(action: {
                                    processing = request.id
                                    Task {
                                        await cloudKitService.denyLocationRequestWithNotification(requestID: request.id)
                                        processing = nil
                                    }
                                }) {
                                    Group {
                                        if processing == request.id { ProgressView() }
                                        else { Text("Deny") }
                                    }.frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered).tint(.red).disabled(processing != nil)

                                Button(action: {
                                    processing = request.id
                                    Task {
                                        await cloudKitService.approveLocationRequestWithNotification(requestID: request.id, for: approvalDuration)
                                        processing = nil
                                    }
                                }) {
                                    Group {
                                        if processing == request.id { ProgressView() }
                                        else { Label("Approve", systemImage: "checkmark.circle.fill") }
                                    }.frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent).disabled(processing != nil)
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

// MARK: - Color hex extension
extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double(value         & 0xFF) / 255
        )
    }
}

#Preview {
    LocationView().environmentObject(CloudKitService())
}
