import SwiftUI
import UIKit

struct CloudKitInviteSheet: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var role = "Child"   // FIX: role picker added
    @State private var isSending = false
    @State private var sent = false
    @State private var codeCopied = false

    private var inviteMessage: String {
        let code = cloudKitService.familyInviteCode
        return "You're invited to \(cloudKitService.familyName) on FamilyConnect. Open the app → Settings → enter your Apple ID email (\(email)) → Join family → code \(code)."
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

                    // FIX: Role picker so parent can set Parent vs Child before inviting
                    Picker("Role", selection: $role) {
                        Text("Child").tag("Child")
                        Text("Parent").tag("Parent")
                    }
                    .pickerStyle(.segmented)
                }

                if sent {
                    Section("Send this to them") {
                        // Code display
                        VStack(spacing: 8) {
                            Text(cloudKitService.familyInviteCode)
                                .font(.largeTitle.monospaced().weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)

                            // FIX: Auto-copy button with confirmation
                            Button(action: copyCode) {
                                HStack {
                                    Image(systemName: codeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(codeCopied ? "Copied!" : "Copy code")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(codeCopied ? .green : .blue)
                            .animation(.easeInOut(duration: 0.2), value: codeCopied)
                        }

                        Text("Apple does not email family invites. Text or copy this code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        // FIX: Pre-formatted share message
                        ShareLink(item: inviteMessage) {
                            Label("Share invite via Messages", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section {
                        Text("After you send, you get a join code to text them. They will not receive an Apple email — you need to share the code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
                        Button("Send invite") {
                            Task { await send() }
                        }
                        .disabled(
                            name.trimmingCharacters(in: .whitespaces).isEmpty ||
                            email.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                    }
                }
            }
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = cloudKitService.familyInviteCode
        withAnimation { codeCopied = true }
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { codeCopied = false }
        }
    }

    private func send() async {
        isSending = true
        cloudKitService.error = nil
        do {
            try await cloudKitService.invitePersonWithRole(name: name, email: email, role: role)
            sent = true
            // FIX: Auto-copy code to clipboard as soon as it's generated
            UIPasteboard.general.string = cloudKitService.familyInviteCode
            codeCopied = true
        } catch {
            cloudKitService.error = error.localizedDescription
        }
        isSending = false
    }
}
