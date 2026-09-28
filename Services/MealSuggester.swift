import Foundation

struct MealSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let reason: String
    let matchedIngredients: [String]
    let missingIngredients: [String]
    let refusingChildren: [String]
    let recipe: Recipe?
    let score: Double
}

@MainActor
enum MealSuggester {
    static func suggest(from service: CloudKitService, limit: Int = 5) -> [MealSuggestion] {
        let recipes = service.recipes
        if recipes.isEmpty {
            return fridgeOnlyIdeas(from: service)
        }

        let ranked = recipes.map { recipe -> MealSuggestion in
            let have = recipe.ingredientNames.filter { service.fridgeContains($0) }
            let missing = service.missingFridgeIngredients(for: recipe)
            let refusers = service.childrenWhoMayRefuse(recipe).map(\.displayName)
            let total = max(recipe.ingredientNames.count, 1)
            var score = Double(have.count) / Double(total)
            if !refusers.isEmpty { score -= 0.15 }
            if have.isEmpty { score -= 0.4 }

            let reason: String
            if missing.isEmpty && refusers.isEmpty {
                reason = "You have the ingredients and it fits what the kids eat."
            } else if missing.isEmpty {
                reason = "You have the ingredients. \(refusers.joined(separator: ", ")) may not eat some items."
            } else if have.isEmpty {
                reason = "Saved recipe. You would need to shop for the ingredients."
            } else {
                reason = "You already have \(have.count) of \(total) ingredients."
            }

            return MealSuggestion(
                title: recipe.title,
                reason: reason,
                matchedIngredients: have,
                missingIngredients: missing,
                refusingChildren: refusers,
                recipe: recipe,
                score: score
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.missingIngredients.count < rhs.missingIngredients.count
            }
            return lhs.score > rhs.score
        }

        return Array(ranked.prefix(limit))
    }

    private static func fridgeOnlyIdeas(from service: CloudKitService) -> [MealSuggestion] {
        let names = service.fridgeItems.map(\.name).filter { !$0.isEmpty }
        guard !names.isEmpty else { return [] }
        let listed = names.prefix(6).joined(separator: ", ")
        return [
            MealSuggestion(
                title: "Cook with what is in the fridge",
                reason: "No saved recipes yet. You currently have: \(listed).",
                matchedIngredients: names,
                missingIngredients: [],
                refusingChildren: [],
                recipe: nil,
                score: 0.5
            )
        ]
    }
}
