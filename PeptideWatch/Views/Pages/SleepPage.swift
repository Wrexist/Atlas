import SwiftUI

/// Third page, in the shape of the system Sleep app's score: last night
/// as a ring of stage arcs that blooms open on arrival, the score rolling
/// up inside it, the band ("High") and a stage legend below.
struct SleepPage: View {
    let sleep: WatchSleepSnapshot
    @State private var showsDetail = false
    @State private var reveal = 0.0

    @Environment(\.watchPageIsActive) private var isActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 34

    private var nightDates: String {
        (sleep.start..<max(sleep.end, sleep.start))
            .formatted(.interval.month(.abbreviated).day())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ring
                HStack(alignment: .firstTextBaseline) {
                    Text(sleep.band.label)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer(minLength: 4)
                    Text(WatchFormat.duration(minutes: sleep.asleepMinutes))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .entrance(0)
                legend
                    .entrance(1)
                Text(nightDates)
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.sleepAccent)
                    .entrance(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Sleep Score")
        .pageBackground(WatchPalette.stageCore)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsDetail = true
                } label: {
                    Image(systemName: "bed.double.fill")
                }
                .accessibilityLabel("Sleep stages")
            }
        }
        .sheet(isPresented: $showsDetail) {
            SleepDetailView(sleep: sleep)
        }
        .onAppear(perform: animateReveal)
        .onChange(of: isActive) { animateReveal() }
    }

    private var ring: some View {
        ZStack {
            SleepStageRing(slices: sleep.slices, lineWidth: 12, reveal: reveal)
            VStack(spacing: -2) {
                Image(systemName: "moon.stars.fill")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.sleepAccent)
                    .symbolEffect(.pulse, options: .repeating.speed(0.3), isActive: isActive && !reduceMotion)
                RollingNumber(value: sleep.score)
                    .font(.system(size: scoreSize, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: 104, height: 104)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep score \(sleep.score), \(sleep.band.label)")
    }

    /// Two columns of stage dots and durations, the ring's key.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], alignment: .leading, spacing: 2) {
            ForEach(sleep.slices) { slice in
                HStack(spacing: 4) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 6, height: 6)
                    Text(slice.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(WatchFormat.duration(minutes: slice.minutes))
                        .monospacedDigit()
                }
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func animateReveal() {
        guard !reduceMotion else {
            reveal = 1
            return
        }
        withAnimation(isActive ? WatchMotion.entrance : nil) {
            reveal = isActive ? 1 : 0
        }
    }
}

private struct SleepDetailView: View {
    let sleep: WatchSleepSnapshot

    var body: some View {
        List {
            ForEach(sleep.slices) { slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 8, height: 8)
                    Text(slice.label)
                    Spacer()
                    Text(WatchFormat.duration(minutes: slice.minutes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                Text("Bedtime")
                Spacer()
                Text(sleep.start, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack {
                Text("Woke")
                Spacer()
                Text(sleep.end, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Text(sleep.hasStages
                 ? LocalizedStringKey("Your score weighs time asleep against an 8-hour target, how much of it was deep and REM, and how little you woke.")
                 : LocalizedStringKey("Your score weighs time asleep against an 8-hour target and how little you woke. Wear Apple Watch to bed to add sleep stages."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Last Night")
    }
}
