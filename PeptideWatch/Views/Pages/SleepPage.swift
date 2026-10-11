import SwiftUI

/// Third page, in the shape of the system Sleep app's score: last night
/// as a ring of stage arcs on deep blue, the score inside it, the band
/// ("High") and the night's dates below.
struct SleepPage: View {
    let sleep: WatchSleepSnapshot
    @State private var showsDetail = false

    private var nightDates: String {
        (sleep.start..<max(sleep.end, sleep.start))
            .formatted(.interval.month(.abbreviated).day())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ZStack {
                    SleepStageRing(slices: sleep.slices, lineWidth: 11)
                    Text("\(sleep.score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 92, height: 92)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep score \(sleep.score), \(sleep.band.label)")

                Text(sleep.band.label)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .accessibilityHidden(true)
                Text("\(WatchFormat.duration(minutes: sleep.asleepMinutes)) asleep")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                Text(nightDates)
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.sleepAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Sleep Score")
        .containerBackground(WatchPalette.sleepPage.gradient, for: .tabView)
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
