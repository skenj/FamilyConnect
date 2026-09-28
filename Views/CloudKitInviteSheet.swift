import SwiftUI

struct CloudKitInviteSheet: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var isSending = false
    @State private var sent = false

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
                    Section("Sent") {
                        Text("Invitation sent to \(email). If they have FamilyConnect and are signed into that Apple ID, they get a notification and can Accept on Home or in Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("No Messages or iCloud share sheet. They accept inside FamilyConnect with the same Apple ID.")
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
