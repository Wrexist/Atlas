import SwiftUI

/// One stage's share of the night, in display order.
struct SleepSlice: Identifiable {
    let label: String
    let minutes: Int
    let color: Color
    var id: String { label }
}

extension WatchSleepSnapshot {
    /// Awake → REM → Core → Deep, the order Apple's Sleep app stacks
    /// them. A source without stages shows one "Asleep" slice instead of
    /// three empty ones; on a staged night, time a source recorded without
    /// a stage gets its own "Asleep" slice rather than counting as Core.
    var slices: [SleepSlice] {
        let asleep: [SleepSlice] = hasStages
            ? [
                SleepSlice(label: String(localized: "REM"), minutes: remMinutes, color: WatchPalette.stageREM),
                SleepSlice(label: String(localized: "Core"), minutes: coreMinutes, color: WatchPalette.stageCore),
                SleepSlice(label: String(localized: "Deep"), minutes: deepMinutes, color: WatchPalette.stageDeep),
                SleepSlice(label: String(localized: "Asleep"), minutes: unspecifiedMinutes, color: WatchPalette.sleepAccent),
            ]
            : [SleepSlice(label: String(localized: "Asleep"), minutes: asleepMinutes, color: WatchPalette.stageCore)]
        let awake = SleepSlice(label: String(localized: "Awake"), minutes: awakeMinutes, color: WatchPalette.stageAwake)
        return ([awake] + asleep).filter { $0.minutes > 0 }
    }
}

/// The Sleep page's hero: the night as a ring split into stage arcs,
/// each arc as long as the time spent in that stage, with a clear gap
/// between arcs so short stages still read as their own segment.
///
/// `reveal` (0…1) grows every arc out from its start while the ring turns
/// into place, so the page can bloom the night open. Complications leave
/// it at 1.
struct SleepStageRing: View, Animatable {
    let slices: [SleepSlice]
    var lineWidth: CGFloat = 10
    var reveal: Double = 1

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().stroke(WatchPalette.track, lineWidth: lineWidth)
                ForEach(arcs(diameter: diameter)) { arc in
                    Circle()
                        .trim(from: arc.from, to: arc.from + (arc.to - arc.from) * reveal)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90 - 70 * (1 - reveal)))
                        .opacity(min(1, reveal * 3))
                }
            }
            .padding(lineWidth / 2)
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct Arc: Identifiable {
        let id: String
        let from: Double
        let to: Double
        let color: Color
    }

    /// Round caps overhang each arc end by half the line width, so the
    /// gap has to cover that overhang before any space shows. A stage
    /// shorter than the gap shrinks its own gap rather than disappearing,
    /// so a few minutes awake still shows as a dot.
    private func arcs(diameter: CGFloat) -> [Arc] {
        let total = Double(slices.reduce(0) { $0 + $1.minutes })
        guard total > 0 else { return [] }
        let circumference = Double.pi * Double(max(1, diameter - lineWidth))
        let gap = slices.count > 1 ? (Double(lineWidth) + 3) / circumference : 0

        var cursor = 0.0
        var result: [Arc] = []
        for slice in slices {
            let share = Double(slice.minutes) / total
            let sliceGap = min(gap, share / 2)
            result.append(Arc(id: slice.id, from: cursor + sliceGap / 2,
                              to: cursor + share - sliceGap / 2, color: slice.color))
            cursor += share
        }
        return result
    }
}
