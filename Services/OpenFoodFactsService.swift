import Foundation

struct ScannedFoodProduct: Sendable {
    let barcode: String
    let name: String
    let brand: String
    let quantity: String
}

enum OpenFoodFactsService {
    static func lookup(barcode: String) async throws -> ScannedFoodProduct {
        let code = barcode.filter(\.isNumber)
        guard code.count >= 8 else {
            throw URLError(.badURL)
        }
        var request = URLRequest(
            url: URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,product_name_en,generic_name,brands,quantity")!
        )
        request.setValue("FamilyConnect/1.0 (familyconnect@local)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = json?["status"] as? Int ?? 0
        guard status == 1, let product = json?["product"] as? [String: Any] else {
            throw OpenFoodFactsError.notFound
        }
        let name = [
            product["product_name"] as? String,
            product["product_name_en"] as? String,
            product["generic_name"] as? String,
            product["brands"] as? String
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Unknown product"
        return ScannedFoodProduct(
            barcode: code,
            name: name,
            brand: (product["brands"] as? String) ?? "",
            quantity: (product["quantity"] as? String) ?? ""
        )
    }
}

enum OpenFoodFactsError: LocalizedError {
    case notFound
    var errorDescription: String? {
        "No product found for that barcode. You can type the name instead."
    }
}
