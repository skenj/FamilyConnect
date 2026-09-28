import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @State private var joinCode = "" // unused; invites arrive in-app

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var me: FamilyMember? { cloudKitService.currentUser }
    private var isParent: Bool { cloudKitService.canAddFamilyMembers }

    var body: some View {
        NavigationStack {
            List {
                Section("Apple ID for invites") {
                    TextField("Your Apple ID email", text: $cloudKitService.myAppleIDEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .onChange(of: cloudKitService.myAppleIDEmail) { _, _ in
                            UserDefaults.standard.set(cloudKitService.myAppleIDEmail, forKey: "FamilyConnect.myAppleIDEmail")
                            Task {
                                await cloudKitService.subscribeToFamilyInvites()
                                await cloudKitService.fetchPendingInvites()
                            }
                        }
                    Text("Use the same email the parent invited. The app matches invitations to this Apple ID.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !cloudKitService.pendingInvites.isEmpty {
                    Section("Invitations") {
                        ForEach(cloudKitService.pendingInvites) { invite in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(invite.organizerName) invited you to \(invite.familyName)")
                                HStack {
                                    Button("Accept") {
                                        Task { await cloudKitService.acceptPendingInvite(invite) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("Decline") {
                                        Task { await cloudKitService.declinePendingInvite(invite) }
                                    }
                                }
                            }
                        }
                    }
                }

                if let me {
                    Section("My location") {
                        Toggle("Share my location", isOn: sharingBinding(for: me))
                        if cloudKitService.pendingLocationOffRequests.contains(me.id) {
                            Text("Waiting for a parent to approve turning this off.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isParent {
                    Section("Family location") {
                        ForEach(cloudKitService.familyMembers) { member in
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(member.displayName, isOn: sharingBinding(for: member))
                                if cloudKitService.pendingLocationOffRequests.contains(member.id) {
                                    HStack {
                                        Text("Asked to turn off")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Spacer()
                                        Button("Deny") {
                                            Task { await cloudKitService.denyLocationOffRequest(for: member) }
                                        }
                                        Button("Approve") {
                                            Task { await cloudKitService.approveLocationOffRequest(for: member) }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("Parents can turn anyone on or off. A child who turns sharing off sends a request here first.")
                    }
                }

                Section("Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(appBuild)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func sharingBinding(for member: FamilyMember) -> Binding<Bool> {
        Binding(
            get: { cloudKitService.isLocationSharingEnabled(for: member.id) },
            set: { enabled in
                Task { await cloudKitService.setLocationSharing(for: member, enabled: enabled) }
            }
        )
    }
}
