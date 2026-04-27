import SwiftUI

struct ProtocolListRootView: View {
    var body: some View {
        NavigationStack {
            ProtocolListView()
        }
    }
}

struct ProtocolListView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showingBuilder = false
    @State private var showingPaywall = false
    @State private var preselectedPeptide: Peptide?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
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
                                ProtocolSection(title: "Active", protocols: dataStore.activeProtocols)
                            }

                            if !dataStore.pausedProtocols.isEmpty {
                                ProtocolSection(title: "Paused", protocols: dataStore.pausedProtocols)
                            }

                            if !dataStore.completedProtocols.isEmpty {
                                ProtocolSection(title: "Completed", protocols: dataStore.completedProtocols)
                            }
                        }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, 100)
            }
            .background(AppColor.background)

            // Floating add button
            GlassIconButton(icon: "plus", size: 56, tinted: true) {
                preselectedPeptide = nil
                if StoreService.shared.requiresPro(activeProtocolCount: dataStore.activeProtocols.count) {
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
        .glassSheet(isPresented: $showingBuilder) {
            ProtocolBuilderView(preselectedPeptide: preselectedPeptide)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
}

private struct ProtocolSection: View {
    let title: String
    let protocols: [PeptideProtocol]

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
                .staggeredAppear(index: index)
            }
        }
    }
}

#Preview {
    ProtocolListRootView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
