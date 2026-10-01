import SwiftUI
import UIKit

struct CloudKitInviteSheet: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var isSending = false
    @State private var sent = false

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
                }

                if sent {
                    Section("Send this to them") {
                        Text(cloudKitService.familyInviteCode)
                            .font(.largeTitle.monospaced().weight(.bold))
                            .frame(maxWidth: .infinity)
                        Text("Apple does not email family invites. Text or copy this code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ShareLink(item: inviteMessage) {
                            Label("Text / share invite", systemImage: "square.and.arrow.up")
                        }
                        Button("Copy code") {
                            UIPasteboard.general.string = cloudKitService.familyInviteCode
                        }
                    }
                } else {
                    Section {
                        Text("After you send, you get a join code to text them. They will not get an Apple email.")
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
