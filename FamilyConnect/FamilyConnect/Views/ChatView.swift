//
//  ChatView.swift
//  FamilyConnect
//
//  Created by Nick Skewes on 16/9/2026.
//


import SwiftUI

struct ChatView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var messageText = ""
    @State private var showingAddMember = false
    
    var body: some View {
        NavigationStack {
            VStack {
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
                    }
                }
                .listStyle(.plain)
                
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 36)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Family Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddMember = true }) {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMember) {
                AddMemberSheet(isPresented: $showingAddMember, cloudKitService: cloudKitService)
            }
        }
    }
    
    private func sendMessage() {
        let message = ChatMessage(
            content: messageText,
            senderID: UUID(),
            senderName: "You"
        )
        cloudKitService.saveChatMessage(message)
        messageText = ""
    }
}

struct AddMemberSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var cloudKitService: CloudKitService
    
    @State private var memberName = ""
    @State private var memberEmail = ""
    @State private var memberPhone = ""
    @State private var memberRole = "Family"
    
    let roles = ["Parent", "Child", "Guardian", "Family"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Member Details") {
                    TextField("Name", text: $memberName)
                    TextField("Email", text: $memberEmail)
                    TextField("Phone", text: $memberPhone)
                    Picker("Role", selection: $memberRole) {
                        ForEach(roles, id: \.self) { role in
                            Text(role).tag(role)
                        }
                    }
                }
                
                Section {
                    Button("Add Member") {
                        let member = FamilyMember(
                            name: memberName,
                            email: memberEmail,
                            phoneNumber: memberPhone,
                            role: memberRole
                        )
                        cloudKitService.saveFamilyMember(member)
                        isPresented = false
                    }
                    .disabled(memberName.isEmpty || memberEmail.isEmpty)
                }
            }
            .navigationTitle("Add Family Member")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(CloudKitService())
}