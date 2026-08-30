import SwiftUI

/// Compact labeled entry into the Protocols/Library surface, shown on
/// Today only while the user has zero protocols. With protocols the
/// dose section (and its Manage header button) owns this route; with
/// none, the differentiated feature would otherwise be reachable only
/// through Profile — invisible to exactly the users who haven't
/// discovered it. One quiet row, no tutorial, disappears the moment a
/// first protocol exists.
struct ProtocolsDiscoverRow: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.light)
            onTap()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "list.clipboard.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle().fill(AppColor.accentPrimary.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Protocols")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Track compounds, doses, and cycles — built for advanced routines.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Protocols. Track compounds, doses, and cycles.")
        .accessibilityHint("Opens the protocol library")
    }
}

#Preview {
    ProtocolsDiscoverRow(onTap: {})
        .padding()
        .background(AppColor.background)
        .preferredColorScheme(.dark)
}
