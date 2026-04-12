import SwiftUI

struct PeptideSelector: View {
    @Binding var selectedPeptides: Set<UUID>
    @State private var searchText = ""

    private var peptides: [Peptide] {
        let all = MockPeptides.all
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter {
            $0.name.lowercased().contains(query) ||
            $0.abbreviation.lowercased().contains(query) ||
            $0.category.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.textTertiary)

                TextField("Search peptides...", text: $searchText)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                    .tint(AppColor.accentPrimary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
            }
            .padding(Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }

            if !selectedPeptides.isEmpty {
                HStack {
                    Text("\(selectedPeptides.count) selected")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentPrimary)
                    Spacer()
                }
            }

            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(peptides) { peptide in
                        Button {
                            withAnimation(AppAnimation.springSnappy) {
                                if selectedPeptides.contains(peptide.id) {
                                    selectedPeptides.remove(peptide.id)
                                } else {
                                    selectedPeptides.insert(peptide.id)
                                }
                            }
                        } label: {
                            let isSelected = selectedPeptides.contains(peptide.id)

                            HStack(spacing: Spacing.md) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isSelected ? AppColor.accentPrimary : AppColor.textTertiary)
                                    .contentTransition(.symbolEffect(.replace))

                                Image(systemName: peptide.imageSystemName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(peptide.category.color)
                                    .frame(width: 28, height: 28)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(peptide.category.color.opacity(0.15))
                                    }

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(peptide.abbreviation)
                                        .font(AppFont.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(AppColor.textPrimary)

                                    Text(peptide.category.displayName)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textTertiary)
                                }

                                Spacer()

                                Text(peptide.dosageRange)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, Spacing.xs)
                            .padding(.horizontal, Spacing.sm)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                        .fill(AppColor.accentPrimary.opacity(0.08))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                                .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                                        }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        PeptideSelector(selectedPeptides: .constant([MockPeptides.bpc157.id]))
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
