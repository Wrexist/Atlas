import SwiftUI

/// Reuses the food search service without logging a second meal.
struct ReplaceScannedFoodSheet: View {
    let grams: Double
    let onReplace: (ScannedProduct) -> Void
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ScannedProduct] = []
    @State private var selected: ScannedProduct?
    @State private var loading = false
    @State private var errorText: String?
    @State private var retry = 0

    private var local: [ScannedProduct] {
        dataStore.profile.customFoods.filter {
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }.map { $0.toScannedProduct() }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the correct food. Your current \(grams.formatted()) g portion stays the same; nutrition is replaced.")
                        .font(AppFont.callout)
                }
                if !local.isEmpty { Section("Your foods") { rows(local) } }
                if loading { ProgressView("Searching foods…") }
                if let errorText {
                    Text(errorText)
                    Button("Retry search") { retry += 1 }
                }
                if !results.isEmpty { Section("Food database") { rows(results) } }
                if !loading && errorText == nil && results.isEmpty && local.isEmpty {
                    Text(query.count < 2 ? "Type at least two characters to search." : "No matches. Try another food name.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, prompt: "Find the correct food")
            .navigationTitle("Replace food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if let selected, let meal = selected.loggable(for: .grams(grams)) {
                    VStack(spacing: Spacing.sm) {
                        Text("\(selected.name) · \(meal.calories) kcal for \(grams.formatted()) g")
                            .font(AppFont.callout).multilineTextAlignment(.center)
                        GlassButton(title: "Replace food", isFullWidth: true) {
                            onReplace(selected)
                            dismiss()
                        }
                    }.padding(Spacing.screenPadding).background(AppColor.background)
                }
            }
            .task(id: "\(query)|\(retry)") { await search() }
        }
    }

    private func rows(_ products: [ScannedProduct]) -> some View {
        ForEach(products, id: \.barcode) { product in
            Button { selected = product } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(product.name).foregroundStyle(AppColor.textPrimary)
                        if let brand = product.brand { Text(brand).font(AppFont.caption) }
                        Text("\(product.per100g.calories.formatted()) kcal / 100 g").font(AppFont.caption)
                    }
                    Spacer()
                    if selected?.barcode == product.barcode { Image(systemName: "checkmark") }
                }.frame(minHeight: 44)
            }.accessibilityAddTraits(selected?.barcode == product.barcode ? .isSelected : [])
        }
    }

    private func search() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []
        errorText = nil
        selected = nil
        guard value.count >= OpenFoodFactsService.minimumSearchQueryLength else { loading = false; return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(500))
            let found = try await OpenFoodFactsService.shared.search(query: value)
            try Task.checkCancellation()
            var seen = Set<String>()
            results = found.filter { seen.insert($0.barcode).inserted }
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            loading = false
            errorText = "Couldn't search the food database. Retry, or choose one of your saved foods."
        }
    }
}
