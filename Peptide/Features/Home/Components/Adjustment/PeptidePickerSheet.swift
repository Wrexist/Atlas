import SwiftUI

struct PeptidePickerSheet: View {
    @Binding var selectedPeptides: Set<UUID>
    let allPeptides: [Peptide]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PeptideSelector(selectedPeptides: $selectedPeptides, allPeptides: allPeptides)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.vertical, Spacing.md)
            }
            .background(AppColor.background)
            .navigationTitle("Choose Peptides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}
