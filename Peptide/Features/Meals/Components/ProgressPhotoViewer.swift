import SwiftUI

/// Full-screen carousel of every progress photo. Swipe horizontally
/// between photos; each one fills the viewport with a date overlay
/// on the bottom. "Compare" button in the toolbar drops the user
/// into the compare-picker → side-by-side mode.
///
/// Privacy posture matches `ProgressPhotosCard`: photos start
/// revealed in this view (the user explicitly tapped to open it),
/// but a "Hide" toggle in the toolbar blurs every photo back so a
/// glance over the shoulder can't catch the user off guard.
struct ProgressPhotoViewer: View {
    let filenames: [String]                // chronological, oldest-first
    let initialFilename: String?
    let onCompare: (String) -> Void        // user picked a photo + tapped compare
    let onDelete: (String) -> Void
    let onClose: () -> Void

    @State private var selected: String?
    @State private var blurEnabled: Bool = false
    @State private var compareMode: Bool = false
    @State private var compareTarget: String?

    init(
        filenames: [String],
        initialFilename: String? = nil,
        onCompare: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.filenames = filenames
        self.initialFilename = initialFilename
        self.onCompare = onCompare
        self.onDelete = onDelete
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $selected) {
                    ForEach(filenames, id: \.self) { filename in
                        photoPage(filename: filename)
                            .tag(Optional(filename))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onAppear {
                    selected = initialFilename ?? filenames.last
                }

                VStack {
                    Spacer()
                    if let selected {
                        dateChip(filename: selected)
                            .padding(.bottom, Spacing.xl)
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.18), value: selected)
                    }
                }
            }
            .navigationTitle("Progress photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .foregroundStyle(AppColor.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if filenames.count >= 2, let selected {
                            Button {
                                onCompare(selected)
                            } label: {
                                Label("Compare with…", systemImage: "rectangle.split.2x1")
                            }
                        }
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                blurEnabled.toggle()
                            }
                        } label: {
                            Label(
                                blurEnabled ? "Unblur" : "Blur photo",
                                systemImage: blurEnabled ? "eye" : "eye.slash"
                            )
                        }
                        if let selected {
                            Button(role: .destructive) {
                                onDelete(selected)
                            } label: {
                                Label("Delete photo", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundStyle(AppColor.accentLight)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func photoPage(filename: String) -> some View {
        if let image = ProgressPhotoStorage.loadImage(for: filename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .blur(radius: blurEnabled ? 22 : 0)
                .animation(.easeOut(duration: 0.18), value: blurEnabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(AppColor.warning)
                Text("Couldn't load this photo.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dateChip(filename: String) -> some View {
        Text(ProgressPhotoMetadata.displayDate(forFilename: filename))
            .font(AppFont.scaled(14, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(Color.black.opacity(0.55))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
            }
    }
}
