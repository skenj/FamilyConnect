import Foundation

struct ImportedRecipe: Sendable {
    var title: String
    var notes: String
    var ingredients: [RecipeIngredient]
    var sourceURL: String
}

enum RecipeImportError: LocalizedError {
    case invalidURL
    case fetchFailed
    case noRecipeFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That does not look like a web address."
        case .fetchFailed:
            return "Could not load the page. Check the link and your connection."
        case .noRecipeFound:
            return "No recipe was found on that page. You can still add it by hand."
        }
    }
}

enum RecipeImporter {
    static func importRecipe(from rawURL: String) async throws -> ImportedRecipe {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else {
            throw RecipeImportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            throw RecipeImportError.fetchFailed
        }

        if let parsed = parseJSONLD(in: html, source: trimmed) {
            return parsed
        }
        if let parsed = parseFallbackHTML(html, source: trimmed) {
            return parsed
        }
        throw RecipeImportError.noRecipeFound
    }

    private static func parseJSONLD(in html: String, source: String) -> ImportedRecipe? {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let json = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let recipe = findRecipe(in: object) {
                return imported(from: recipe, source: source)
            }
        }
        return nil
    }

    private static func findRecipe(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if isRecipe(dict) { return dict }
            if let graph = dict["@graph"] as? [Any] {
                for item in graph {
                    if let found = findRecipe(in: item) { return found }
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let found = findRecipe(in: item) { return found }
            }
        }
        return nil
    }

    private static func isRecipe(_ dict: [String: Any]) -> Bool {
        let type = dict["@type"]
        if let text = type as? String { return text.caseInsensitiveCompare("Recipe") == .orderedSame }
        if let list = type as? [Any] {
            return list.contains { ($0 as? String)?.caseInsensitiveCompare("Recipe") == .orderedSame }
        }
        return dict["recipeIngredient"] != nil
    }

    private static func imported(from recipe: [String: Any], source: String) -> ImportedRecipe {
        let title = stringValue(recipe["name"]) ?? "Imported recipe"
        var notesParts: [String] = []
        if let description = stringValue(recipe["description"]), !description.isEmpty {
            notesParts.append(description)
        }
        let instructions = flattenInstructions(recipe["recipeInstructions"])
        if !instructions.isEmpty {
            notesParts.append("Steps:\n" + instructions)
        }
        notesParts.append("Source: \(source)")

        let ingredientLines = stringArray(recipe["recipeIngredient"])
        let ingredients = ingredientLines.compactMap { line -> RecipeIngredient? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return splitIngredient(trimmed)
        }

        return ImportedRecipe(
            title: title,
            notes: notesParts.joined(separator: "\n\n"),
            ingredients: ingredients,
            sourceURL: source
        )
    }

    private static func parseFallbackHTML(_ html: String, source: String) -> ImportedRecipe? {
        let title = firstMatch(#"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)"#, in: html)
            ?? firstMatch(#"<title>(.*?)</title>"#, in: html)
            ?? "Imported recipe"
        var ingredients: [RecipeIngredient] = []
        if let listBlock = firstMatch(#"(?is)<ul[^>]*ingredient[^>]*>(.*?)</ul>"#, in: html)
            ?? firstMatch(#"(?is)<ol[^>]*ingredient[^>]*>(.*?)</ol>"#, in: html) {
            let itemRegex = try? NSRegularExpression(pattern: #"(?is)<li[^>]*>(.*?)</li>"#)
            let ns = listBlock as NSString
            itemRegex?.matches(in: listBlock, range: NSRange(location: 0, length: ns.length)).forEach { match in
                let raw = stripTags(ns.substring(with: match.range(at: 1)))
                if !raw.isEmpty { ingredients.append(splitIngredient(raw)) }
            }
        }
        guard !ingredients.isEmpty else { return nil }
        return ImportedRecipe(
            title: stripTags(title),
            notes: "Source: \(source)",
            ingredients: ingredients,
            sourceURL: source
        )
    }

    private static func splitIngredient(_ line: String) -> RecipeIngredient {
        let cleaned = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return RecipeIngredient(name: cleaned, quantity: "")
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let dict = value as? [String: Any] { return stringValue(dict["name"]) ?? stringValue(dict["text"]) }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let text = value as? String { return [text] }
        if let list = value as? [Any] {
            return list.compactMap { stringValue($0) }
        }
        return []
    }

    private static func flattenInstructions(_ value: Any?) -> String {
        if let text = value as? String { return stripTags(text) }
        if let list = value as? [Any] {
            return list.enumerated().compactMap { index, item in
                let line = stringValue(item) ?? {
                    if let dict = item as? [String: Any] {
                        return stringValue(dict["text"]) ?? stringValue(dict["name"])
                    }
                    return nil
                }()
                guard let line, !line.isEmpty else { return nil }
                return "\(index + 1). \(stripTags(line))"
            }.joined(separator: "\n")
        }
        if let dict = value as? [String: Any] {
            return flattenInstructions(dict["itemListElement"] ?? dict["text"])
        }
        return ""
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
