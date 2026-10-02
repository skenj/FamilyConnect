import Foundation
import AuthenticationServices
import CloudKit

// MARK: - Authentication Extensions
// Add these methods to CloudKitService by dropping this file into Services/

extension CloudKitService {

    // MARK: - Apple Credential State Validation (FIX #1)
    // Call on every app launch and foreground to detect revoked tokens.

    func validateAppleCredentialState() async {
        let provider = CloudKitService.appleIDProvider
        guard let appleUserID = UserDefaults.standard.string(forKey: "FamilyConnect.appleUserID"),
              !appleUserID.isEmpty else {
            // No Apple sign-in stored — nothing to validate
            return
        }

        do {
            let state = try await provider.credentialState(forUserID: appleUserID)
            await MainActor.run {
                switch state {
                case .authorized:
                    // All good — credential is still valid
                    break
                case .revoked:
                    // User revoked access in Apple ID settings → force sign out
                    self.signOut()
                    self.error = "Your Apple ID sign-in was revoked. Please sign in again."
                case .notFound:
                    // Credential not found — could be a new device or Apple ID mismatch
                    // Don't force sign out (could be email-based user) but flag it
                    print("Apple credential not found for stored userID")
                case .transferred:
                    // App was transferred to a new team — re-authenticate
                    self.signOut()
                    self.error = "Please sign in again."
                @unknown default:
                    break
                }
            }
        } catch {
            // Network error or other issue — don't sign out, just log
            print("Could not validate Apple credential state: \(error.localizedDescription)")
        }
    }

    // Shared provider instance (avoids creating one per call)
    private static let appleIDProvider = ASAuthorizationAppleIDProvider()

    // MARK: - Invite with Role (FIX #6)
    // Extends invitePerson() to also set the invited member's role.

    func invitePersonWithRole(name: String, email: String, role: String) async throws {
        // Run the standard invite flow
        try await invitePerson(name: name, email: email)

        // After invite succeeds, update the member's role
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let index = familyMembers.firstIndex(where: {
            $0.email.caseInsensitiveCompare(trimmedEmail) == .orderedSame
        }) {
            familyMembers[index].role = role
            await saveFamilyMember(familyMembers[index])
        }
    }
}
