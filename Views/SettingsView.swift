import SwiftUI
import PhotosUI
import MessageUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @State private var joinCode = ""
    @State private var showingLeaveFamily = false
    @State private var showingFeedback = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var me: FamilyMember? { cloudKitService.currentUser }
    private var isParent: Bool { cloudKitService.canAddFamilyMembers }

    var body: some View {
        List {
            Section {
                if !cloudKitService.myAppleIDEmail.isEmpty {
                    HStack {
                        Text("Signed in")
                        Spacer()
                        Text(cloudKitService.myAppleIDEmail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Button("Log out", role: .destructive) {
                    cloudKitService.signOut()
                }
            } header: {
                Text("Account")
            }

            Section {
                Button {
                    showingFeedback = true
                } label: {
                    Label("Send screenshots to Nick", systemImage: "camera.badge.ellipsis")
                }
                Text("Testers can attach screenshots and a short note. It opens Mail to nskewes@icloud.com.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Troubleshooting")
            }

            Section {
                Text("More app settings will be added here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Coming later")
            }

            Section {
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
            } header: {
                Text("Apple ID for invites")
            }

            Section {
                TextField("Invite code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join with code") {
                    Task { await cloudKitService.joinFamily(withCode: joinCode) }
                }
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).count < 4)
                Text("If you were invited, enter the Apple ID email above, then the code the parent texted you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Join a family")
            }

            if !cloudKitService.pendingInvites.isEmpty {
                Section {
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
                } header: {
                    Text("Invitations")
                }
            }

            if let me {
                Section {
                    Toggle("Share my location", isOn: sharingBinding(for: me))
                    if cloudKitService.pendingLocationOffRequests.contains(me.id) {
                        Text("Waiting for a parent to approve turning this off.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("My location")
                }
            }

            if isParent {
                Section {
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
                } header: {
                    Text("Family location")
                } footer: {
                    Text("Parents can turn anyone on and off. A child who turns sharing off sends a request here first.")
                }
            }

            if isParent || cloudKitService.belongsToSomeoneElsesFamily {
                Section {
                    Button("Leave family", role: .destructive) {
                        showingLeaveFamily = true
                    }
                    Text("You will lose access to this family's information.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("This family")
                }
            }

            Section {
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
            } header: {
                Text("Info")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingFeedback) {
            FeedbackComposerView(
                version: appVersion,
                build: appBuild,
                signedInAs: cloudKitService.myAppleIDEmail
            )
        }
        .alert("Leave this family?", isPresented: $showingLeaveFamily) {
            Button("Leave family", role: .destructive) {
                Task { await cloudKitService.leaveFamily() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will no longer see this family's members, messages, calendar, or meals. Invite is required to join again.")
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

struct FeedbackComposerView: View {
    let version: String
    let build: String
    let signedInAs: String
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var showingMail = false
    @State private var mailError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened") {
                    TextField("Short note for Nick", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Screenshots") {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
                        Label("Add screenshots", systemImage: "photo.on.rectangle.angled")
                    }
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Send to nskewes@icloud.com") {
                        if MFMailComposeViewController.canSendMail() {
                            showingMail = true
                        } else {
                            mailError = "Mail is not set up on this iPhone. Add an email account in Settings, or share the screenshots from Photos."
                        }
                    }
                    .disabled(images.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Includes app version \(version) (\(build)).")
                }
                if let mailError {
                    Section {
                        Text(mailError).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Send feedback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadImages(items) }
            }
            .sheet(isPresented: $showingMail) {
                MailComposeView(
                    subject: "FamilyConnect tester feedback \(version) (\(build))",
                    body: mailBody,
                    images: images
                ) { dismiss() }
            }
        }
    }

    private var mailBody: String {
        """
        \(note)

        ---
        Version: \(version)
        Build: \(build)
        Signed in as: \(signedInAs.isEmpty ? "unknown" : signedInAs)
        Device: \(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        """
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        images = loaded
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let images: [UIImage]
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mail = MFMailComposeViewController()
        mail.mailComposeDelegate = context.coordinator
        mail.setToRecipients(["nskewes@icloud.com"])
        mail.setSubject(subject)
        mail.setMessageBody(body, isHTML: false)
        for (index, image) in images.enumerated() {
            if let data = image.jpegData(compressionQuality: 0.7) {
                mail.addAttachmentData(data, mimeType: "image/jpeg", fileName: "screenshot-\(index + 1).jpg")
            }
        }
        return mail
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { self.onFinish() }
        }
    }
}
