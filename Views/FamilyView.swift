import SwiftUI
import PhotosUI
import UIKit

struct FamilyView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @State private var showingInvite = false
    @State private var memberToEdit: FamilyMember?
    @State private var memberToDelete: FamilyMember?
    @State private var showingLeaveFamily = false

    private var isParent: Bool {
        cloudKitService.canAddFamilyMembers
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(cloudKitService.familyMembers.filter { $0.inviteStatus.caseInsensitiveCompare("Left") != .orderedSame }) { member in
                        Button {
                            memberToEdit = member
                        } label: {
                            memberRow(member)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isParent, !member.isCurrentUser {
                                Button("Remove", role: .destructive) {
                                    memberToDelete = member
                                }
                            }
                        }
                    }
                }
                if isParent {
                    Section {
                        Button("Leave family", role: .destructive) {
                            showingLeaveFamily = true
                        }
                    } footer: {
                        Text("You will lose access to this family's chats, calendar, meals, and members.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("My Family")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isParent {
                        Button {
                            showingInvite = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityLabel("Invite family member")
                    }
                }
            }
            .sheet(isPresented: $showingInvite) {
                FamilyInviteSheet()
                    .environmentObject(cloudKitService)
            }
            .sheet(item: $memberToEdit) { member in
                EditFamilyMemberSheet(member: member)
                    .environmentObject(cloudKitService)
            }
            .alert(
                "Remove \(memberToDelete?.displayName ?? "this person")?",
                isPresented: Binding(
                    get: { memberToDelete != nil },
                    set: { if !$0 { memberToDelete = nil } }
                )
            ) {
                Button("Remove", role: .destructive) {
                    if let member = memberToDelete {
                        Task { await cloudKitService.deleteFamilyMember(member) }
                    }
                    memberToDelete = nil
                }
                Button("Cancel", role: .cancel) { memberToDelete = nil }
            } message: {
                Text("They will leave the family share. They will not come back unless you invite them again.")
            }
            .alert(
                "Leave this family?",
                isPresented: $showingLeaveFamily
            ) {
                Button("Leave family", role: .destructive) {
                    Task { await cloudKitService.leaveFamily() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will no longer see this family's members, messages, calendar, or meals. This cannot be undone unless someone invites you again.")
            }
            .refreshable { await cloudKitService.refreshAll() }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !member.email.isEmpty, member.displayName.caseInsensitiveCompare(member.email) != .orderedSame {
                    Text(member.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if member.isCurrentUser {
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            Text(statusLabel(member))
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor(member))
            if !cloudKitService.isLocationSharingEnabled(for: member.id) {
                Image(systemName: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if cloudKitService.pendingLocationOffRequests.contains(member.id) {
                Image(systemName: "location.slash.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusLabel(_ member: FamilyMember) -> String {
        if member.inviteStatus == "Awaiting" { return "Awaiting" }
        return member.role.isEmpty ? "Family" : member.role
    }

    private func statusColor(_ member: FamilyMember) -> Color {
        member.inviteStatus == "Awaiting" ? .orange : .secondary
    }
}

struct MemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image = member.loadPhoto() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let parts = member.displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "•" : String(letters).uppercased()
    }
}

struct EditFamilyMemberSheet: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMember

    @State private var name = ""
    @State private var nickname = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var role = "Family"
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: UIImage?

    private let roles = ["Parent", "Child", "Guardian", "Family"]
    private var canEdit: Bool {
        cloudKitService.canAddFamilyMembers || member.isCurrentUser
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    HStack {
                        if let preview {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        } else {
                            MemberAvatar(member: member, size: 64)
                        }
                        if canEdit {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Text("Choose photo")
                            }
                        }
                    }
                }
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Nickname", text: $nickname)
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    if cloudKitService.canAddFamilyMembers {
                        Picker("Role", selection: $role) {
                            ForEach(roles, id: \.self) { Text($0) }
                        }
                    } else {
                        Text(role)
                    }
                }

                Section {
                    Toggle("Share location", isOn: locationBinding)
                    if cloudKitService.pendingLocationOffRequests.contains(member.id) {
                        Text(member.isCurrentUser
                             ? "Waiting for a parent to approve turning this off."
                             : "This person asked to turn location off.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        if cloudKitService.canAddFamilyMembers && !member.isCurrentUser {
                            HStack {
                                Button("Deny") {
                                    Task { await cloudKitService.denyLocationOffRequest(for: member) }
                                }
                                Button("Approve off") {
                                    Task { await cloudKitService.approveLocationOffRequest(for: member) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    if cloudKitService.canAddFamilyMembers {
                        Text("Parents can turn any member on or off. A child who turns this off sends you a chat request first.")
                    } else {
                        Text("If you turn this off, a parent is asked to approve it.")
                    }
                }
            }
            .navigationTitle("Edit")
            .onAppear {
                name = member.name
                nickname = member.nickname
                email = member.email
                phone = member.phoneNumber
                role = member.role.isEmpty ? "Family" : member.role
                preview = member.loadPhoto()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        preview = image
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canEdit || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        var updated = member
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.nickname = nickname.trimmingCharacters(in: .whitespaces)
        updated.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        updated.phoneNumber = phone
        updated.role = role
        if let preview {
            updated.savePhoto(preview)
        }
        await cloudKitService.saveFamilyMember(updated)
        dismiss()
    }

    private var locationBinding: Binding<Bool> {
        Binding(
            get: { cloudKitService.isLocationSharingEnabled(for: member.id) },
            set: { enabled in
                Task { await cloudKitService.setLocationSharing(for: member, enabled: enabled) }
            }
        )
    }
}

#Preview {
    FamilyView()
        .environmentObject(CloudKitService())
}

extension FamilyMember {
    func loadPhoto() -> UIImage? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("member-\(id.uuidString).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    mutating func savePhoto(_ image: UIImage) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("member-\(id.uuidString).jpg")
        if let data = image.jpegData(compressionQuality: 0.82) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

struct FamilyInviteSheet: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var isSending = false
    @State private var sent = false

    private var inviteMessage: String {
        "You're invited to \(cloudKitService.familyName) on FamilyConnect. Open the app → Settings → Apple ID email \(email) → Join family → code \(cloudKitService.familyInviteCode)."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Who to invite") {
                    TextField("Name", text: $name)
                    TextField("Apple ID email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                }
                if sent {
                    Section("Send this to them") {
                        Text(cloudKitService.familyInviteCode)
                            .font(.largeTitle.monospaced().weight(.bold))
                            .frame(maxWidth: .infinity)
                        Text("They will not get an Apple email. Text them this code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ShareLink(item: inviteMessage) {
                            Label("Text / share invite", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Text("After send you get a join code to text. Apple does not notify them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = cloudKitService.error, !error.isEmpty {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Invite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else if sent {
                        Button("Done") { dismiss() }
                    } else {
                        Button("Create invite") {
                            Task { await send() }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || email.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        cloudKitService.error = nil
        do {
            try await cloudKitService.invitePerson(name: name, email: email)
            sent = true
        } catch {
            cloudKitService.error = error.localizedDescription
        }
        isSending = false
    }
}
