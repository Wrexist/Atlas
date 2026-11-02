import SwiftUI

/// Drag-to-reorder + show/hide editor for Today's sections — the
/// `EditBiomarkersSheet` pattern applied to the Today scroll. One list
/// holds every section so a hidden one keeps its place and comes back
/// where it was.
///
/// Writes through the binding the host wires to
/// `dataStore.profile.todayLayout`; the host persists from the sheet's
/// `onDismiss` so a session of edits lands as one save.
struct EditTodaySheet: View {
    @Binding var layout: TodayLayout

    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.sections) { section in
                        row(section)
                    }
                    .onMove { source, destination in
                        layout.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Sections")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(AppColor.textSecondary)
                } footer: {
                    Text("Drag to reorder. Switch a section off to hide it from Today.")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                }

                Section {
                    Button("Reset to default", role: .destructive, action: reset)
                        .disabled(layout == .default)
                }
            }
            .listStyle(.insetGrouped)
            .glassFormStyle()
            .environment(\.editMode, $editMode)
            .navigationTitle("Edit Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func row(_ section: TodaySection) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.surfaceElevated)
                Image(systemName: section.systemImage)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
            .frame(width: 32, height: 32)

            Text(section.displayName)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)

            Spacer(minLength: 0)

            Toggle(section.displayName, isOn: visibilityBinding(for: section))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppColor.accentPrimary)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func visibilityBinding(for section: TodaySection) -> Binding<Bool> {
        Binding(
            get: { !layout.isHidden(section) },
            set: { isShown in
                Haptics.selection()
                AppAnimation.with(AppAnimation.springSnappy) {
                    layout.setHidden(section, !isShown)
                }
            }
        )
    }

    private func reset() {
        Haptics.selection()
        AppAnimation.with(AppAnimation.springSnappy) { layout = .default }
    }
}

#Preview {
    struct PreviewHost: View {
        @State var layout = TodayLayout(order: [], hidden: ["weeklyRecap"])
        var body: some View {
            EditTodaySheet(layout: $layout)
        }
    }
    return PreviewHost()
}
