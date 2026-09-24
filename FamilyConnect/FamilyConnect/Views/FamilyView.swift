import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var showingAddMember = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if cloudKitService.familyMembers.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.gray)
                        
                        Text("No Family Members Yet")
                            .font(.headline)
                        
                        Text("Add your family members to get started")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button(action: { showingAddMember = true }) {
                            Label("Add Family Member", systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(8)
                        }
                        .padding()
                        
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(cloudKitService.familyMembers) { member in
                            NavigationLink(destination: MemberDetailView(member: member)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(member.name)
                                            .font(.headline)
                                        
                                        HStack(spacing: 8) {
                                            Text(member.role)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            Divider()
                                                .frame(height: 12)
                                            
                                            Text(member.email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.gray)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Family Members")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.title3)
                    }
                    
                    Button(action: { showingAddMember = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddMember) {
                AddFamilyMemberSheet(
                    isPresented: $showingAddMember,
                    cloudKitService: cloudKitService
                )
            }
            .sheet(isPresented: $showingSettings) {
                FamilySettingsSheet(isPresented: $showingSettings)
            }
        }
    }
}

struct MemberDetailView: View {
    let member: FamilyMember
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                
                Text(member.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(member.role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            Form {
                Section("Contact Information") {
                    LabeledContent("Email") {
                        Text(member.email)
                            .textSelection(.enabled)
                    }
                    
                    LabeledContent("Phone") {
                        Text(member.phoneNumber)
                            .textSelection(.enabled)
                    }
                }
                
                Section("Member Details") {
                    LabeledContent("Role") {
                        Text(member.role)
                    }
                    
                    LabeledContent("Added") {
                        Text(member.dateAdded, style: .date)
                    }
                }
            }
            
            Spacer()
        }
        .navigationTitle("Member Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddFamilyMemberSheet: View {
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
                Section("Member Information") {
                    TextField("Full Name", text: $memberName)
                    TextField("Email Address", text: $memberEmail)
                        .textContentType(.emailAddress)
                    TextField("Phone Number", text: $memberPhone)
                        .textContentType(.telephoneNumber)
                }
                
                Section("Role") {
                    Picker("Select Role", selection: $memberRole) {
                        ForEach(roles, id: \.self) { role in
                            Text(role).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
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
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Add Family Member")
            .navigationBarTitleDisplayMode(.inline)
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

struct FamilySettingsSheet: View {
    @Binding var isPresented: Bool
    @State private var familyGroupName = "My Family"
    @State private var allowNewMembers = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Family Group") {
                    TextField("Group Name", text: $familyGroupName)
                }
                
                Section("Permissions") {
                    Toggle("Allow members to add new people", isOn: $allowNewMembers)
                }
                
                Section {
                    Text("Manage your family group settings and permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Family Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    FamilyView()
        .environmentObject(CloudKitService())
}
