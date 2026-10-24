import SwiftUI
import UIKit

/// The scanned pages behind a lab value, so the user can check a
/// transcribed number against the report it came from. Pages are read
/// off the main actor; a device that never had the scan says so.
struct LabReportViewer: View {
    let reportID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var pages: [UIImage]?

    var body: some View {
        NavigationStack {
            Group {
                if let pages, pages.isEmpty {
                    ContentUnavailableView(
                        "Report not on this device",
                        systemImage: "doc.questionmark",
                        description: Text("Scanned reports stay on the device that scanned them.")
                    )
                } else if let pages {
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                            ForEach(pages.indices, id: \.self) { index in
                                Image(uiImage: pages[index])
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
                                    .accessibilityLabel(Text("Page \(index + 1) of \(pages.count)"))
                            }
                        }
                        .padding(Spacing.screenPadding)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.background)
            .navigationTitle("Original report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { pages = await Self.load(reportID) }
    }

    private static func load(_ reportID: UUID) async -> [UIImage] {
        let urls = LabReportStorage.pageURLs(for: reportID)
        return await Task.detached(priority: .userInitiated) {
            urls.compactMap { UIImage(contentsOfFile: $0.path) }
        }.value
    }
}
