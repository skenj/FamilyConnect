import SwiftUI
import AuthenticationServices
import UIKit

struct AuthView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @State private var email = ""
    @State private var name = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "person.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("FamilyConnect")
                    .font(.largeTitle.bold())
                Text("Sign in so we can match any family invitation sent to your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 24)

                Text("or")
                    .foregroundStyle(.secondary)

                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)
                TextField("Apple ID or Google email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)

                Button("Continue with email") {
                    let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.contains("@") else {
                        message = "Enter the email the parent invited."
                        return
                    }
                    cloudKitService.completeSignIn(email: trimmed, name: name, provider: "email")
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)

                Button("Continue with Google") {
                    message = "Google Sign-In needs a Google Cloud OAuth client in a later build. Use the same Gmail in the email field and tap Continue with email."
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            UserDefaults.standard.set(credential.user, forKey: "FamilyConnect.appleUserID")
            let savedEmail = UserDefaults.standard.string(forKey: "FamilyConnect.myAppleIDEmail") ?? ""
            let resolvedEmail = credential.email
                ?? (cloudKitService.myAppleIDEmail.isEmpty ? nil : cloudKitService.myAppleIDEmail)
                ?? (savedEmail.isEmpty ? nil : savedEmail)
                ?? email
            let resolvedName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !resolvedName.isEmpty { name = resolvedName }
            // Apple only returns email the first time. Still sign in.
            cloudKitService.completeSignIn(
                email: resolvedEmail,
                name: resolvedName.isEmpty ? name : resolvedName,
                provider: "apple"
            )
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}

struct InviteDecisionView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("You have been invited to a family. Accept to join. You cannot create another family until you leave this one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(cloudKitService.pendingInvites) { invite in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(invite.organizerName) invited you to \(invite.familyName)")
                            .font(.headline)
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
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Family invite")
        }
    }
}
