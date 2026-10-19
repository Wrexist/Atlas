import SwiftUI

/// Picker shown from the protocol builder when the user wants to append the
/// peptides they're picking onto an existing protocol instead of creating a
/// new one. Mirrors the structure of `AddToStackSheet` (which is launched
/// from a peptide detail page) but tailored for the builder flow.
struct AppendStackPickerSheet: View {
    let protocols: [PeptideProtocol]
    let selectedId: UUID?
    let onPick: (UUID?) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    ForEach(protocols) { proto in
                        row(for: proto)
                    }

                    if let selectedId, protocols.contains(where: { $0.id == selectedId }) {
                        Button {
                            onPick(nil)
                        } label: {
                            Text("Don't append — create a new stack")
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, Spacing.md)
                        }
                        .buttonStyle(ScalePressStyle())
                        .padding(.top, Spacing.sm)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Pick a Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func row(for proto: PeptideProtocol) -> some View {
        let isSelected = proto.id == selectedId
        return Button {
            Haptics.selection()
            onPick(proto.id)
        } label: {
            GlassCard(tinted: isSelected) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: proto.status.iconName)
                        .font(AppFont.scaled(16))
                        .foregroundStyle(proto.status.color)
                        .frame(width: 28, height: 28)
                        .background {
                            Circle().fill(proto.status.color.opacity(0.15))
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(proto.name)
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)

                        Text(subtitle(for: proto))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .font(isSelected ? AppFont.scaled(16) : AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func subtitle(for proto: PeptideProtocol) -> String {
        let abbreviations = proto.peptides.prefix(3).map(\.abbreviation).joined(separator: " · ")
        let extras = proto.peptides.count > 3 ? " +\(proto.peptides.count - 3)" : ""
        let body = abbreviations.isEmpty ? "Empty stack" : abbreviations + extras
        return "\(body) — \(proto.schedule.summary)"
    }
}
