import SwiftUI

struct MealSuggestView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [MealSuggestion] = []
    @State private var sentTitle: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Suggestions use the fridge and foods each child will eat. A later version can add AI when no saved recipe fits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if suggestions.isEmpty {
                    Section {
                        Text("Add fridge items and at least one recipe, then try again.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(suggestions) { item in
                        Section {
                            Text(item.title).font(.headline)
                            Text(item.reason).font(.subheadline)
                            if !item.matchedIngredients.isEmpty {
                                labeledList("In the fridge", item.matchedIngredients)
                            }
                            if !item.missingIngredients.isEmpty {
                                labeledList("Need to buy", item.missingIngredients)
                            }
                            if !item.refusingChildren.isEmpty {
                                Text("May not suit: \(item.refusingChildren.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Button {
                                Task {
                                    await cloudKitService.notifyParentsOfMealChoice(
                                        title: item.title,
                                        extra: item.missingIngredients.isEmpty ? "" : "Need to buy: \(item.missingIngredients.joined(separator: ", "))."
                                    )
                                    sentTitle = item.title
                                }
                            } label: {
                                Label(
                                    sentTitle == item.title ? "Sent to parents" : "Ask parents for this",
                                    systemImage: sentTitle == item.title ? "checkmark.circle.fill" : "paperplane"
                                )
                            }
                            .disabled(sentTitle == item.title)
                        }
                    }
                }
            }
            .navigationTitle("Tonight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                suggestions = MealSuggester.suggest(from: cloudKitService)
            }
        }
    }

    private func labeledList(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            Text(items.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
