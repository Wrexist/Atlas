#if DEBUG
import SwiftUI

/// DEBUG-only alignment harness for the photoreal anatomy pack.
///
/// Cycles each muscle-head region highlighted so every mask can be
/// eyeballed against the base body (look for halos, gaps, or a muscle that
/// lights the wrong area), and surfaces any masks missing from the bundle.
/// Also doubles as a live preview of the vector fallback when no asset
/// pack is present. Never compiled into release. See
/// `docs/PHOTOREAL_ANATOMY_PLAN.md`.
///
/// Drop it behind any DEBUG entry point (e.g. a hidden Profile row) or use
/// the Xcode preview below.
struct AnatomyDebugView: View {
    @State private var index = 0
    @State private var auto = true
    @State private var intensity: Double = 1.0

    private let muscles = AnatomicalMuscle.allCases
    private let tick = Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()

    private var current: AnatomicalMuscle { muscles[index] }

    var body: some View {
        VStack(spacing: 16) {
            header

            MuscleMapView(highlights: [current: .intensity(intensity)])
                .frame(maxHeight: 460)
                .padding(.horizontal)

            controls
            coverage
            Spacer(minLength: 0)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onReceive(tick) { _ in
            guard auto else { return }
            index = (index + 1) % muscles.count
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("\(index + 1)/\(muscles.count)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(current.rawValue)
                .font(.title3.weight(.bold).monospaced())
                .foregroundStyle(.white)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                Button("‹ Prev") { auto = false; step(-1) }
                Toggle("Auto", isOn: $auto).fixedSize()
                Button("Next ›") { auto = false; step(1) }
            }
            .tint(.orange)

            HStack {
                Text("Intensity").font(.caption).foregroundStyle(.secondary)
                Slider(value: $intensity, in: 0...1)
                Text(String(format: "%.2f", intensity))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var coverage: some View {
        if AnatomyAssets.isAvailable {
            let missing = AnatomyAssets.missingMasks()
            Text(missing.isEmpty
                 ? "✓ Asset pack complete (\(muscles.count) masks)"
                 : "⚠︎ Missing masks: \(missing.map(\.rawValue).joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(missing.isEmpty ? .green : .red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        } else {
            Text("No asset pack bundled — showing vector fallback")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func step(_ delta: Int) {
        index = (index + delta + muscles.count) % muscles.count
    }
}

#Preview("Anatomy alignment harness") {
    AnatomyDebugView()
}
#endif
