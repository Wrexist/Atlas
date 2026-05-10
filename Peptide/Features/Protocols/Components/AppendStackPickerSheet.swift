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
        .liquidGlassPresentation(detents: [.medium, .large])
    }

    private func row(for proto: PeptideProtocol) -> some View {
        let isSelected = proto.id == selectedId
        return Button {
            onPick(proto.id)
        } label: {
            GlassCard(tinted: isSelected) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: proto.status.iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(statusColor(proto.status))
                        .frame(width: 28, height: 28)
                        .background {
                            Circle().fill(statusColor(proto.status).opacity(0.15))
                        }

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

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColor.accentLight)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }

    private func statusColor(_ status: ProtocolStatus) -> Color {
        switch status {
        case .active: AppColor.accentPrimary
        case .paused: AppColor.warning
        case .completed: AppColor.textSecondary
        }
    }

    private func subtitle(for proto: PeptideProtocol) -> String {
        let abbreviations = proto.peptides.prefix(3).map(\.abbreviation).joined(separator: " · ")
        let extras = proto.peptides.count > 3 ? " +\(proto.peptides.count - 3)" : ""
        let body = abbreviations.isEmpty ? "Empty stack" : abbreviations + extras
        return "\(body) — \(proto.schedule.summary)"
    }
}
