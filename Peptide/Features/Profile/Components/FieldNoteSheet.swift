import SwiftUI

/// The shake-to-note sheet: what you were looking at, a text field, and
/// the notes saved so far with one button to share them all.
struct FieldNoteSheet: View {
    let screen: String
    let screenshot: UIImage
    let onDone: () -> Void

    @State private var text = ""
    @State private var notes = FieldNoteStore.shared.notes
    @State private var exportFiles: [URL] = []
    @State private var confirmingDelete = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(verbatim: screen)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            Text("A screenshot is saved with the note.")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    TextField("What felt off, or what's missing?", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .font(AppFont.body)
                        .focused($isFocused)
                        .padding(Spacing.md)
                        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
                    if !notes.isEmpty {
                        savedNotes
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { exportFiles = FieldNoteStore.shared.exportFiles() }
            // `.task` rather than `.onAppear`: focus set while the UIKit
            // presentation is still animating is often dropped.
            .task { isFocused = true }
            // A swipe must not throw away a half-written note.
            .interactiveDismissDisabled(!text.isEmpty)
            .confirmationDialog("Delete all notes?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    FieldNoteStore.shared.deleteAll()
                    notes = []
                    exportFiles = []
                }
            }
        }
    }

    private var savedNotes: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Saved notes: \(notes.count)")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            HStack(spacing: Spacing.md) {
                ShareLink(items: exportFiles) {
                    Label("Share all", systemImage: "square.and.arrow.up")
                }
                Spacer(minLength: 0)
                Button("Delete all", role: .destructive) { confirmingDelete = true }
            }
            .font(AppFont.subheadline.weight(.semibold))
            .frame(minHeight: Spacing.minimumHitTarget)
        }
    }

    private func save() {
        FieldNoteStore.shared.add(text: text, screen: screen, screenshot: screenshot)
        Haptics.notify(.success)
        onDone()
    }
}
