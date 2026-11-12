import SwiftUI

/// 30-second daily wellness check-in. Five 1-5 ratings (energy /
/// sleep / recovery / mood / focus) plus an optional note, as one card
/// of rows: each row is a rising five-bar level you tap or drag across,
/// with the rating named in words. One screen, one thumb, no scrolling
/// on an iPhone 13, so people actually fill it in.
///
/// Pre-fills with the prior day's values when the user is filling
/// in fresh — the "stay still until you nudge it" pattern halves
/// the time-to-save vs. resetting to 3 every time. For an existing
/// check-in (the user tapped the card again to edit), pre-fills
/// with that day's stored values.
struct OutcomeCheckInSheet: View {
    let date: Date
    let initial: OutcomeEntry?
    let previousEntry: OutcomeEntry?
    let onSave: (OutcomeEntry) -> Void
    let onCancel: () -> Void

    @State private var energy: Int = 3
    @State private var sleepQuality: Int = 3
    @State private var recovery: Int = 3
    @State private var mood: Int = 3
    @State private var focus: Int = 3
    @State private var note: String = ""
    @State private var didHydrate: Bool = false
    /// The values the sheet opened with, so a stray swipe can't throw
    /// away five ratings and a typed note.
    @State private var openedValues: [String] = []

    private var currentValues: [String] {
        [energy, sleepQuality, recovery, mood, focus].map(String.init) + [note]
    }

    private var hasChanges: Bool { didHydrate && currentValues != openedValues }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    ratingsCard
                    noteCard
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle(initial == nil ? "How are you feeling?" : "Edit check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardChangesCancelButton(hasChanges: hasChanges, onCancel: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                }
            }
            .onAppear(perform: hydrate)
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerCopy)
                .font(AppFont.eyebrow)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.accentLight)
            Text("Tap or drag the bars. Takes 30 seconds, and shows Atlas what actually works for you.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerCopy: String {
        let dayLabel = OutcomeCheckInSheet.dayFormatter.string(from: date)
        return String(
            localized: "Daily check-in · \(dayLabel)",
            comment: "Header eyebrow on the outcome check-in sheet. Date is localised."
        )
    }

    private var ratingsCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(spacing: 0) {
                OutcomeLevelRow(dimension: .energy, value: $energy)
                Divider().overlay(AppColor.glassBorder)
                OutcomeLevelRow(dimension: .sleepQuality, value: $sleepQuality)
                Divider().overlay(AppColor.glassBorder)
                OutcomeLevelRow(dimension: .recovery, value: $recovery)
                Divider().overlay(AppColor.glassBorder)
                OutcomeLevelRow(dimension: .mood, value: $mood)
                Divider().overlay(AppColor.glassBorder)
                OutcomeLevelRow(dimension: .focus, value: $focus)
            }
        }
    }

    private var noteCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "text.bubble")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    Text("Note (optional)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                }
                TextField("Anything notable today?", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .foregroundStyle(AppColor.textPrimary)
                    .tint(AppColor.accentPrimary)
            }
        }
    }

    // MARK: - State plumbing

    private func hydrate() {
        guard !didHydrate else { return }
        didHydrate = true
        if let initial {
            energy = initial.energy
            sleepQuality = initial.sleepQuality
            recovery = initial.recovery
            mood = initial.mood
            focus = initial.focus
            note = initial.note ?? ""
        } else if let previousEntry {
            // "Yesterday's values" pre-fill cuts the median time-to-
            // save in half — most users' day-to-day deltas are small.
            energy = previousEntry.energy
            sleepQuality = previousEntry.sleepQuality
            recovery = previousEntry.recovery
            mood = previousEntry.mood
            focus = previousEntry.focus
            // Don't carry over the note — a stale note from yesterday
            // is worse than no note today.
        }
        openedValues = currentValues
    }

    private func commit() {
        Haptics.success()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = OutcomeEntry(
            id: initial?.id ?? UUID(),
            date: date,
            energy: energy,
            sleepQuality: sleepQuality,
            recovery: recovery,
            mood: mood,
            focus: focus,
            note: trimmed.isEmpty ? nil : trimmed,
            updatedAt: Date()
        )
        onSave(entry)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

/// One rating: the dimension, its rating in words, and five bars rising
/// left to right, filled up to the rating. Tap a bar or drag across them;
/// VoiceOver swipes up and down.
private struct OutcomeLevelRow: View {
    let dimension: OutcomeDimension
    @Binding var value: Int

    @ScaledMetric(relativeTo: .body) private var barWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var barStep: CGFloat = 5
    private static let barGap: CGFloat = 6
    private static let range = 1...5

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                label
                Spacer(minLength: Spacing.sm)
                bars
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                label
                bars
            }
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(dimension.displayName))
        .accessibilityValue(Text("\(Self.word(for: value)), \(value) of 5"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + 1)
            case .decrement: set(value - 1)
            @unknown default: break
            }
        }
    }

    private var label: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: dimension.icon)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(dimension.tint)
                .frame(width: AppFont.scaledValue(34), height: AppFont.scaledValue(34))
                .background(dimension.tint.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(dimension.displayName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(Self.word(for: value))
                    .font(AppFont.footnote)
                    .foregroundStyle(dimension.tint)
                    .contentTransition(.numericText())
            }
        }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: Self.barGap) {
            ForEach(Self.range, id: \.self) { rating in
                RoundedRectangle(cornerRadius: Spacing.iconCornerRadius, style: .continuous)
                    .fill(rating <= value ? dimension.tint : AppColor.track)
                    .frame(width: barWidth, height: barWidth * 0.5 + barStep * CGFloat(rating))
            }
        }
        .frame(minHeight: Spacing.minimumHitTarget, alignment: .bottom)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let slot = Int(drag.location.x / (barWidth + Self.barGap))
                    set(slot + 1)
                }
        )
        .appAnimation(AppAnimation.springSnappy, value: value)
    }

    private func set(_ rating: Int) {
        let clamped = min(Self.range.upperBound, max(Self.range.lowerBound, rating))
        guard clamped != value else { return }
        value = clamped
        Haptics.selection()
    }

    static func word(for rating: Int) -> String {
        switch rating {
        case 1: String(localized: "Very low", comment: "Daily check-in rating 1 of 5")
        case 2: String(localized: "Low", comment: "Daily check-in rating 2 of 5")
        case 3: String(localized: "Okay", comment: "Daily check-in rating 3 of 5")
        case 4: String(localized: "Good", comment: "Daily check-in rating 4 of 5")
        default: String(localized: "Great", comment: "Daily check-in rating 5 of 5")
        }
    }
}
