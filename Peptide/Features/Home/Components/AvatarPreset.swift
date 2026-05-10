import SwiftUI
import UIKit

/// Built-in symbol-on-gradient avatars users can pick when they don't want to
/// upload a photo. We render the chosen preset to JPEG with the same pipeline
/// as a real photo so the rest of the app (WelcomeHeader, ProfileHeader, etc.)
/// can stay agnostic — it always reads `profile.avatarImageData`.
struct AvatarPreset: Identifiable, Hashable {
    let id: String
    let symbol: String
    let gradient: [Color]

    static let all: [AvatarPreset] = [
        AvatarPreset(
            id: "spark",
            symbol: "sparkles",
            gradient: [Color(hex: 0x6BAF7E), Color(hex: 0x3A6247)]
        ),
        AvatarPreset(
            id: "wave",
            symbol: "wave.3.right",
            gradient: [Color(hex: 0x60A5E8), Color(hex: 0x2563A0)]
        ),
        AvatarPreset(
            id: "atom",
            symbol: "atom",
            gradient: [Color(hex: 0xA78BFA), Color(hex: 0x6D44C7)]
        ),
        AvatarPreset(
            id: "flame",
            symbol: "flame.fill",
            gradient: [Color(hex: 0xF2A062), Color(hex: 0xB85C28)]
        ),
        AvatarPreset(
            id: "leaf",
            symbol: "leaf.fill",
            gradient: [Color(hex: 0x2DD4BF), Color(hex: 0x0E8C7C)]
        ),
        AvatarPreset(
            id: "bolt",
            symbol: "bolt.heart.fill",
            gradient: [Color(hex: 0xFB7FA9), Color(hex: 0xC04372)]
        ),
        AvatarPreset(
            id: "moon",
            symbol: "moon.stars.fill",
            gradient: [Color(hex: 0x4A4F8C), Color(hex: 0x1E2347)]
        ),
        AvatarPreset(
            id: "dumbbell",
            symbol: "dumbbell.fill",
            gradient: [Color(hex: 0x9CA3AF), Color(hex: 0x4B5563)]
        ),
    ]

    /// Renders the preset to a square JPEG matching the customization sheet's
    /// 1024px / 0.82-quality avatar pipeline. Performed on the calling thread
    /// — callers should hop off the main thread for big batches.
    func renderJPEGData(side: CGFloat = 1024, quality: CGFloat = 0.82) -> Data? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            // Diagonal gradient — top-leading light → bottom-trailing dark.
            let cgColors = gradient.map { UIColor($0).cgColor } as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let cgGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: cgColors,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    cgGradient,
                    start: .zero,
                    end: CGPoint(x: side, y: side),
                    options: []
                )
            }

            // Centered SF Symbol, ~40% of the canvas, white with a subtle
            // shadow so it reads on any gradient.
            let symbolSize = side * 0.4
            let config = UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
            if let symbolImage = UIImage(systemName: symbol)?
                .applyingSymbolConfiguration(config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let drawSize = symbolImage.size
                let origin = CGPoint(
                    x: rect.midX - drawSize.width / 2,
                    y: rect.midY - drawSize.height / 2
                )
                symbolImage.draw(at: origin)
            }
            _ = rect
        }
        return image.jpegData(compressionQuality: quality)
    }
}
