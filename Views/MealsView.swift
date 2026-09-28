import SwiftUI
import VisionKit
import Foundation

struct MealsView: View {
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var section = 0
    @State private var showingAddRecipe = false
    @State private var showingImportRecipe = false
    @State private var showingAddFridge = false
    @State private var showingAddKidFood = false
    @State private var showingSuggest = false
    @State private var showingVote = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    Text("Plan").tag(0)
                    Text("Fridge").tag(1)
                    Text("Kids eat").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                switch section {
                case 1:
                    fridgeList
                case 2:
                    kidsEatList
                default:
                    recipeList
                }
            }
            .navigationTitle("Meals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if section == 0 {
                        Menu {
                            Button("Tonight") { showingSuggest = true }
                            Button("Meal vote") { showingVote = true }
                        } label: {
                            Text("Vote")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if section == 0 {
                        Menu {
                            Button("Add recipe") { showingAddRecipe = true }
                            Button("Import from website") { showingImportRecipe = true }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    } else {
                        Button {
                            if section == 1 { showingAddFridge = true } else { showingAddKidFood = true }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddRecipe) { AddRecipeSheet() }
            .sheet(isPresented: $showingImportRecipe) {
                ImportRecipeSheet(initialURL: cloudKitService.pendingRecipeURL ?? "")
            }
            .onChange(of: cloudKitService.pendingRecipeURL) { _, url in
                if url != nil { showingImportRecipe = true }
            }
            .sheet(isPresented: $showingAddFridge) { AddFridgeItemSheet() }
            .sheet(isPresented: $showingAddKidFood) { AddKidFoodSheet() }
            .sheet(isPresented: $showingSuggest) {
                MealSuggestView()
                    .environmentObject(cloudKitService)
            }
            .sheet(isPresented: $showingVote) {
                NavigationStack {
                    MealVoteView()
                        .environmentObject(cloudKitService)
                }
            }
            .refreshable { await cloudKitService.refreshAll() }
        }
    }

    private var recipeList: some View {
        Group {
            if cloudKitService.recipes.isEmpty {
                ContentUnavailableView(
                    "No recipes yet",
                    systemImage: "fork.knife",
                    description: Text("Add a recipe. FamilyConnect checks the fridge and what children will eat.")
                )
            } else {
                List {
                    ForEach(cloudKitService.recipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(recipe.title).font(.headline)
                                    Spacer()
                                    Text(recipe.mealType)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let date = recipe.plannedDate {
                                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Label("\(cloudKitService.inFridgeCount(for: recipe))/\(recipe.ingredientNames.count) in fridge", systemImage: "refrigerator")
                                    if !cloudKitService.childrenWhoMayRefuse(recipe).isEmpty {
                                        Label("check kids", systemImage: "exclamationmark.triangle")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await cloudKitService.deleteRecipe(cloudKitService.recipes[index])
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var fridgeList: some View {
        Group {
            if cloudKitService.fridgeItems.isEmpty {
                ContentUnavailableView(
                    "Fridge is empty",
                    systemImage: "refrigerator",
                    description: Text("Add what you have so recipes can use it.")
                )
            } else {
                List {
                    ForEach(cloudKitService.fridgeItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName).font(.headline)
                            if let expires = item.expiresOn {
                                Text("Use by \(expires.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(expires < Date() ? .red : .secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await cloudKitService.deleteFridgeItem(cloudKitService.fridgeItems[index])
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var kidsEatList: some View {
        let children = cloudKitService.childMembers
        return Group {
            if children.isEmpty {
                ContentUnavailableView(
                    "No children listed",
                    systemImage: "figure.and.child.holdinghands",
                    description: Text("Add a family member with the Child role, then list foods they will eat.")
                )
            } else {
                List {
                    ForEach(children) { child in
                        Section(child.name) {
                            let foods = cloudKitService.acceptedFoods(for: child.id)
                            if foods.isEmpty {
                                Text("No accepted ingredients yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(foods) { food in
                                    VStack(alignment: .leading) {
                                        Text(food.ingredientName)
                                        if !food.notes.isEmpty {
                                            Text(food.notes).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .onDelete { indexSet in
                                    Task {
                                        for index in indexSet {
                                            await cloudKitService.deleteAcceptedFood(foods[index])
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    @EnvironmentObject var cloudKitService: CloudKitService
    @Environment(\.dismiss) private var dismiss
    @State private var sentToParents = false
    @State private var showingEdit = false
    @State private var confirmDelete = false

    private var liveRecipe: Recipe {
        cloudKitService.recipes.first(where: { $0.id == recipe.id }) ?? recipe
    }

    var body: some View {
        List {
            Section("Ingredients") {
                ForEach(liveRecipe.ingredients) { ingredient in
                    HStack {
                        Text(ingredient.name)
                        Spacer()
                        if !ingredient.quantity.isEmpty {
                            Text(ingredient.quantity).foregroundStyle(.secondary)
                        }
                        Image(systemName: cloudKitService.fridgeContains(ingredient.name) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(cloudKitService.fridgeContains(ingredient.name) ? .green : .secondary)
                    }
                }
            }
            if !liveRecipe.notes.isEmpty {
                Section("Notes") { Text(liveRecipe.notes) }
            }
            let missing = cloudKitService.missingFridgeIngredients(for: liveRecipe)
            if !missing.isEmpty {
                Section("Need from shop") {
                    ForEach(missing, id: \.self) { Text($0) }
                }
            }
            let refusals = cloudKitService.childrenWhoMayRefuse(liveRecipe)
            if !refusals.isEmpty {
                Section("May not eat this") {
                    ForEach(refusals, id: \.id) { child in
                        Text(child.name)
                    }
                }
            }
            Section {
                Button {
                    Task {
                        await cloudKitService.notifyParentsOfMealChoice(title: liveRecipe.title)
                        sentToParents = true
                    }
                } label: {
                    Label(sentToParents ? "Sent to parents" : "I want this", systemImage: sentToParents ? "checkmark.circle.fill" : "paperplane")
                }
                .disabled(sentToParents)
            }
        }
        .navigationTitle(liveRecipe.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddRecipeSheet(existing: liveRecipe)
                .environmentObject(cloudKitService)
        }
        .alert("Delete this recipe?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await cloudKitService.deleteRecipe(liveRecipe)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(liveRecipe.title)
        }
    }
}

struct AddRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var cloudKitService: CloudKitService
    var existing: Recipe? = nil
    @State private var title = ""
    @State private var notes = ""
    @State private var mealType = "Dinner"
    @State private var planned = false
    @State private var plannedDate = Date()
    @State private var lines = "chicken\nrice\nbroccoli"

    let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Recipe name", text: $title)
                Picker("Meal", selection: $mealType) {
                    ForEach(mealTypes, id: \.self) { Text($0) }
                }
                Toggle("Plan on a day", isOn: $planned)
                if planned {
                    DatePicker("Date", selection: $plannedDate, displayedComponents: .date)
                }
                Section("Ingredients (one per line, optional amount after a comma)") {
                    TextEditor(text: $lines)
                        .frame(minHeight: 120)
                }
                TextField("Notes", text: $notes)
            }
            .navigationTitle(existing == nil ? "Add recipe" : "Edit recipe")
            .onAppear { loadExisting() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func loadExisting() {
        guard let existing else { return }
        title = existing.title
        notes = existing.notes
        mealType = existing.mealType
        if let date = existing.plannedDate {
            planned = true
            plannedDate = date
        }
        lines = existing.ingredients.map { item in
            item.quantity.isEmpty ? item.name : "\(item.name), \(item.quantity)"
        }.joined(separator: "\n")
    }

    private func save() {
        let ingredients = lines.split(whereSeparator: \.isNewline).compactMap { line -> RecipeIngredient? in
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            let parts = raw.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                return RecipeIngredient(name: parts[0], quantity: parts[1])
            }
            return RecipeIngredient(name: raw)
        }
        var recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes,
            ingredients: ingredients,
            plannedDate: planned ? plannedDate : nil,
            mealType: mealType
        )
        if let existing {
            recipe = Recipe(
                id: existing.id,
                title: title.trimmingCharacters(in: .whitespaces),
                notes: notes,
                ingredients: ingredients,
                plannedDate: planned ? plannedDate : nil,
                mealType: mealType
            )
        }
        Task {
            await cloudKitService.saveRecipe(recipe)
            dismiss()
        }
    }
}

struct ImportRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var cloudKitService: CloudKitService
    var initialURL: String = ""
    @State private var urlText = ""
    @State private var draft: ImportedRecipe?
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("https://…", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    Button("Fetch recipe") {
                        Task { await fetch() }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }

                if isLoading {
                    Section { ProgressView("Reading page…") }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
                if let draft {
                    Section("Title") { TextField("Title", text: bindingTitle) }
                    Section("Ingredients") {
                        ForEach(draft.ingredients) { item in
                            Text(item.quantity.isEmpty ? item.name : "\(item.name) \(item.quantity)")
                        }
                    }
                    Section("Notes") {
                        Text(draft.notes).font(.footnote)
                    }
                }
            }
            .navigationTitle("Import recipe")
            .onAppear {
                if urlText.isEmpty, !initialURL.isEmpty {
                    urlText = initialURL
                    Task { await fetch() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft == nil || draft?.title.trimmingCharacters(in: .whitespaces).isEmpty == true)
                }
            }
        }
    }

    private var bindingTitle: Binding<String> {
        Binding(
            get: { draft?.title ?? "" },
            set: { draft?.title = $0 }
        )
    }

    private func fetch() async {
        isLoading = true
        message = nil
        do {
            draft = try await RecipeImporter.importRecipe(from: urlText)
            message = "Check the ingredients, then Save."
        } catch {
            draft = nil
            message = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        guard let draft else { return }
        let recipe = Recipe(
            title: draft.title,
            notes: draft.notes,
            ingredients: draft.ingredients,
            mealType: "Dinner"
        )
        Task {
            await cloudKitService.saveRecipe(recipe)
            dismiss()
        }
    }
}

struct AddFridgeItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var hasExpiry = false
    @State private var expiresOn = Date().addingTimeInterval(86_400 * 3)
    @State private var showingScanner = false
    @State private var scanMessage: String?
    @State private var isLookingUp = false

    var body: some View {
        NavigationStack {
            Form {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan barcode", systemImage: "barcode.viewfinder")
                }
                if isLookingUp {
                    ProgressView("Looking up product…")
                }
                if let scanMessage {
                    Text(scanMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                TextField("Ingredient", text: $name)
                TextField("Amount", text: $quantity)
                TextField("Unit (optional)", text: $unit)
                Toggle("Has use-by date", isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker("Use by", selection: $expiresOn, displayedComponents: .date)
                }
            }
            .navigationTitle("Fridge item")
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { code in
                    Task { await lookupBarcode(code) }
                }
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let item = FridgeItem(
                            name: name.trimmingCharacters(in: .whitespaces),
                            quantity: quantity,
                            unit: unit,
                            expiresOn: hasExpiry ? expiresOn : nil
                        )
                        Task {
                            await cloudKitService.saveFridgeItem(item)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func lookupBarcode(_ code: String) async {
        isLookingUp = true
        scanMessage = nil
        do {
            let product = try await OpenFoodFactsService.lookup(barcode: code)
            name = product.name
            if !product.quantity.isEmpty {
                quantity = product.quantity
            }
            if !product.brand.isEmpty {
                scanMessage = product.brand
            }
        } catch {
            scanMessage = error.localizedDescription
        }
        isLookingUp = false
    }
}

struct AddKidFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var selectedChildIDs: Set<UUID> = []
    @State private var ingredient = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Food they will eat", text: $ingredient)
                TextField("Notes (optional)", text: $notes)
                Section("Assign to") {
                    if cloudKitService.childMembers.isEmpty {
                        Text("Add family members with the Child role first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(selectedChildIDs.count == cloudKitService.childMembers.count ? "Clear all" : "Select all") {
                            if selectedChildIDs.count == cloudKitService.childMembers.count {
                                selectedChildIDs.removeAll()
                            } else {
                                selectedChildIDs = Set(cloudKitService.childMembers.map(\.id))
                            }
                        }
                        ForEach(cloudKitService.childMembers) { child in
                            Button {
                                if selectedChildIDs.contains(child.id) {
                                    selectedChildIDs.remove(child.id)
                                } else {
                                    selectedChildIDs.insert(child.id)
                                }
                            } label: {
                                HStack {
                                    Text(child.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: selectedChildIDs.contains(child.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedChildIDs.contains(child.id) ? .blue : .secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kids will eat")
            .onAppear {
                if selectedChildIDs.isEmpty {
                    selectedChildIDs = Set(cloudKitService.childMembers.map(\.id))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = ingredient.trimmingCharacters(in: .whitespaces)
                        Task {
                            for childID in selectedChildIDs {
                                let food = ChildAcceptedFood(
                                    childID: childID,
                                    ingredientName: name,
                                    notes: notes
                                )
                                await cloudKitService.saveAcceptedFood(food)
                            }
                            dismiss()
                        }
                    }
                    .disabled(ingredient.trimmingCharacters(in: .whitespaces).isEmpty || selectedChildIDs.isEmpty)
                }
            }
        }
    }
}

struct MealVoteView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService

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

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, dismiss: dismiss)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let dismiss: DismissAction
        private var handled = false

        init(onCode: @escaping (String) -> Void, dismiss: DismissAction) {
            self.onCode = onCode
            self.dismiss = dismiss
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            if let first = addedItems.first {
                handle(first)
            }
        }

        private func handle(_ item: RecognizedItem) {
            guard !handled else { return }
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, !value.isEmpty {
                handled = true
                onCode(value)
                dismiss()
            }
        }
    }
}

