import SwiftUI

struct ProtocolListView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showingBuilder = false
    @State private var showingPaywall = false
    @State private var preselectedPeptide: Peptide?
    @State private var sharingProtocol: PeptideProtocol?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        CommunityStacksEntryCard()

                        if dataStore.protocols.isEmpty {
                            VStack(spacing: Spacing.lg) {
                                Image(systemName: "list.clipboard")
                                    .font(.system(size: 48))
                                    .foregroundStyle(AppColor.textTertiary)

                                Text("No Protocols Yet")
                                    .font(AppFont.title2)
                                    .foregroundStyle(AppColor.textSecondary)

                                Text("Create your first peptide protocol to start tracking your regimen.")
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(AppColor.textTertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, Spacing.xxxxl)
                            .sectionAppear(index: 0)
                        } else {
                            if !dataStore.activeProtocols.isEmpty {
                                ProtocolSection(
                                    title: "Active",
                                    protocols: dataStore.activeProtocols,
                                    onShare: { sharingProtocol = $0 }
                                )
                            }

                            if !dataStore.pausedProtocols.isEmpty {
                                ProtocolSection(
                                    title: "Paused",
                                    protocols: dataStore.pausedProtocols,
                                    onShare: { sharingProtocol = $0 }
                                )
                            }

                            if !dataStore.completedProtocols.isEmpty {
                                ProtocolSection(
                                    title: "Completed",
                                    protocols: dataStore.completedProtocols,
                                    onShare: { sharingProtocol = $0 }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, 100)
                }
                .background(AppColor.background)

                // Floating add button
                GlassIconButton(icon: "plus", accessibilityLabel: "New protocol", size: 56, tinted: true) {
                    preselectedPeptide = nil
                    let blocked = StoreService.shared.requiresPro(
                        activeProtocolCount: dataStore.activeProtocols.count
                    )
                    if dataStore.profile.hapticFeedbackEnabled {
                        if blocked {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        } else {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    if blocked {
                        showingPaywall = true
                    } else {
                        showingBuilder = true
                    }
                }
                .appShadow(AppShadow.accentGlow)
                .padding(Spacing.xxl)
            }
            .navigationTitle("Protocols")
            .navigationDestination(for: PeptideProtocol.self) { protocol_ in
                ProtocolDetailView(protocol_: protocol_)
            }
            .navigationDestination(for: CommunityStack.self) { stack in
                CommunityStackDetailView(stack: stack)
            }
            .navigationDestination(for: StackLibraryRoute.self) { _ in
                StackLibraryView()
            }
            .glassSheet(isPresented: $showingBuilder) {
                ProtocolBuilderView(preselectedPeptide: preselectedPeptide)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(item: $sharingProtocol) { proto in
                ShareCardSheet(proto: proto)
            }
        }
    }
}

/// Token-only routing value used by the entry card so SwiftUI's
/// `NavigationLink(value:)` resolves to `StackLibraryView`.
struct StackLibraryRoute: Hashable {}

private struct CommunityStacksEntryCard: View {
    var body: some View {
        NavigationLink(value: StackLibraryRoute()) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Browse community stacks")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Research-backed templates from peptide practitioners")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .fill(AppColor.glassTint)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse community stacks")
    }
}

private struct ProtocolSection: View {
    let title: String
    let protocols: [PeptideProtocol]
    let onShare: (PeptideProtocol) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title.uppercased())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .tracking(1.5)
                .padding(.leading, Spacing.xs)

            ForEach(Array(protocols.enumerated()), id: \.element.id) { index, protocol_ in
                NavigationLink(value: protocol_) {
                    ProtocolCard(protocol_: protocol_)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        onShare(protocol_)
                    } label: {
                        Label("Share Cycle Card", systemImage: "square.and.arrow.up")
                    }
                }
                .staggeredAppear(index: index)
            }
        }
    }
}

#Preview {
    ProtocolListView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
