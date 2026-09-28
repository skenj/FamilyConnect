import Foundation
import CloudKit

struct FridgeItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var quantity: String
    var unit: String
    var expiresOn: Date?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        quantity: String = "1",
        unit: String = "",
        expiresOn: Date? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.expiresOn = expiresOn
        self.addedAt = addedAt
    }

    var displayName: String {
        let qty = [quantity, unit].filter { !$0.isEmpty }.joined(separator: " ")
        return qty.isEmpty ? name : "\(name) · \(qty)"
    }

    static let recordType = "FridgeItem"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["name"] = name
        record["quantity"] = quantity
        record["unit"] = unit
        record["expiresOn"] = expiresOn
        record["addedAt"] = addedAt
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> FridgeItem? {
        guard let name = record["name"] as? String else { return nil }
        return FridgeItem(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            name: name,
            quantity: record["quantity"] as? String ?? "1",
            unit: record["unit"] as? String ?? "",
            expiresOn: record["expiresOn"] as? Date,
            addedAt: record["addedAt"] as? Date ?? Date()
        )
    }
}

struct ChildAcceptedFood: Identifiable, Codable, Hashable {
    let id: UUID
    var childID: UUID
    var ingredientName: String
    var notes: String

    init(id: UUID = UUID(), childID: UUID, ingredientName: String, notes: String = "") {
        self.id = id
        self.childID = childID
        self.ingredientName = ingredientName
        self.notes = notes
    }

    static let recordType = "ChildAcceptedFood"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["childID"] = childID.uuidString
        record["ingredientName"] = ingredientName
        record["notes"] = notes
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> ChildAcceptedFood? {
        guard
            let ingredientName = record["ingredientName"] as? String,
            let childRaw = record["childID"] as? String,
            let childID = UUID(uuidString: childRaw)
        else { return nil }
        return ChildAcceptedFood(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            childID: childID,
            ingredientName: ingredientName,
            notes: record["notes"] as? String ?? ""
        )
    }
}

struct RecipeIngredient: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var quantity: String

    init(id: UUID = UUID(), name: String, quantity: String = "") {
        self.id = id
        self.name = name
        self.quantity = quantity
    }
}

struct Recipe: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String
    var ingredients: [RecipeIngredient]
    var plannedDate: Date?
    var mealType: String

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        ingredients: [RecipeIngredient] = [],
        plannedDate: Date? = nil,
        mealType: String = "Dinner"
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.ingredients = ingredients
        self.plannedDate = plannedDate
        self.mealType = mealType
    }

    var ingredientNames: [String] {
        ingredients.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static let recordType = "Recipe"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["title"] = title
        record["notes"] = notes
        record["mealType"] = mealType
        record["plannedDate"] = plannedDate
        if let data = try? JSONEncoder().encode(ingredients), let json = String(data: data, encoding: .utf8) {
            record["ingredientsJSON"] = json
        }
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> Recipe? {
        guard let title = record["title"] as? String else { return nil }
        var ingredients: [RecipeIngredient] = []
        if let json = record["ingredientsJSON"] as? String, let data = json.data(using: .utf8) {
            ingredients = (try? JSONDecoder().decode([RecipeIngredient].self, from: data)) ?? []
        }
        return Recipe(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            title: title,
            notes: record["notes"] as? String ?? "",
            ingredients: ingredients,
            plannedDate: record["plannedDate"] as? Date,
            mealType: record["mealType"] as? String ?? "Dinner"
        )
    }
}
