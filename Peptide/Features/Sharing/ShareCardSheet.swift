import SwiftUI
import UIKit

/// Hosts a scaled-down preview of the rendered cycle card and lets the user
/// push it through the iOS share sheet. Reuses the `ShareSheet` representable
/// already defined in `Peptide/Features/Profile/Components/ExportSection.swift`.
struct ShareCardSheet: View {
    let proto: PeptideProtocol
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @State private var renderedURL: URL?
    @State private var showShareSheet = false
    @State private var isRendering = false
    @State private var errorMessage: String?

    private static let previewScale: CGFloat = 0.34
    private var previewWidth: CGFloat { ShareCardRenderer.canvasSize.width * Self.previewScale }
    private var previewHeight: CGFloat { ShareCardRenderer.canvasSize.height * Self.previewScale }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    preview
                    pitch
                    GlassButton(
                        title: isRendering ? "Preparing…" : "Share Cycle Card",
                        icon: "square.and.arrow.up",
                        style: .primary,
                        isFullWidth: true
                    ) {
                        renderAndShare()
                    }
                    .disabled(isRendering)
                    .padding(.horizontal, Spacing.screenPadding)
                }
                .padding(.vertical, Spacing.xl)
            }
            .background(AppColor.background)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let renderedURL {
                    ShareSheet(urls: [renderedURL])
                }
            }
            .alert("Couldn't share", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var preview: some View {
        CycleCardView(proto: proto)
            .frame(
                width: ShareCardRenderer.canvasSize.width,
                height: ShareCardRenderer.canvasSize.height
            )
            .scaleEffect(Self.previewScale, anchor: .topLeading)
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: AppColor.accentGlow, radius: 24, x: 0, y: 12)
    }

    private var pitch: some View {
        VStack(spacing: Spacing.xs) {
            Text("1080 × 1350 · ready for Stories")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Text("Brand watermark is baked into the image.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    private func renderAndShare() {
        guard !isRendering else { return }
        isRendering = true
        // Render on the next runloop tick so the spinner state actually flushes
        // before the (synchronous) ImageRenderer pass kicks in.
        Task { @MainActor in
            await Task.yield()
            defer { isRendering = false }
            do {
                let url = try ShareCardRenderer.renderPNG(for: proto)
                renderedURL = url
                if dataStore.profile.hapticFeedbackEnabled {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                showShareSheet = true
            } catch {
                if dataStore.profile.hapticFeedbackEnabled {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
