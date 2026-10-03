import SwiftUI

// MARK: - ChatView (WhatsApp-style)
struct ChatView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var showNewChat = false
    @State private var selectedThread: ChatThread?
    @State private var privateThreads: [ChatThread] = []

    private var me: FamilyMember? { cloudKitService.currentUser }

    private var familyThread: ChatThread {
        let msgs = cloudKitService.chatMessages.filter { $0.threadID == "family" }
        let latest = msgs.max(by: { $0.timestamp < $1.timestamp })
        let unread = msgs.filter {
            !$0.isRead(by: me?.id ?? UUID()) && $0.senderID != (me?.id ?? UUID())
        }.count
        return ChatThread(id: "family", name: "Family Chat",
                          latestMessage: latest, unreadCount: unread, isFamily: true)
    }

    private var totalPrivateUnread: Int {
        privateThreads.reduce(0) { $0 + $1.unreadCount }
    }

    // Recompute thread list from chatMessages
    private func rebuildThreads() {
        guard let me else { privateThreads = []; return }

        let privateMessages = cloudKitService.chatMessages.filter {
            $0.threadID != "family" && $0.threadID.contains(me.id.uuidString)
        }

        var threadMap: [String: [ChatMessage]] = [:]
        for msg in privateMessages {
            threadMap[msg.threadID, default: []].append(msg)
        }

        privateThreads = threadMap.compactMap { threadID, messages -> ChatThread? in
            guard let latest = messages.max(by: { $0.timestamp < $1.timestamp }) else { return nil }

            // Find the other participant from familyMembers
            let otherMember = cloudKitService.familyMembers.first { member in
                member.id != me.id && threadID.contains(member.id.uuidString)
            }

            let unread = messages.filter {
                !$0.isRead(by: me.id) && $0.senderID != me.id
            }.count

            return ChatThread(
                id: threadID,
                name: otherMember?.displayName ?? "Family Member",
                latestMessage: latest,
                unreadCount: unread,
                isFamily: false
            )
        }
        .sorted { $0.latestMessage!.timestamp > $1.latestMessage!.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Family Chat row (always visible, tappable)
                    familyChatRow
                        .onTapGesture { selectedThread = familyThread }

                    Divider()

                    // MARK: - Direct Messages section
                    VStack(spacing: 0) {
                        // Section header
                        HStack {
                            Text("Direct Messages")
                                .font(.headline)
                            if totalPrivateUnread > 0 {
                                Text("\(totalPrivateUnread)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.red).clipShape(Capsule())
                            }
                            Spacer()
                            Button(action: { showNewChat = true }) {
                                Image(systemName: "square.and.pencil")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        if privateThreads.isEmpty {
                            // Empty state
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("No direct messages yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Button("Start a chat") { showNewChat = true }
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else {
                            // WhatsApp-style chat links — NOT a List, avoids scroll conflicts
                            VStack(spacing: 0) {
                                ForEach(privateThreads) { thread in
                                    ChatThreadRow(thread: thread)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedThread = thread }
                                    Divider().padding(.leading, 76)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedThread) { thread in
                ChatConversationView(thread: thread, cloudKitService: cloudKitService)
            }
            .sheet(isPresented: $showNewChat) {
                NewChatSheet(cloudKitService: cloudKitService) { member in
                    guard let me else { return }
                    let threadID = ChatMessage.privateThreadID(between: me.id, and: member.id)
                    selectedThread = ChatThread(
                        id: threadID, name: member.displayName,
                        latestMessage: nil, unreadCount: 0, isFamily: false
                    )
                    showNewChat = false
                }
            }
            .onAppear { rebuildThreads() }
            .onChange(of: cloudKitService.chatMessages) { rebuildThreads() }
            .onChange(of: cloudKitService.familyMembers) { rebuildThreads() }
            .task { await cloudKitService.refreshAll() }
            .refreshable { await cloudKitService.refreshAll() }
        }
    }

    // MARK: - Family chat row (pinned at top, WhatsApp style)
    private var familyChatRow: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 54, height: 54)
                Image(systemName: "person.3.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Family Chat")
                        .font(.headline)
                    Spacer()
                    if let ts = familyThread.latestMessage?.timestamp {
                        Text(timeLabel(ts))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text(familyThread.latestMessage.map {
                        "\($0.senderName): \($0.content)"
                    } ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if familyThread.unreadCount > 0 {
                        Text("\(familyThread.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private func timeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - WhatsApp-style chat thread row
struct ChatThreadRow: View {
    let thread: ChatThread

    var body: some View {
        HStack(spacing: 14) {
            // Avatar with initial
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 54, height: 54)
                Text(thread.name.prefix(1).uppercased())
                    .font(.title3.bold())
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(thread.name).font(.headline)
                    Spacer()
                    if let ts = thread.latestMessage?.timestamp {
                        Text(timeLabel(ts))
                            .font(.caption)
                            .foregroundColor(thread.unreadCount > 0 ? .blue : .secondary)
                    }
                }
                HStack {
                    Text(thread.latestMessage?.content ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundColor(thread.unreadCount > 0 ? .primary : .secondary)
                        .fontWeight(thread.unreadCount > 0 ? .medium : .regular)
                        .lineLimit(1)
                    Spacer()
                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func timeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - New Chat Sheet
struct NewChatSheet: View {
    let cloudKitService: CloudKitService
    let onSelect: (FamilyMember) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var me: FamilyMember? { cloudKitService.currentUser }
    private var candidates: [FamilyMember] {
        let others = cloudKitService.familyMembers.filter { $0.id != me?.id }
        if search.isEmpty { return others }
        return others.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationView {
            List(candidates) { member in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(member.isParent ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Text(member.displayName.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(member.isParent ? .blue : .green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName).font(.headline)
                        Text(member.role.capitalized).font(.caption).foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(member) }
            }
            .searchable(text: $search, prompt: "Search family members")
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Full Conversation View
struct ChatConversationView: View {
    let thread: ChatThread
    let cloudKitService: CloudKitService
    @State private var messageText = ""
    @State private var threadMessages: [ChatMessage] = []
    @State private var messageToEdit: ChatMessage?
    @State private var editText = ""
    @State private var isLoadingOlder = false
    @State private var hasMoreMessages = true
    // Fix: tap anywhere to dismiss keyboard
    @FocusState private var composerFocused: Bool

    private var me: FamilyMember? { cloudKitService.currentUser }

    private var participants: [UUID] {
        if thread.isFamily { return cloudKitService.familyMembers.map(\.id) }
        let parts = thread.id.replacingOccurrences(of: "private-", with: "")
            .components(separatedBy: "-")
        return stride(from: 0, to: parts.count, by: 5).compactMap { i -> UUID? in
            UUID(uuidString: parts[i..<min(i+5, parts.count)].joined(separator: "-"))
        }
    }

    private var mentionMatches: [FamilyMember] {
        guard thread.isFamily, let query = mentionQuery else { return [] }
        if query.isEmpty { return cloudKitService.familyMembers }
        return cloudKitService.familyMembers.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    private var mentionQuery: String? {
        guard let at = messageText.lastIndex(of: "@") else { return nil }
        let after = messageText[messageText.index(after: at)...]
        if after.contains(where: { $0.isWhitespace }) { return nil }
        return String(after)
    }

    private func refreshMessages() {
        threadMessages = cloudKitService.chatMessages
            .filter { $0.threadID == thread.id }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list — tap outside keyboard to dismiss
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if hasMoreMessages && !threadMessages.isEmpty {
                            Button(action: loadOlder) {
                                if isLoadingOlder {
                                    ProgressView().frame(maxWidth: .infinity).padding()
                                } else {
                                    Text("Load older messages")
                                        .font(.caption).foregroundColor(.blue)
                                        .frame(maxWidth: .infinity).padding()
                                }
                            }
                        }

                        ForEach(threadMessages) { message in
                            MessageBubble(
                                message: message,
                                isMe: message.senderID == me?.id,
                                showName: thread.isFamily,
                                participants: participants
                            )
                            .id(message.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if message.senderID == me?.id {
                                    Button("Delete", role: .destructive) {
                                        Task { await cloudKitService.deleteChatMessage(message) }
                                    }
                                    Button("Edit") {
                                        editText = message.content
                                        messageToEdit = message
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                // Fix: tap on messages area dismisses keyboard
                .onTapGesture { composerFocused = false }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: threadMessages.count) {
                    if let last = threadMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = threadMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Mention suggestions
            if !mentionMatches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mentionMatches) { member in
                            Button { insertMention(member.displayName) } label: {
                                Text(member.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                .background(Color(.secondarySystemBackground))
            }

            // Composer bar
            HStack(spacing: 10) {
                TextField("Message…", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($composerFocused)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundColor(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? .secondary : .blue
                        )
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(thread.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshMessages() }
        .onChange(of: cloudKitService.chatMessages) { refreshMessages() }
        .task { await cloudKitService.markThreadAsRead(threadID: thread.id) }
        .sheet(item: $messageToEdit) { message in
            NavigationStack {
                Form {
                    TextField("Message", text: $editText, axis: .vertical).lineLimit(3...10)
                }
                .navigationTitle("Edit message")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { messageToEdit = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await saveEdit(message) } }
                            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func loadOlder() {
        guard !isLoadingOlder else { return }
        isLoadingOlder = true
        Task {
            let hasMore = await cloudKitService.loadOlderMessages(threadID: thread.id)
            hasMoreMessages = hasMore
            isLoadingOlder = false
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let me else { return }
        let mentioned = thread.isFamily
            ? cloudKitService.familyMembers.filter { member in
                [member.displayName, member.name].contains {
                    text.localizedCaseInsensitiveContains("@" + $0)
                }
              }
            : []
        let msg = ChatMessage(
            content: text,
            senderID: me.id,
            senderName: me.displayName,
            notifyScope: thread.isFamily
                ? (mentioned.isEmpty ? "all" : mentioned.map { $0.id.uuidString }.joined(separator: ","))
                : "mention",
            mentionedIDs: mentioned.map(\.id),
            threadID: thread.id
        )
        messageText = ""
        composerFocused = false

        // Instant local update
        threadMessages.append(msg)

        Task {
            if thread.isFamily {
                await cloudKitService.saveChatMessage(msg)
            } else {
                await cloudKitService.savePrivateChatMessage(msg)
            }
        }
    }

    private func insertMention(_ name: String) {
        guard let at = messageText.lastIndex(of: "@") else { return }
        messageText = messageText[..<at] + "@\(name) "
        composerFocused = true
    }

    private func saveEdit(_ message: ChatMessage) async {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let updated = ChatMessage(
            id: message.id, content: text, senderID: message.senderID,
            senderName: message.senderName, timestamp: message.timestamp,
            notifyScope: message.notifyScope, mentionedIDs: message.mentionedIDs,
            threadID: message.threadID, readBy: message.readBy
        )
        await cloudKitService.saveChatMessage(updated)
        messageToEdit = nil
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    let isMe: Bool
    let showName: Bool
    let participants: [UUID]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer(minLength: 60) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                if showName && !isMe {
                    Text(message.senderName)
                        .font(.caption).foregroundColor(.secondary).padding(.leading, 4)
                }
                Text(message.content)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isMe ? Color.blue : Color(.tertiarySystemFill))
                    .foregroundColor(isMe ? .white : .primary)
                    .cornerRadius(18, corners: isMe
                        ? [.topLeft, .topRight, .bottomLeft]
                        : [.topLeft, .topRight, .bottomRight])
                HStack(spacing: 3) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2).foregroundColor(.secondary)
                    if isMe {
                        ReceiptView(status: message.receiptStatus(participants: participants))
                    }
                }
                .padding(.horizontal, 4)
            }
            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
    }
}

// MARK: - Read receipt ticks
struct ReceiptView: View {
    let status: ChatMessage.ReceiptStatus
    var body: some View {
        switch status {
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2).foregroundColor(.secondary)
        case .readSome:
            Image(systemName: "checkmark.circle")
                .font(.caption2).foregroundColor(.secondary)
        case .readAll:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2).foregroundColor(.blue)
        }
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

// MARK: - Thread model
struct ChatThread: Identifiable, Hashable {
    let id: String
    let name: String
    let latestMessage: ChatMessage?
    let unreadCount: Int
    let isFamily: Bool
}

#Preview {
    ChatView().environmentObject(CloudKitService())
}
