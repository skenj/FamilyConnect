import Foundation
import CloudKit
import Combine
import UserNotifications
import UIKit

// FamilyConnect CloudKitService 2026-09-29 warning-clean

@MainActor
final class CloudKitService: ObservableObject {
    static var preferLocalSandbox = false

    @Published var familyMembers: [FamilyMember] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var recipes: [Recipe] = []
    @Published var fridgeItems: [FridgeItem] = []
    @Published var acceptedFoods: [ChildAcceptedFood] = []
    @Published var mealVotes: [MealVote] = []
    @Published var currentUser: FamilyMember?
    @Published var isLoading = false
    @Published var error: String?
    @Published var accountStatusDescription = "Checking…"
    @Published var familyName = "My Family"
    @Published var isShareOwner = true
    @Published var shareURL: URL?
    @Published var participantEmails: [String] = []
    @Published var sharingStatus = "Not shared yet"
    @Published var isLocalSandbox = false
    @Published var sandboxInviteCode = ""
    @Published var pendingRecipeURL: String?
    @Published var locationSharingEnabled: [UUID: Bool] = [:]
    @Published var pendingLocationOffRequests: Set<UUID> = []
    @Published var familyInviteCode = ""
    @Published var suppressedInviteEmails: Set<String> = []
    @Published var pendingInvites: [PendingFamilyInvite] = []
    @Published var myAppleIDEmail = ""
    @Published var isSignedIn = UserDefaults.standard.bool(forKey: "FamilyConnect.isSignedIn")
    @Published var signedInProvider = UserDefaults.standard.string(forKey: "FamilyConnect.authProvider") ?? ""

    var belongsToSomeoneElsesFamily: Bool { !isShareOwner }

    var canCreateNewFamily: Bool {
        isShareOwner && pendingInvites.isEmpty
    }

    var canAddFamilyMembers: Bool {
        currentUser?.role.caseInsensitiveCompare("Parent") == .orderedSame
    }

    var openMealVotes: [MealVote] {
        mealVotes.filter(\.isOpen).sorted { $0.createdAt < $1.createdAt }
    }

    var childMembers: [FamilyMember] {
        familyMembers.filter { $0.role.caseInsensitiveCompare("Child") == .orderedSame }
    }

    let container = CKContainer(identifier: "iCloud.com.personal.FamilyConnect")

    private var iCloudUserRecordName: String?
    private var familyRoot: CKRecord?
    private var familyShare: CKShare?
    private let store = LocalFamilyStore()

    private var familyZoneID = CKRecordZone.ID(zoneName: "FamilyZone")

    private var activeDatabase: CKDatabase {
        isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private var familyRecordID: CKRecord.ID {
        CKRecord.ID(recordName: "family-root", zoneID: familyZoneID)
    }

    func acceptedFoods(for childID: UUID) -> [ChildAcceptedFood] {
        acceptedFoods.filter { $0.childID == childID }
            .sorted { $0.ingredientName.localizedCaseInsensitiveCompare($1.ingredientName) == .orderedAscending }
    }

    func fridgeContains(_ name: String) -> Bool {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return fridgeItems.contains { $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased()) }
    }

    func inFridgeCount(for recipe: Recipe) -> Int {
        recipe.ingredientNames.filter { fridgeContains($0) }.count
    }

    func missingFridgeIngredients(for recipe: Recipe) -> [String] {
        recipe.ingredientNames.filter { !fridgeContains($0) }
    }

    func childrenWhoMayRefuse(_ recipe: Recipe) -> [FamilyMember] {
        childMembers.filter { child in
            let accepted = acceptedFoods(for: child.id).map { $0.ingredientName.lowercased() }
            guard !accepted.isEmpty else { return false }
            return recipe.ingredientNames.contains { ingredient in
                !accepted.contains { acceptedName in
                    ingredient.lowercased().contains(acceptedName) || acceptedName.contains(ingredient.lowercased())
                }
            }
        }
    }

    func bootstrap() async {
        loadSnapshot()

        if Self.preferLocalSandbox {
            startLocalSandbox(reason: "Local sandbox (no Developer Program CloudKit yet)")
            return
        }

        await checkAccountStatus()
        if isLocalSandbox { return }

        await resolveICloudUser()
        await fetchPendingInvites()
        let joinedOther = UserDefaults.standard.bool(forKey: "FamilyConnect.joinedOtherFamily")
        if await loadSharedFamilyRoot() {
            UserDefaults.standard.set(true, forKey: "FamilyConnect.joinedOtherFamily")
            await claimJoinedMembership()
            await applyICloudProfile()
            await refreshAll()
        } else if joinedOther {
            isShareOwner = false
            sharingStatus = "Reconnecting to family…"
            _ = await loadSharedFamilyRoot()
            await refreshAll()
        } else if pendingInvites.isEmpty {
            await loadFamilyShareContext()
            await ensureCurrentUserRecord()
            await applyICloudProfile()
            await refreshAll()
        } else {
            // Invitation waiting — do not create a second family.
            await applyICloudProfile()
        }

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "didRequestNotify") == false {
            await FamilyNotifier.requestPermission()
            defaults.set(true, forKey: "didRequestNotify")
        }
        if defaults.bool(forKey: "didSubscribeChat") == false {
            await subscribeToChatNotifications()
            defaults.set(true, forKey: "didSubscribeChat")
        }
        await subscribeToFamilyInvites()
        await fetchPendingInvites()

