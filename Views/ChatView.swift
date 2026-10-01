import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var messageText = ""
    @State private var messageToEdit: ChatMessage?
    @State private var editText = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(cloudKitService.chatMessages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(message.senderName)
                                    .font(.headline)
                                Spacer()
                                Text(message.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(message.content)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isMine(message) {
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
                        .contextMenu {
                            if isMine(message) {
                                Button("Edit") {
                                    editText = message.content
                                    messageToEdit = message
                                }
                                Button("Delete", role: .destructive) {
                                    Task { await cloudKitService.deleteChatMessage(message) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    hideKeyboard()
                }

                if !mentionMatches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(mentionMatches, id: \.id) { member in
                                Button {
                                    insertMention(member.displayName)
                                } label: {
                                    Text(member.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.secondarySystemBackground))
                }

                HStack(spacing: 12) {
                    TextField("Type a message…", text: $messageText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }

                    if composerFocused {
                        Button(action: hideKeyboard) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.title3)
                        }
                        .accessibilityLabel("Hide keyboard")
                    }

                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Family Chat")
            .refreshable { await cloudKitService.refreshAll() }
            .task { await cloudKitService.refreshAll() }
            .sheet(item: $messageToEdit) { message in
                NavigationStack {
                    Form {
                        TextField("Message", text: $editText, axis: .vertical)
                            .lineLimit(3...10)
                    }
                    .navigationTitle("Edit message")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { messageToEdit = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task { await saveEdit(message) }
                            }
                            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        hideKeyboard()
                    } label: {
                        Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
                    }
                }
            }
        }
    }

    private var mentionQuery: String? {
        guard let at = messageText.lastIndex(of: "@") else { return nil }
        let after = messageText[messageText.index(after: at)...]
        if after.contains(where: { $0.isWhitespace }) { return nil }
        return String(after)
    }

    private var mentionMatches: [FamilyMember] {
        guard let query = mentionQuery else { return [] }
        let members = cloudKitService.familyMembers
        if query.isEmpty { return members }
        return members.filter { member in
            member.displayName.localizedCaseInsensitiveContains(query)
                || member.name.localizedCaseInsensitiveContains(query)
        }
    }

    private func insertMention(_ name: String) {
        guard let at = messageText.lastIndex(of: "@") else { return }
        let prefix = messageText[..<at]
        messageText = prefix + "@\(name) "
        composerFocused = true
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let me = cloudKitService.currentUser
        let mentioned = cloudKitService.familyMembers.filter { member in
            let names = [member.displayName, member.name, member.nickname].filter { !$0.isEmpty }
            return names.contains { text.localizedCaseInsensitiveContains("@" + $0) }
        }
        let message = ChatMessage(
            content: text,
            senderID: me?.id ?? UUID(),
            senderName: me?.displayName ?? "You",
            timestamp: Date(),
            notifyScope: mentioned.isEmpty ? "all" : mentioned.map { $0.id.uuidString }.joined(separator: ","),
            mentionedIDs: mentioned.map(\.id)
        )
        messageText = ""
        hideKeyboard()
        Task {
            await cloudKitService.saveChatMessage(message)
        }
    }

    private func isMine(_ message: ChatMessage) -> Bool {
        guard let me = cloudKitService.currentUser else { return false }
        return message.senderID == me.id
            || message.senderName == me.displayName
            || message.senderName == me.name
            || message.senderName == "You"
    }

    private func saveEdit(_ message: ChatMessage) async {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let updated = ChatMessage(
            id: message.id,
            content: text,
            senderID: message.senderID,
            senderName: message.senderName,
            timestamp: message.timestamp,
            notifyScope: message.notifyScope,
            mentionedIDs: message.mentionedIDs
        )
        await cloudKitService.saveChatMessage(updated)
        messageToEdit = nil
        hideKeyboard()
    }

    private func hideKeyboard() {
        composerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ChatView()
        .environmentObject(CloudKitService())
}
