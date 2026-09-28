import SwiftUI

struct MealVoteView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService

    private var isChild: Bool {
        cloudKitService.currentUser?.role.caseInsensitiveCompare("Child") == .orderedSame
    }

    var body: some View {
        List {
            if cloudKitService.openMealVotes.isEmpty {
                Text("No open meal vote. When someone taps I want this, it appears here.")
                    .foregroundStyle(.secondary)
            } else {
                Section("Kids vote") {
                    ForEach(cloudKitService.openMealVotes) { vote in
                        Button {
                            Task { await cloudKitService.castMealVote(vote.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(vote.title).font(.headline).foregroundStyle(.primary)
                                    Text("Asked by \(vote.requestedByName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(vote.voteCount)")
                                    .font(.title3.weight(.semibold))
                                if let me = cloudKitService.currentUser, vote.voterIDs.contains(me.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                if cloudKitService.canAddFamilyMembers {
                    Section {
                        Button("Close vote and tell the family") {
                            Task { await cloudKitService.closeMealVote() }
                        }
                    } footer: {
                        Text("Parents get every new request in Chat. Closing sends the winner to everyone.")
                    }
                }
            }
        }
        .navigationTitle("Meal vote")
        .refreshable { await cloudKitService.refreshAll() }
    }
}