        NotificationCenter.default.addObserver(forName: .familyCloudKitShareAccepted, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isShareOwner = false
                _ = await self.loadSharedFamilyRoot()
                await self.ensureCurrentUserRecord()
                if var me = self.currentUser {
                    me.inviteStatus = "Accepted"
                    await self.saveFamilyMember(me)
                }
                await self.refreshAll()
                self.sharingStatus = "Joined family"
            }
        }
        NotificationCenter.default.addObserver(forName: .familyCloudKitShareFailed, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                self?.error = (note.object as? String) ?? "Could not accept family invite"
            }
        }
    }

    func refreshAll() async {
        if isLocalSandbox {
            loadSnapshot()
            return
        }

        isLoading = true
        defer { isLoading = false }
        async let members: () = fetchFamilyMembers()
        async let events: () = fetchCalendarEvents()
        async let messages: () = fetchChatMessages()
        async let meals: () = fetchMealData()
        _ = await (members, events, messages, meals)
    }

    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                accountStatusDescription = "iCloud available"
                isLocalSandbox = false
            case .noAccount:
                startLocalSandbox(reason: "No iCloud account on this device")
            case .restricted:
                startLocalSandbox(reason: "iCloud is restricted on this device")
            case .temporarilyUnavailable, .couldNotDetermine:
                accountStatusDescription = "Trying CloudKit"
                isLocalSandbox = false
            @unknown default:
                isLocalSandbox = false
            }
        } catch {
            accountStatusDescription = "CloudKit status error: \(error.localizedDescription)"
            isLocalSandbox = false
        }
    }

    func resolveICloudUser() async {
        do {
            iCloudUserRecordName = try await container.userRecordID().recordName
        } catch {
            iCloudUserRecordName = nil
        }
    }

    func startLocalSandbox(reason: String) {
        isLocalSandbox = true
        accountStatusDescription = reason
        sharingStatus = reason
        if store.load() == nil {
            sandboxInviteCode = Self.makeInviteCode()
        }
        loadSnapshot()
        if familyMembers.isEmpty {
            let owner = FamilyMember(name: "Me", email: "", phoneNumber: "", role: "Parent", isCurrentUser: true)
            familyMembers = [owner]
            currentUser = owner
            persistSnapshot()
        }
    }

    func addSandboxInvitee(name: String) {
        let member = FamilyMember(name: name, email: "", phoneNumber: "", role: "Family")
        familyMembers.append(member)
        persistSnapshot()
    }

    func switchSandboxUser(to member: FamilyMember) {
        var updated = familyMembers
        for i in updated.indices {
            updated[i].isCurrentUser = updated[i].id == member.id
        }
        familyMembers = updated
        currentUser = updated.first(where: { $0.id == member.id })
        persistSnapshot()
    }

    func resetSandbox() {
        store.clear()
        familyMembers = []
        calendarEvents = []
        chatMessages = []
        recipes = []
        fridgeItems = []
        acceptedFoods = []
        currentUser = nil
        participantEmails = []
        shareURL = nil
        startLocalSandbox(reason: "Local sandbox reset")
    }

    private func loadSnapshot() {
        guard let snapshot = store.load() else { return }
        familyName = snapshot.familyName
        familyMembers = snapshot.members
        calendarEvents = snapshot.events
        chatMessages = snapshot.messages.sorted { $0.timestamp < $1.timestamp }
        recipes = snapshot.recipes
        fridgeItems = snapshot.fridgeItems
        acceptedFoods = snapshot.acceptedFoods
        participantEmails = snapshot.participantEmails
        sandboxInviteCode = snapshot.inviteCode
        currentUser = familyMembers.first(where: \.isCurrentUser) ?? familyMembers.first
        sharingStatus = "Sandbox family with \(familyMembers.count) people"
        loadLocationSharingPrefs()
        loadInvitePrefs()
    }

    private func persistSnapshot() {
        store.save(
            LocalFamilySnapshot(
                familyName: familyName,
                inviteCode: sandboxInviteCode,
                members: familyMembers,
                events: calendarEvents,
                messages: chatMessages,
                recipes: recipes,
                fridgeItems: fridgeItems,
                acceptedFoods: acceptedFoods,
                participantEmails: participantEmails
            )
        )
        persistLocationSharingPrefs()
        persistInvitePrefs()
    }

    func isLocationSharingEnabled(for memberID: UUID) -> Bool {
        locationSharingEnabled[memberID] ?? true
    }

    func setLocationSharing(for member: FamilyMember, enabled: Bool) async {
        guard let me = currentUser else { return }
        let iAmParent = canAddFamilyMembers
        let targetIsChild = member.role.caseInsensitiveCompare("Child") == .orderedSame
        let changingSelf = member.id == me.id

        if !enabled && changingSelf && targetIsChild && !iAmParent {
            pendingLocationOffRequests.insert(member.id)
            persistLocationSharingPrefs()
            let parents = familyMembers.filter { $0.role.caseInsensitiveCompare("Parent") == .orderedSame }
            let message = ChatMessage(
                content: "\(me.displayName) asked to turn off location sharing.",
                senderID: me.id,
                senderName: me.displayName,
                timestamp: Date(),
                notifyScope: parents.map { $0.id.uuidString }.joined(separator: ","),
                mentionedIDs: parents.map(\.id)
            )
            await saveChatMessage(message)
            return
        }

        if !iAmParent && !changingSelf {
            error = "Only a Parent can change another person's location sharing."
            return
        }

        locationSharingEnabled[member.id] = enabled
        pendingLocationOffRequests.remove(member.id)
        persistLocationSharingPrefs()
        if iAmParent && !changingSelf {
            let message = ChatMessage(
                content: "Location sharing for \(member.displayName) is now \(enabled ? "on" : "off").",
                senderID: me.id,
                senderName: me.displayName,
                timestamp: Date(),
                notifyScope: "all",
                mentionedIDs: [member.id]
            )
            await saveChatMessage(message)
        }
    }

    func approveLocationOffRequest(for member: FamilyMember) async {
        guard canAddFamilyMembers else { return }
        locationSharingEnabled[member.id] = false
        pendingLocationOffRequests.remove(member.id)
        persistLocationSharingPrefs()
        let me = currentUser
        let message = ChatMessage(
            content: "A parent approved turning off location sharing for \(member.displayName).",
            senderID: me?.id ?? member.id,
            senderName: me?.displayName ?? "Parent",
            timestamp: Date(),
            notifyScope: member.id.uuidString,
            mentionedIDs: [member.id]
        )
        await saveChatMessage(message)
    }

    func denyLocationOffRequest(for member: FamilyMember) async {
        guard canAddFamilyMembers else { return }
        pendingLocationOffRequests.remove(member.id)
        persistLocationSharingPrefs()
    }

    private func persistLocationSharingPrefs() {
        let on = Dictionary(uniqueKeysWithValues: locationSharingEnabled.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(on, forKey: "FamilyConnect.locationSharing")
        UserDefaults.standard.set(pendingLocationOffRequests.map(\.uuidString), forKey: "FamilyConnect.locationOffRequests")
    }

    private func loadLocationSharingPrefs() {
        if let on = UserDefaults.standard.dictionary(forKey: "FamilyConnect.locationSharing") as? [String: Bool] {
            locationSharingEnabled = Dictionary(uniqueKeysWithValues: on.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        if let pending = UserDefaults.standard.array(forKey: "FamilyConnect.locationOffRequests") as? [String] {
            pendingLocationOffRequests = Set(pending.compactMap(UUID.init))
        }
    }

    private func persistInvitePrefs() {
        UserDefaults.standard.set(familyInviteCode, forKey: "FamilyConnect.familyInviteCode")
        UserDefaults.standard.set(Array(suppressedInviteEmails), forKey: "FamilyConnect.suppressedInviteEmails")
        UserDefaults.standard.set(myAppleIDEmail, forKey: "FamilyConnect.myAppleIDEmail")
    }

    private func loadInvitePrefs() {
        familyInviteCode = UserDefaults.standard.string(forKey: "FamilyConnect.familyInviteCode") ?? familyInviteCode
        if let emails = UserDefaults.standard.array(forKey: "FamilyConnect.suppressedInviteEmails") as? [String] {
            suppressedInviteEmails = Set(emails.map { $0.lowercased() })
        }
        myAppleIDEmail = UserDefaults.standard.string(forKey: "FamilyConnect.myAppleIDEmail") ?? myAppleIDEmail
    }

    private static func makeInviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    func loadFamilyShareContext() async {
        if isLocalSandbox { return }
        do {
            try await ensureFamilyZone()
        } catch {
            self.error = "Could not create FamilyZone: \(error.localizedDescription)"
            return
        }
        if let root = try? await container.privateCloudDatabase.record(for: familyRecordID) {
            familyRoot = root
            familyName = root["name"] as? String ?? "My Family"
            isShareOwner = true
            if let shareRef = root.share {
                if let existing = try? await container.privateCloudDatabase.record(for: shareRef.recordID) as? CKShare {
                    familyShare = existing
                    shareURL = existing.url
                    refreshParticipantList(from: existing)
                }
            }
            return
        }
        if await loadSharedFamilyRoot() {
            return
        }
        await createFamilyRootIfNeeded()
    }

    @discardableResult
    func loadSharedFamilyRoot() async -> Bool {
        guard let zones = try? await container.sharedCloudDatabase.allRecordZones() else { return false }
        for zone in zones where zone.zoneID.zoneName == "FamilyZone" {
            familyZoneID = zone.zoneID
            isShareOwner = false
            let rootID = CKRecord.ID(recordName: "family-root", zoneID: zone.zoneID)
            if let root = try? await container.sharedCloudDatabase.record(for: rootID) {
                familyRoot = root
                familyName = root["name"] as? String ?? familyName
                sharingStatus = "Joined family"
                return true
            }
        }
        return false
    }

    func ensureFamilyZone() async throws {
        let key = "didCreateFamilyZone"
        if UserDefaults.standard.bool(forKey: key) { return }
        let zone = CKRecordZone(zoneID: familyZoneID)
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
        UserDefaults.standard.set(true, forKey: key)
    }

    func createFamilyRootIfNeeded() async {
        guard !isLocalSandbox, familyRoot == nil else { return }
        _ = try? await ensureFamilyZone()
        let record = CKRecord(recordType: "Family", recordID: familyRecordID)
        record["name"] = familyName
        record["createdDate"] = Date()
        if let saved = try? await container.privateCloudDatabase.save(record) {
            familyRoot = saved
        }
    }

    func updateFamilyName(_ name: String) async {
        familyName = name
        if isLocalSandbox {
            persistSnapshot()
            return
        }
        guard let root = familyRoot else { return }
        root["name"] = name
        if let saved = try? await activeDatabase.save(root) {
            familyRoot = saved
        }
    }

    func prepareShare() async throws -> CKShare {
        if isLocalSandbox {
            throw CloudKitServiceError.sandboxInvite
        }
        try await ensureFamilyZone()
        await createFamilyRootIfNeeded()

        let root = try await container.privateCloudDatabase.record(for: familyRecordID)
        familyRoot = root

        if let existingID = root.share?.recordID,
           let existing = try? await container.privateCloudDatabase.record(for: existingID) as? CKShare {
            familyShare = existing
            shareURL = existing.url
            if existing.publicPermission != .none {
                existing.publicPermission = .none
                if let saved = try? await container.privateCloudDatabase.save(existing) as? CKShare {
                    familyShare = saved
                } else {
                    familyShare = existing
                }
                shareURL = familyShare?.url ?? existing.url
            }
            refreshParticipantList(from: familyShare ?? existing)
            sharingStatus = existing.url == nil ? "Share exists — tap Refresh in a moment" : "Invite link ready"
            return familyShare ?? existing
        }

        if let existing = familyShare, existing.url != nil {
            shareURL = existing.url
            return existing
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = familyName as CKRecordValue
        // Only people the organiser adds as participants can accept.
        // .readWrite here would let anyone with the URL join another family's data.
        share.publicPermission = .none

        let saved: (saveResults: [CKRecord.ID: Result<CKRecord, Error>], deleteResults: [CKRecord.ID: Result<Void, Error>])
        do {
            saved = try await container.privateCloudDatabase.modifyRecords(
                saving: [root, share],
                deleting: [],
                savePolicy: .changedKeys,
                atomically: true
            )
        } catch {
            let text = error.localizedDescription
            if text.localizedCaseInsensitiveContains("oplock") || text.localizedCaseInsensitiveContains("server record") {
                let latest = try await container.privateCloudDatabase.record(for: familyRecordID)
                familyRoot = latest
                if let existingID = latest.share?.recordID,
                   let existing = try? await container.privateCloudDatabase.record(for: existingID) as? CKShare {
                    familyShare = existing
                    shareURL = existing.url
                    return existing
                }
            }
            throw error
        }
        var savedShare: CKShare?
        for result in saved.saveResults.values {
            switch result {
            case .success(let record):
                if let next = record as? CKShare {
                    savedShare = next
                } else if record.recordID == root.recordID {
                    familyRoot = record
                }
            case .failure(let error):
                throw error
            }
        }
        guard let savedShare else { throw CloudKitServiceError.missingFamily }
        familyShare = savedShare
        shareURL = savedShare.url
        refreshParticipantList(from: savedShare)
        sharingStatus = savedShare.url == nil ? "Share created — tap Refresh if the link is missing" : "Invite link ready"
        return savedShare
    }

    func invitePerson(name: String, email: String) async throws {
        guard isShareOwner else {
            throw CloudKitServiceError.notAuthorized
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedName.isEmpty else { return }
        if !trimmedEmail.isEmpty {
            suppressedInviteEmails.remove(trimmedEmail)
        }

        if let index = familyMembers.firstIndex(where: {
            (!trimmedEmail.isEmpty && $0.email.caseInsensitiveCompare(trimmedEmail) == .orderedSame) ||
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            familyMembers[index].inviteStatus = "Awaiting"
            if !trimmedEmail.isEmpty { familyMembers[index].email = trimmedEmail }
            if familyMembers[index].name.contains("@") { familyMembers[index].name = trimmedName }
            await saveFamilyMember(familyMembers[index])
        } else {
            var member = FamilyMember(
                name: trimmedName,
                email: trimmedEmail,
                phoneNumber: "",
                role: "Family"
            )
            member.inviteStatus = "Awaiting"
            upsertMember(member)
            persistSnapshot()
            await saveFamilyMember(member)
        }

        let share = try await prepareShare()
        let participant: CKShare.Participant
        do {
            participant = try await fetchShareParticipant(email: trimmedEmail)
        } catch {
            throw CloudKitServiceError.appleIDNotFound(trimmedEmail)
        }
        participant.permission = .readWrite
        participant.role = .privateUser
        share.addParticipant(participant)
        let saved = try await container.privateCloudDatabase.save(share)
        if let savedShare = saved as? CKShare {
            familyShare = savedShare
            shareURL = savedShare.url
        }
        familyInviteCode = Self.makeInviteCode()
        let inviteeRecordName = participant.userIdentity.userRecordID?.recordName ?? ""
        try await publishFamilyInvite(
            code: familyInviteCode,
            email: trimmedEmail,
            inviteeUserRecordName: inviteeRecordName
        )
        persistInvitePrefs()
        sharingStatus = "Invite sent to \(trimmedEmail). Text them the join code."
    }

    func completeSignIn(email: String, name: String, provider: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        myAppleIDEmail = trimmed
        signedInProvider = provider
        isSignedIn = true
        UserDefaults.standard.set(true, forKey: "FamilyConnect.isSignedIn")
        UserDefaults.standard.set(provider, forKey: "FamilyConnect.authProvider")
        UserDefaults.standard.set(trimmed, forKey: "FamilyConnect.myAppleIDEmail")
        if var me = currentUser {
            if me.email.isEmpty { me.email = trimmed }
            if me.name == "Me" || me.name.isEmpty, !name.isEmpty { me.name = name }
            currentUser = me
            upsertMember(me)
        }
        persistInvitePrefs()
        Task {
            await subscribeToFamilyInvites()
            await fetchPendingInvites()
            await bootstrap()
        }
    }

    func signOut() {
        isSignedIn = false
        signedInProvider = ""
        pendingInvites = []
        UserDefaults.standard.set(false, forKey: "FamilyConnect.isSignedIn")
        UserDefaults.standard.set("", forKey: "FamilyConnect.authProvider")
        resetLocalFamilySession()
    }

    private func resetLocalFamilySession() {
        UserDefaults.standard.set(false, forKey: "FamilyConnect.joinedOtherFamily")
        isShareOwner = true
        familyShare = nil
        shareURL = nil
        familyRoot = nil
        familyZoneID = CKRecordZone.ID(zoneName: "FamilyZone")
        familyMembers = []
        currentUser = nil
        calendarEvents = []
        chatMessages = []
        recipes = []
        fridgeItems = []
        acceptedFoods = []
        mealVotes = []
        participantEmails = []
        familyName = "My Family"
        sharingStatus = "Signed out"
        store.clear()
        persistSnapshot()
    }

    func leaveFamily() async {
        let me = currentUser
        let email = (me?.email ?? myAppleIDEmail).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if var leaving = me {
            leaving.inviteStatus = "Left"
            leaving.isCurrentUser = false
            await saveFamilyMember(leaving)
            if !isLocalSandbox {
                let recordID = CKRecord.ID(recordName: leaving.id.uuidString, zoneID: familyZoneID)
                _ = try? await activeDatabase.deleteRecord(withID: recordID)
            }
        }
        if !email.isEmpty {
            suppressedInviteEmails.insert(email)
            persistInvitePrefs()
        }
        if isShareOwner, let share = familyShare, !email.isEmpty {
            for participant in share.participants where participant.role != .owner {
                let participantEmail = (participant.userIdentity.lookupInfo?.emailAddress ?? "").lowercased()
                if participantEmail == email {
                    share.removeParticipant(participant)
                }
            }
            _ = try? await container.privateCloudDatabase.save(share)
        }
        signOut()
    }

    private func publishFamilyInvite(code: String, email: String, inviteeUserRecordName: String) async throws {
        guard let url = shareURL ?? familyShare?.url else { return }
        let values: [String: String] = [
            "code": code,
            "shareURL": url.absoluteString,
            "familyName": familyName,
            "email": email,
            "organizerName": currentUser?.displayName ?? "A parent",
            "status": "pending"
        ]
        var listKeys: Set<String> = ["status", "inviteeUserRecordName"]
        for attempt in 1...8 {
            let record = CKRecord(recordType: "FamilyInvite", recordID: CKRecord.ID(recordName: code))
            for (key, value) in values {
                if listKeys.contains(key) {
                    record[key] = [value]
                } else {
                    record[key] = value
                }
            }
            if !inviteeUserRecordName.isEmpty {
                record["inviteeUserRecordName"] = [inviteeUserRecordName]
            }
            do {
                _ = try await container.publicCloudDatabase.save(record)
                return
            } catch {
                let text = error.localizedDescription
                guard let field = Self.cloudKitMismatchedField(in: text) else { throw error }
                if text.contains("STRING_LIST") {
                    listKeys.insert(field)
                } else {
                    listKeys.remove(field)
                }
                if attempt == 8 { throw error }
            }
        }
    }

    private static func cloudKitMismatchedField(in text: String) -> String? {
        guard let start = text.range(of: "field '"),
              let end = text.range(of: "' for type", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private func inviteField(_ record: CKRecord, _ key: String) -> String {
        if let value = record[key] as? String { return value }
        if let values = record[key] as? [String] { return values.first ?? "" }
        return ""
    }

    func fetchPendingInvites() async {
        let email = matchingInviteEmail()
        let recordName = iCloudUserRecordName ?? ""
        guard !email.isEmpty || !recordName.isEmpty else {
            pendingInvites = []
            return
        }
        var records: [CKRecord] = []
        if !email.isEmpty {
            records.append(contentsOf: await queryInvites(NSPredicate(format: "email == %@", email)))
        }
        if !recordName.isEmpty {
            records.append(contentsOf: await queryInvites(NSPredicate(format: "inviteeUserRecordName CONTAINS %@", recordName)))
        }
        var seen = Set<String>()
        pendingInvites = records.compactMap { record in
            let id = record.recordID.recordName
            guard seen.insert(id).inserted else { return nil }
            let status = inviteField(record, "status").lowercased()
            if status == "accepted" || status == "declined" { return nil }
            guard let url = URL(string: inviteField(record, "shareURL")) else { return nil }
            return PendingFamilyInvite(
                id: id,
                familyName: inviteField(record, "familyName").isEmpty ? "Family" : inviteField(record, "familyName"),
                organizerName: inviteField(record, "organizerName").isEmpty ? "A parent" : inviteField(record, "organizerName"),
                email: inviteField(record, "email"),
                shareURL: url
            )
        }
    }

    private func queryInvites(_ predicate: NSPredicate) async -> [CKRecord] {
        let query = CKQuery(recordType: "FamilyInvite", predicate: predicate)
        do {
            let result = try await container.publicCloudDatabase.records(matching: query)
            return result.matchResults.compactMap { _, item in try? item.get() }
        } catch {
            return []
        }
    }

    func acceptPendingInvite(_ invite: PendingFamilyInvite) async {
        familyName = invite.familyName
        await acceptShare(from: invite.shareURL)
        pendingInvites.removeAll { $0.id == invite.id }
        if let record = try? await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: invite.id)) {
            record["status"] = ["accepted"]
            _ = try? await container.publicCloudDatabase.save(record)
        }
    }

    func declinePendingInvite(_ invite: PendingFamilyInvite) async {
        pendingInvites.removeAll { $0.id == invite.id }
        if let record = try? await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: invite.id)) {
            record["status"] = ["declined"]
            _ = try? await container.publicCloudDatabase.save(record)
        }
    }

    func joinFamily(withCode raw: String) async {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 4 else {
            error = "Enter the family invite code."
            return
        }
        do {
            let record = try await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: code))
            guard let url = URL(string: inviteField(record, "shareURL")), !inviteField(record, "shareURL").isEmpty else {
                error = "That invite is no longer available."
                return
            }
            familyName = (record["familyName"] as? String) ?? familyName
            let invitedEmail = inviteField(record, "email")
            if myAppleIDEmail.isEmpty, !invitedEmail.isEmpty {
                myAppleIDEmail = invitedEmail.lowercased()
                UserDefaults.standard.set(myAppleIDEmail, forKey: "FamilyConnect.myAppleIDEmail")
            }
            await acceptShare(from: url)
            record["status"] = ["accepted"]
            _ = try? await container.publicCloudDatabase.save(record)
            await claimJoinedMembership()
        } catch {
            self.error = "No invite found. Sign into the invited Apple ID and pull to refresh Home."
        }
    }

    func subscribeToFamilyInvites() async {
        await FamilyNotifier.requestPermission()
        let email = matchingInviteEmail()
        let recordName = iCloudUserRecordName ?? ""
        if !email.isEmpty {
            await saveInviteSubscription(id: "family-invite-email", predicate: NSPredicate(format: "email == %@", email))
        }
        if !recordName.isEmpty {
            await saveInviteSubscription(id: "family-invite-user-\(recordName)", predicate: NSPredicate(format: "inviteeUserRecordName CONTAINS %@", recordName))
        }
    }

    private func saveInviteSubscription(id: String, predicate: NSPredicate) async {
        let subscription = CKQuerySubscription(
            recordType: "FamilyInvite",
            predicate: predicate,
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "You have a family invitation in FamilyConnect."
        info.soundName = "default"
        info.shouldBadge = true
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await container.publicCloudDatabase.save(subscription)
        } catch {
            // Duplicate subscription is fine.
        }
    }

    private func matchingInviteEmail() -> String {
        let typed = myAppleIDEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !typed.isEmpty { return typed }
        return (currentUser?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func refreshParticipantList(from share: CKShare? = nil) {
        let share = share ?? familyShare
        guard let share else { return }
        for participant in share.participants {
            if participant.role == .owner { continue }
            let email = (participant.userIdentity.lookupInfo?.emailAddress
                ?? participant.userIdentity.lookupInfo?.phoneNumber
                ?? "").lowercased()
            if !email.isEmpty, suppressedInviteEmails.contains(email) { continue }
            let name = [participant.userIdentity.nameComponents?.givenName, participant.userIdentity.nameComponents?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let status: String
            switch participant.acceptanceStatus {
            case .accepted: status = "Accepted"
            case .pending, .unknown: status = "Awaiting"
            case .removed: continue
            @unknown default: status = "Awaiting"
            }
            if let index = familyMembers.firstIndex(where: {
                (!$0.email.isEmpty && !email.isEmpty && $0.email.caseInsensitiveCompare(email) == .orderedSame) ||
                ($0.inviteStatus == "Awaiting" && !$0.email.isEmpty && !email.isEmpty && $0.email.caseInsensitiveCompare(email) == .orderedSame) ||
                ($0.name.caseInsensitiveCompare(name) == .orderedSame && !name.isEmpty)
            }) {
                familyMembers[index].inviteStatus = status
                if !email.isEmpty { familyMembers[index].email = email }
                if familyMembers[index].name.isEmpty || familyMembers[index].name == email, !name.isEmpty {
                    familyMembers[index].name = name
                }
            } else if status == "Awaiting", !email.isEmpty {
                // Only create a placeholder if invitePerson did not already add one.
                let exists = familyMembers.contains {
                    (!$0.email.isEmpty && !email.isEmpty && $0.email.caseInsensitiveCompare(email) == .orderedSame) ||
                    ($0.inviteStatus == "Awaiting" && $0.name.caseInsensitiveCompare(name.isEmpty ? email : name) == .orderedSame)
                }
                if !exists {
                    var member = FamilyMember(
                        name: name.isEmpty ? email : name,
                        email: email,
                        phoneNumber: "",
                        role: "Family"
                    )
                    member.inviteStatus = status
                    familyMembers.append(member)
                }
            }
        }
        persistSnapshot()
    }

    private func fetchShareParticipant(email: String) async throws -> CKShare.Participant {
        try await withCheckedThrowingContinuation { continuation in
            let info = CKUserIdentity.LookupInfo(emailAddress: email)
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [info])
            var fetched: CKShare.Participant?
            var finished = false
            operation.perShareParticipantResultBlock = { (_: CKUserIdentity.LookupInfo, result: Result<CKShare.Participant, Error>) in
                switch result {
                case .success(let participant):
                    fetched = participant
                case .failure(let error):
                    if !finished {
                        finished = true
                        continuation.resume(throwing: error)
                    }
                }
            }
            operation.fetchShareParticipantsResultBlock = { result in
                guard !finished else { return }
                finished = true
                switch result {
                case .success:
                    if let fetched {
                        continuation.resume(returning: fetched)
                    } else {
                        continuation.resume(throwing: CloudKitServiceError.missingFamily)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    func acceptShare(from url: URL) async {
        if RecipeImportRouter.consume(url, into: self) { return }
        if isLocalSandbox {
            sharingStatus = "Opened a share link in sandbox — CloudKit invite is disabled"
            return
        }
        do {
            let metadata = try await container.shareMetadata(for: url)
            do {
                _ = try await container.accept(metadata)
            } catch {
                // Already accepted or system already accepted via the delegate.
            }
            await finishJoiningShare()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func finishJoiningShare() async {
        isShareOwner = false
        UserDefaults.standard.set(true, forKey: "FamilyConnect.joinedOtherFamily")
        sharingStatus = "Joining family…"
        _ = await loadSharedFamilyRoot()
        await fetchFamilyMembers()
        await claimJoinedMembership()
        absorbAcceptedPlaceholders()
        persistSnapshot()
        await refreshAll()
        sharingStatus = "Joined family"
    }

    /// Bind this device to the invited FamilyMember row and mark it Accepted.
    func claimJoinedMembership() async {
        await resolveICloudUser()
        let email = matchingInviteEmail()
        for i in familyMembers.indices {
            familyMembers[i].isCurrentUser = false
        }
        let index = familyMembers.firstIndex { member in
            (!email.isEmpty && !member.email.isEmpty && member.email.caseInsensitiveCompare(email) == .orderedSame)
            || (iCloudUserRecordName != nil && member.iCloudUserRecordName == iCloudUserRecordName)
        }
        if let index {
            familyMembers[index].inviteStatus = "Accepted"
            familyMembers[index].isCurrentUser = true
            familyMembers[index].iCloudUserRecordName = iCloudUserRecordName ?? familyMembers[index].iCloudUserRecordName
            if familyMembers[index].email.isEmpty {
                familyMembers[index].email = email
            }
            currentUser = familyMembers[index]
            await saveFamilyMember(familyMembers[index])
            return
        }
        await ensureCurrentUserRecord()
        if var me = currentUser {
            me.inviteStatus = "Accepted"
            me.isCurrentUser = true
            me.email = me.email.isEmpty ? email : me.email
            await saveFamilyMember(me)
        }
    }

    /// When the invitee accepts, drop the organiser's Awaiting placeholder if we now have a real member.
    private func absorbAcceptedPlaceholders() {
        var kept: [FamilyMember] = []
        for member in familyMembers {
            let isPlaceholder = member.inviteStatus == "Awaiting" && member.iCloudUserRecordName == nil && !member.isCurrentUser
            if isPlaceholder {
                let mate = familyMembers.contains { other in
                    other.id != member.id &&
                    other.inviteStatus != "Awaiting" &&
                    (
                        (!member.email.isEmpty && other.email.caseInsensitiveCompare(member.email) == .orderedSame) ||
                        (!member.name.isEmpty && other.name.localizedCaseInsensitiveCompare(member.name) == .orderedSame)
                    )
                }
                if mate { continue }
            }
            kept.append(member)
        }
        familyMembers = kept
        dedupeMembers()
    }

    func ensureCurrentUserRecord() async {
        dedupeMembers()
        resolveLocalCurrentUser()
        if currentUser != nil { return }
        let me = FamilyMember(
            name: "Me",
            email: matchingInviteEmail(),
            phoneNumber: "",
            role: isShareOwner ? "Parent" : "Family",
            iCloudUserRecordName: iCloudUserRecordName,
            isCurrentUser: true
        )
        await saveFamilyMember(me)
    }

    func applyICloudProfile() async {
        do {
            let userID = try await container.userRecordID()
            iCloudUserRecordName = userID.recordName
            if var me = familyMembers.first(where: \.isCurrentUser) ?? currentUser {
                me.iCloudUserRecordName = userID.recordName
                me.isCurrentUser = true
                if me.name == "Me" || me.name.hasPrefix("Me") {
                    // keep editable local name
                }
                currentUser = me
                upsertMember(me)
                persistSnapshot()
                return
            }
            let given: String? = nil
            let email = ""
            let fullName = ""

            if var me = familyMembers.first(where: \.isCurrentUser) ?? currentUser {
                if let given, !given.isEmpty, me.name == "Me" || me.name.hasPrefix("Me") {
                    me.name = given
                } else if !fullName.isEmpty, me.name == "Me" || me.name.hasPrefix("Me") {
                    me.name = fullName
                }
                if me.email.isEmpty, !email.isEmpty {
                    me.email = email
                }
                me.iCloudUserRecordName = userID.recordName
                me.isCurrentUser = true
                currentUser = me
                upsertMember(me)
                persistSnapshot()
                if !isLocalSandbox {
                    var record = me.toCKRecord()
                    record = namespaced(record)
                    attachParent(&record)
                    _ = try? await upsertCloudRecord(record)
                }
            }
        } catch {
            // Keep local name if iCloud identity is hidden
        }
    }

    func saveFamilyMember(_ member: FamilyMember) async {
        if !canAddFamilyMembers && currentUser != nil && member.id != currentUser?.id &&
            !familyMembers.contains(where: { $0.id == member.id }) {
            error = "Only a Parent can add family members."
            return
        }
        upsertMember(member)
        persistSnapshot()
        guard !isLocalSandbox else { return }
        do {
            var record = member.toCKRecord()
            record = namespaced(record)
            attachParent(&record)
            try await upsertCloudRecord(record)
        } catch {
            self.error = cloudKitUserMessage(error, action: "member save")
        }
    }


    func deleteFamilyMember(_ member: FamilyMember) async {
        guard canAddFamilyMembers else {
            error = "Only a Parent can remove family members."
            return
        }
        guard member.isCurrentUser == false else {
            error = "You cannot remove yourself."
            return
        }
        familyMembers.removeAll { $0.id == member.id }
        let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !email.isEmpty { suppressedInviteEmails.insert(email) }
        persistInvitePrefs()
        persistSnapshot()
        if let share = familyShare, !email.isEmpty {
            for participant in share.participants where participant.role != .owner {
                let participantEmail = (participant.userIdentity.lookupInfo?.emailAddress ?? "").lowercased()
                if participantEmail == email {
                    share.removeParticipant(participant)
                }
            }
            if let saved = try? await container.privateCloudDatabase.save(share) as? CKShare {
                familyShare = saved
            }
        }
        guard !isLocalSandbox else { return }
        let recordID = CKRecord.ID(recordName: member.id.uuidString, zoneID: familyZoneID)
        do {
            try await activeDatabase.deleteRecord(withID: recordID)
        } catch {
            self.error = cloudKitUserMessage(error, action: "member delete")
        }
    }

    func saveCalendarEvent(_ event: CalendarEvent) async {
        if let index = calendarEvents.firstIndex(where: { $0.id == event.id }) {
            calendarEvents[index] = event
        } else {
            calendarEvents.append(event)
        }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        do {
            var record = event.toCKRecord()
            record = namespaced(record)
            attachParent(&record)
            try await upsertCloudRecord(record)
        } catch {
            self.error = cloudKitUserMessage(error, action: "event save")
        }
    }


    var parentMembers: [FamilyMember] {
        familyMembers.filter { $0.role.caseInsensitiveCompare("Parent") == .orderedSame }
    }

    func notifyParentsOfMealChoice(title: String, extra: String = "") async {
        guard let me = currentUser else { return }
        let parents = parentMembers
        let parentIDs = parents.map(\.id)
        var text = "\(me.displayName) would like \(title) tonight."
        if !extra.isEmpty { text += " \(extra)" }
        let message = ChatMessage(
            content: text,
            senderID: me.id,
            senderName: me.displayName,
            timestamp: Date(),
            notifyScope: parentIDs.map(\.uuidString).joined(separator: ","),
            mentionedIDs: parentIDs
        )
        await saveChatMessage(message)
        await addMealVoteRequest(title: title)
    }

    func saveChatMessage(_ message: ChatMessage) async {
        if let index = chatMessages.firstIndex(where: { $0.id == message.id }) {
            chatMessages[index] = message
        } else {
            chatMessages.append(message)
        }
        chatMessages.sort { $0.timestamp < $1.timestamp }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        if familyRoot == nil {
            if isShareOwner {
                await loadFamilyShareContext()
            } else {
                _ = await loadSharedFamilyRoot()
            }
        }
        do {
            var record = message.toCKRecord()
            record = namespaced(record)
            attachParent(&record)
            try await upsertCloudRecord(record)
        } catch {
            self.error = "CloudKit message save failed: \(error.localizedDescription)"
        }
    }

    func deleteChatMessage(_ message: ChatMessage) async {
        chatMessages.removeAll { $0.id == message.id }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        _ = try? await activeDatabase.deleteRecord(withID: CKRecord.ID(recordName: message.id.uuidString, zoneID: familyZoneID))
    }

    func saveRecipe(_ recipe: Recipe) async {
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        do {
            var record = recipe.toCKRecord()
            record = namespaced(record)
            attachParent(&record)
            try await upsertCloudRecord(record)
        } catch {
            self.error = cloudKitUserMessage(error, action: "recipe save")
        }
    }

    func deleteRecipe(_ recipe: Recipe) async {
        recipes.removeAll { $0.id == recipe.id }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        _ = try? await activeDatabase.deleteRecord(withID: CKRecord.ID(recordName: recipe.id.uuidString, zoneID: familyZoneID))
    }


    func addMealVoteRequest(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let me = currentUser else { return }
        if let existing = mealVotes.first(where: { $0.isOpen && $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            await castMealVote(existing.id)
            return
        }
        let vote = MealVote(
            title: trimmed,
            requestedByID: me.id,
            requestedByName: me.displayName,
            voterIDs: me.role.caseInsensitiveCompare("Child") == .orderedSame ? [me.id] : []
        )
        mealVotes.append(vote)
        await saveMealVote(vote)
        let kids = childMembers
        if !kids.isEmpty {
            let alert = ChatMessage(
                content: "New meal idea: \(trimmed). Kids can vote in Meals.",
                senderID: me.id,
                senderName: me.displayName,
                timestamp: Date(),
                notifyScope: kids.map { $0.id.uuidString }.joined(separator: ","),
                mentionedIDs: kids.map(\.id)
            )
            await saveChatMessage(alert)
        }
    }

    func castMealVote(_ voteID: UUID) async {
        guard let me = currentUser else { return }
        guard let index = mealVotes.firstIndex(where: { $0.id == voteID && $0.isOpen }) else { return }
        // one vote per child: remove from other open options
        for i in mealVotes.indices where mealVotes[i].isOpen {
            mealVotes[i].voterIDs.removeAll { $0 == me.id }
        }
        if !mealVotes[index].voterIDs.contains(me.id) {
            mealVotes[index].voterIDs.append(me.id)
        }
        for vote in mealVotes where vote.isOpen {
            await saveMealVote(vote)
        }
    }

    func closeMealVote() async {
        guard canAddFamilyMembers else {
            error = "Only a Parent can close the meal vote."
            return
        }
        let open = mealVotes.filter(\.isOpen)
        guard !open.isEmpty else { return }
        let winner = open.max(by: { $0.voteCount < $1.voteCount })
        for i in mealVotes.indices where mealVotes[i].isOpen {
            mealVotes[i].isOpen = false
            await saveMealVote(mealVotes[i])
        }
        let me = currentUser
        let result: String
        if let winner, winner.voteCount > 0 {
            result = "Meal vote closed. Winner: \(winner.title) (\(winner.voteCount) vote\(winner.voteCount == 1 ? "" : "s"))."
        } else {
            result = "Meal vote closed with no votes."
        }
        let recipients = familyMembers.map(\.id)
        let message = ChatMessage(
            content: result,
            senderID: me?.id ?? UUID(),
            senderName: me?.displayName ?? "Family",
            timestamp: Date(),
            notifyScope: "all",
            mentionedIDs: recipients
        )
        await saveChatMessage(message)
    }

    func saveMealVote(_ vote: MealVote) async {
        if let index = mealVotes.firstIndex(where: { $0.id == vote.id }) {
            mealVotes[index] = vote
        } else {
            mealVotes.append(vote)
        }
        guard !isLocalSandbox else { return }
        do {
            var record = vote.toCKRecord()
            record = namespaced(record)
            attachParent(&record)
            try await upsertCloudRecord(record)
        } catch {
            self.error = cloudKitUserMessage(error, action: "meal vote save")
        }
    }

    func saveFridgeItem(_ item: FridgeItem) async {
        if let index = fridgeItems.firstIndex(where: { $0.id == item.id }) {
            fridgeItems[index] = item
        } else {
            fridgeItems.insert(item, at: 0)
        }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        do {
            var record = item.toCKRecord()
            record = namespaced(record)
            attachParent(&record)
            try await upsertCloudRecord(record)
        } catch {
            self.error = cloudKitUserMessage(error, action: "fridge save")
        }
    }

    func deleteFridgeItem(_ item: FridgeItem) async {
        fridgeItems.removeAll { $0.id == item.id }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        _ = try? await activeDatabase.deleteRecord(withID: CKRecord.ID(recordName: item.id.uuidString, zoneID: familyZoneID))
    }

    func saveAcceptedFood(_ food: ChildAcceptedFood) async {
        if let index = acceptedFoods.firstIndex(where: { $0.id == food.id }) {
            acceptedFoods[index] = food
        } else {
            acceptedFoods.append(food)
        }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        do {
            var record = food.toCKRecord()
            record = namespaced(record)
            attachParent(&record)
            try await upsertCloudRecord(record)
        } catch {
            self.error = cloudKitUserMessage(error, action: "kid food save")
        }
    }

    func deleteAcceptedFood(_ food: ChildAcceptedFood) async {
        acceptedFoods.removeAll { $0.id == food.id }
        persistSnapshot()
        guard !isLocalSandbox else { return }
        _ = try? await activeDatabase.deleteRecord(withID: CKRecord.ID(recordName: food.id.uuidString, zoneID: familyZoneID))
    }

    private func fetchMealData() async {
        do {
            recipes = try await queryAll(Recipe.recordType).compactMap(Recipe.fromCKRecord)
        } catch {
            if let message = cloudKitUserMessage(error, action: "recipe fetch") { self.error = message }
        }
        do {
            fridgeItems = try await queryAll(FridgeItem.recordType).compactMap(FridgeItem.fromCKRecord)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            if let message = cloudKitUserMessage(error, action: "fridge fetch") { self.error = message }
        }
        do {
            acceptedFoods = try await queryAll(ChildAcceptedFood.recordType).compactMap(ChildAcceptedFood.fromCKRecord)
        } catch {
            if let message = cloudKitUserMessage(error, action: "kid food fetch") { self.error = message }
        }
        do {
            mealVotes = try await queryAll(MealVote.recordType).compactMap(MealVote.fromCKRecord)
                .sorted { $0.createdAt < $1.createdAt }
        } catch {
            if let message = cloudKitUserMessage(error, action: "meal vote fetch") { self.error = message }
        }
    }

    func updateMemberLocation(latitude: Double, longitude: Double) async {
        guard var me = currentUser else { return }
        me.latitude = latitude
        me.longitude = longitude
        await saveFamilyMember(me)
    }

        private func fetchFamilyMembers() async {
        do {
            let records = try await queryAll(FamilyMember.recordType)
            let fetched = records.compactMap(FamilyMember.fromCKRecord)
                .filter { $0.inviteStatus.caseInsensitiveCompare("Left") != .orderedSame }
            mergeMembers(fetched)
            familyMembers.removeAll { $0.inviteStatus.caseInsensitiveCompare("Left") == .orderedSame }
        } catch {
            if let message = cloudKitUserMessage(error, action: "member fetch") { self.error = message }
        }
    }

    private func fetchCalendarEvents() async {
        do {
            calendarEvents = try await queryAll(CalendarEvent.recordType).compactMap(CalendarEvent.fromCKRecord)
        } catch {
            if let message = cloudKitUserMessage(error, action: "event fetch") { self.error = message }
        }
    }

    private func fetchChatMessages() async {
        do {
            chatMessages = try await queryAll(ChatMessage.recordType).compactMap(ChatMessage.fromCKRecord)
                .sorted { $0.timestamp < $1.timestamp }
        } catch {
            if let message = cloudKitUserMessage(error, action: "chat fetch") { self.error = message }
        }
    }

    private func queryAll(_ recordType: String) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var zoneIDs: [CKRecordZone.ID] = [familyZoneID]
        let sharedZones = (try? await container.sharedCloudDatabase.allRecordZones()) ?? []
        let familyShared = sharedZones.map(\.zoneID).filter { $0.zoneName == "FamilyZone" }
        if !isShareOwner {
            if !familyShared.isEmpty {
                zoneIDs = familyShared
                familyZoneID = familyShared[0]
            }
        }
        func collect(from database: CKDatabase, zoneID: CKRecordZone.ID?) async {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            if let result = try? await database.records(matching: query, inZoneWith: zoneID) {
                for (_, item) in result.matchResults {
                    if let record = try? item.get() { records.append(record) }
                }
            }
        }
        for zoneID in zoneIDs {
            await collect(from: activeDatabase, zoneID: zoneID)
        }
        if records.isEmpty {
            for zoneID in familyShared {
                await collect(from: container.sharedCloudDatabase, zoneID: zoneID)
            }
        }
        if records.isEmpty, isShareOwner {
            await collect(from: container.privateCloudDatabase, zoneID: familyZoneID)
        }
        return records
    }

    private func namespaced(_ record: CKRecord) -> CKRecord {
        if record.recordID.zoneID == familyZoneID {
            return record
        }
        let newID = CKRecord.ID(recordName: record.recordID.recordName, zoneID: familyZoneID)
        let moved = CKRecord(recordType: record.recordType, recordID: newID)
        let skip: Set<String> = [
            "recordName", "createdBy", "creatorUserRecordID", "createdUserRecordName",
            "modifiedBy", "lastModifiedUserRecordID", "modifiedUserRecordName",
            "creationDate", "modificationDate", "etag", "parent", "share"
        ]
        for key in record.allKeys() {
            if key.hasPrefix("_") || skip.contains(key) { continue }
            if let asset = record[key] as? CKAsset, let url = asset.fileURL {
                moved[key] = CKAsset(fileURL: url)
            } else if record[key] is CKAsset {
                continue
            } else {
                moved[key] = record[key]
            }
        }
        return moved
    }


    private func upsertCloudRecord(_ record: CKRecord) async throws {
        _ = try await activeDatabase.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )
    }

    private func attachParent(_ record: inout CKRecord) {
        guard let root = familyRoot else { return }
        record.parent = CKRecord.Reference(record: root, action: .none)
    }


    private func dedupeMembers() {
        var unique: [FamilyMember] = []
        for member in familyMembers {
            let duplicate = unique.firstIndex { existing in
                existing.id == member.id ||
                (iCloudUserRecordName != nil && existing.iCloudUserRecordName == member.iCloudUserRecordName && member.iCloudUserRecordName != nil) ||
                (existing.isCurrentUser && member.isCurrentUser) ||
                (existing.name.hasPrefix("Me") && member.name.hasPrefix("Me")) ||
                (!existing.email.isEmpty && existing.email.caseInsensitiveCompare(member.email) == .orderedSame)
            }
            if let duplicate {
                if member.inviteStatus == "Accepted" { unique[duplicate].inviteStatus = "Accepted" }
                if unique[duplicate].inviteStatus == "Awaiting", member.inviteStatus != "Awaiting" {
                    unique[duplicate].inviteStatus = member.inviteStatus
                }
                if unique[duplicate].nickname.isEmpty { unique[duplicate].nickname = member.nickname }
                if unique[duplicate].phoneNumber.isEmpty { unique[duplicate].phoneNumber = member.phoneNumber }
                if member.isCurrentUser { unique[duplicate].isCurrentUser = true }
                if unique[duplicate].iCloudUserRecordName == nil {
                    unique[duplicate].iCloudUserRecordName = member.iCloudUserRecordName
                }
                if (unique[duplicate].name == "Me" || unique[duplicate].name.hasPrefix("Me")),
                   !member.name.isEmpty, member.name != "Me" {
                    unique[duplicate].name = member.name
                }
            } else {
                unique.append(member)
            }
        }
        familyMembers = unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        resolveLocalCurrentUser()
    }

    private func resolveLocalCurrentUser() {
        let email = matchingInviteEmail()
        for i in familyMembers.indices {
            familyMembers[i].isCurrentUser = false
        }
        if let i = familyMembers.firstIndex(where: { member in
            (iCloudUserRecordName != nil && member.iCloudUserRecordName == iCloudUserRecordName)
            || (!email.isEmpty && !member.email.isEmpty && member.email.caseInsensitiveCompare(email) == .orderedSame)
        }) {
            familyMembers[i].isCurrentUser = true
            if familyMembers[i].inviteStatus == "Awaiting" {
                familyMembers[i].inviteStatus = "Accepted"
            }
            currentUser = familyMembers[i]
        } else {
            currentUser = familyMembers.first(where: { $0.name == "Me" || $0.role.caseInsensitiveCompare("Parent") == .orderedSame && isShareOwner })
            currentUser?.isCurrentUser = true
            if let me = currentUser, let i = familyMembers.firstIndex(where: { $0.id == me.id }) {
                familyMembers[i].isCurrentUser = true
            }
        }
    }

    private func mergeMembers(_ fetched: [FamilyMember]) {
        var merged = fetched
        for local in familyMembers {
            let exists = merged.contains { remote in
                remote.id == local.id ||
                (!local.email.isEmpty && remote.email.caseInsensitiveCompare(local.email) == .orderedSame)
            }
            if !exists {
                if local.inviteStatus == "Awaiting" {
                    let acceptedMate = merged.contains { remote in
                        (!local.email.isEmpty && remote.email.caseInsensitiveCompare(local.email) == .orderedSame) ||
                        remote.name.localizedCaseInsensitiveCompare(local.name) == .orderedSame
                    }
                    if acceptedMate { continue }
                }
                merged.append(local)
            } else if let index = merged.firstIndex(where: {
                $0.id == local.id || (!local.email.isEmpty && $0.email.caseInsensitiveCompare(local.email) == .orderedSame)
            }) {
                if merged[index].inviteStatus != "Accepted", local.inviteStatus == "Accepted" {
                    merged[index].inviteStatus = "Accepted"
                }
            }
        }
        familyMembers = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        resolveLocalCurrentUser()
        absorbAcceptedPlaceholders()
    }

    private func upsertMember(_ member: FamilyMember) {
        if let index = familyMembers.firstIndex(where: { $0.id == member.id }) {
            familyMembers[index] = member
        } else {
            familyMembers.append(member)
        }
        familyMembers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if member.isCurrentUser { currentUser = member }
    }

    private func isIgnorableCloudError(_ error: Error) -> Bool {
        if isUnknownItem(error) { return true }
        let ns = error as NSError
        if ns.domain == CKError.errorDomain && ns.code == CKError.operationCancelled.rawValue { return true }
        if ns.code == NSURLErrorCancelled { return true }
        return error.localizedDescription.localizedCaseInsensitiveContains("cancelled")
    }

    private func isUnknownItem(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == CKError.errorDomain && ns.code == CKError.unknownItem.rawValue
    }

    private func cloudKitUserMessage(_ error: Error, action: String) -> String? {
        if isIgnorableCloudError(error) { return nil }
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("not marked queryable") {
            return "CloudKit schema: in CloudKit Console add a Queryable index on recordName for FamilyMember, then Save."
        }
        return "CloudKit \(action) failed: \(text)"
    }

    func subscribeToChatNotifications() async {
        guard !isLocalSandbox, let myID = currentUser?.id else { return }
        await FamilyNotifier.requestPermission()
        let allPredicate = NSPredicate(format: "notifyScope == %@", "all")
        let mentionPredicate = NSPredicate(format: "mentionedIDs CONTAINS %@", myID.uuidString)
        await saveChatSubscription(id: "family-chat-all", predicate: allPredicate, alert: "%1$@: %2$@")
        await saveChatSubscription(id: "family-chat-mention-\(myID.uuidString)", predicate: mentionPredicate, alert: "%1$@ mentioned you: %2$@")
    }

    private func saveChatSubscription(id: String, predicate: NSPredicate, alert: String) async {
        let subscription = CKQuerySubscription(
            recordType: ChatMessage.recordType,
            predicate: predicate,
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertLocalizationKey = alert
        info.alertLocalizationArgs = ["senderName", "content"]
        info.soundName = "default"
        info.shouldBadge = true
        info.shouldSendContentAvailable = true
        info.desiredKeys = ["senderName", "content", "senderID", "notifyScope", "mentionedIDs"]
        subscription.notificationInfo = info
        do {
            _ = try await activeDatabase.save(subscription)
        } catch {}
    }
}

struct PendingFamilyInvite: Identifiable, Hashable {
    let id: String
    let familyName: String
    let organizerName: String
    let email: String
    let shareURL: URL
}

enum FamilyNotifier {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

enum CloudKitServiceError: LocalizedError {
    case missingFamily
    case sandboxInvite
    case appleIDNotFound(String)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .missingFamily:
            return "Family group is not ready yet."
        case .appleIDNotFound(let email):
            return "Apple ID not found for \(email). Check the address, that they use iCloud, and that Find My / iCloud contacts discovery is allowed."
        case .sandboxInvite:
            return "iCloud invites need a paid Developer account. Use Add sandbox member instead."
        case .notAuthorized:
            return "Only the family organiser can invite people. Leave this family before creating a new one."
        }
    }
}

private struct LocalFamilySnapshot: Codable {
    var familyName: String
    var inviteCode: String
    var members: [FamilyMember]
    var events: [CalendarEvent]
    var messages: [ChatMessage]
    var recipes: [Recipe]
    var fridgeItems: [FridgeItem]
    var acceptedFoods: [ChildAcceptedFood]
    var participantEmails: [String]

    init(
        familyName: String,
        inviteCode: String,
        members: [FamilyMember],
        events: [CalendarEvent],
        messages: [ChatMessage],
        recipes: [Recipe] = [],
        fridgeItems: [FridgeItem] = [],
        acceptedFoods: [ChildAcceptedFood] = [],
        participantEmails: [String]
    ) {
        self.familyName = familyName
        self.inviteCode = inviteCode
        self.members = members
        self.events = events
        self.messages = messages
        self.recipes = recipes
        self.fridgeItems = fridgeItems
        self.acceptedFoods = acceptedFoods
        self.participantEmails = participantEmails
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        familyName = try c.decode(String.self, forKey: .familyName)
        inviteCode = try c.decode(String.self, forKey: .inviteCode)
        members = try c.decode([FamilyMember].self, forKey: .members)
        events = try c.decode([CalendarEvent].self, forKey: .events)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        fridgeItems = try c.decodeIfPresent([FridgeItem].self, forKey: .fridgeItems) ?? []
        acceptedFoods = try c.decodeIfPresent([ChildAcceptedFood].self, forKey: .acceptedFoods) ?? []
        participantEmails = try c.decode([String].self, forKey: .participantEmails)
    }
}

private struct LocalFamilyStore {
    private let key = "FamilyConnect.localSandbox.v1"

    func load() -> LocalFamilySnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LocalFamilySnapshot.self, from: data)
    }

    func save(_ snapshot: LocalFamilySnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct MealVote: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var requestedByID: UUID
    var requestedByName: String
    var voterIDs: [UUID]
    var isOpen: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        requestedByID: UUID,
        requestedByName: String,
        voterIDs: [UUID] = [],
        isOpen: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.requestedByID = requestedByID
        self.requestedByName = requestedByName
        self.voterIDs = voterIDs
        self.isOpen = isOpen
        self.createdAt = createdAt
    }

    var voteCount: Int { voterIDs.count }

    static let recordType = "MealVote"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["title"] = title
        record["requestedByID"] = requestedByID.uuidString
        record["requestedByName"] = requestedByName
        record["voterIDs"] = voterIDs.map(\.uuidString)
        record["isOpen"] = isOpen
        record["createdAt"] = createdAt
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> MealVote? {
        guard let title = record["title"] as? String else { return nil }
        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        let requestedByID = (record["requestedByID"] as? String).flatMap(UUID.init) ?? UUID()
        let voterStrings = record["voterIDs"] as? [String] ?? []
        return MealVote(
            id: id,
            title: title,
            requestedByID: requestedByID,
            requestedByName: record["requestedByName"] as? String ?? "",
            voterIDs: voterStrings.compactMap(UUID.init),
            isOpen: record["isOpen"] as? Bool ?? true,
            createdAt: record["createdAt"] as? Date ?? Date()
        )
    }
}

