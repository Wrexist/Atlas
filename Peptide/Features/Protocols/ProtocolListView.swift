import SwiftUI

struct ProtocolListView: View {
    @State private var viewModel = ProtocolViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        if !viewModel.activeProtocols.isEmpty {
                            ProtocolSection(title: "Active", protocols: viewModel.activeProtocols)
                        }

                        if !viewModel.pausedProtocols.isEmpty {
                            ProtocolSection(title: "Paused", protocols: viewModel.pausedProtocols)
                        }

                        if !viewModel.completedProtocols.isEmpty {
                            ProtocolSection(title: "Completed", protocols: viewModel.completedProtocols)
                        }
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.bottom, 100)
                }
                .background(AppColor.background)

                // Floating add button
                GlassIconButton(icon: "plus", size: 56, tinted: true) {
                    viewModel.showingBuilder = true
                }
                .appShadow(AppShadow.accentGlow)
                .padding(Spacing.xxl)
            }
            .navigationTitle("Protocols")
            .navigationDestination(for: PeptideProtocol.self) { protocol_ in
                ProtocolDetailView(protocol_: protocol_)
            }
            .glassSheet(isPresented: $viewModel.showingBuilder) {
                ProtocolBuilderView()
            }
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
    ProtocolListView()
        .preferredColorScheme(.dark)
}
