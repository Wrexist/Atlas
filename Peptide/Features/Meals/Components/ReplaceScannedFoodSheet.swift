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

    private var gramsText: String { grams.formatted(.number.precision(.fractionLength(0...1))) }

    private var local: [ScannedProduct] {
        dataStore.profile.customFoods.filter {
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }.map { $0.toScannedProduct() }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the correct food. Your current \(gramsText) g portion stays the same; nutrition is replaced.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.xs, bottom: 0, trailing: Spacing.xs))
                }
                if !local.isEmpty { Section("Your foods") { rows(local) } }
                if loading {
                    statusRow { ProgressView("Searching foods…") }
                }
                if let errorText {
                    statusRow {
                        VStack(spacing: Spacing.sm) {
                            Text(errorText)
                                .multilineTextAlignment(.center)
                            Button("Retry search") { retry += 1 }
                                .fontWeight(.semibold)
                        }
                    }
                }
                if !results.isEmpty { Section("Food database") { rows(results) } }
                if !loading && errorText == nil && results.isEmpty && local.isEmpty {
                    statusRow {
                        Text(query.count < 2 ? "Type at least two characters to search." : "No matches. Try another food name.")
                    }
                }
            }
            .glassFormStyle()
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, prompt: "Find the correct food")
            .navigationTitle("Replace food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .pinnedFooter { footer }
            .task(id: "\(query)|\(retry)") { await search() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let selected, selected.hasNutrition, let meal = selected.loggable(for: .grams(grams)) {
            VStack(spacing: Spacing.sm) {
                Text("\(selected.name) · \(meal.calories) kcal for \(gramsText) g")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                GlassButton(title: "Replace food", isFullWidth: true) {
                    onReplace(selected)
                    dismiss()
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.sm)
        }
    }

    /// Loading, error and empty copy, centred in the list instead of
    /// sitting in a lone grey row.
    private func statusRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .listRowBackground(Color.clear)
    }

    /// Picture, name and brand on the left; energy on the right, so every
    /// row reads the same way and the numbers line up in one column.
    private func rows(_ products: [ScannedProduct]) -> some View {
        ForEach(products, id: \.barcode) { product in
            let isSelected = selected?.barcode == product.barcode
            Button { selected = product } label: {
                HStack(spacing: Spacing.md) {
                    FoodThumbnail(name: product.name, imageURL: product.imageURL, size: 44)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(product.name)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(2)
                        if let brand = product.brand, !brand.isEmpty {
                            Text(brand)
                                .font(AppFont.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text("\(product.per100g.calories.formatted(.number.precision(.fractionLength(0)))) kcal")
                            .font(AppFont.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                        Text("per 100 g")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Spacing.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            try await Task.sleep(for: AppAnimation.searchDebounceDelay)
            let found = try await OpenFoodFactsService.shared.search(query: value)
            try Task.checkCancellation()
            // A crowd record with no energy or macros would replace the
            // item with a silent 0 kcal, as the barcode review refuses to.
            var seen = Set<String>()
            results = found.filter { $0.hasNutrition && seen.insert($0.barcode).inserted }
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            loading = false
            // The local throttle and rate limits carry their own "try
            // again in Ns" copy; an immediate Retry would just fail again.
            errorText = (error as? OpenFoodFactsService.LookupError)?.errorDescription
                ?? String(localized: "Couldn't search the food database. Retry, or choose one of your saved foods.")
        }
    }
}
