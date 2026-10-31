import SwiftUI

/// 30-second daily wellness check-in. Five 1-5 sliders (energy /
/// sleep / recovery / mood / focus) plus an optional note. Designed
/// to be a one-screen, one-thumb interaction — the whole sheet
/// fits on an iPhone 13 without scrolling so users actually fill
/// it in instead of bouncing.
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
    @Namespace private var pillNamespace

    private var currentValues: [String] {
        [energy, sleepQuality, recovery, mood, focus].map(String.init) + [note]
    }

    private var hasChanges: Bool { didHydrate && currentValues != openedValues }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    sliderCard(for: .energy,       value: $energy)
                    sliderCard(for: .sleepQuality, value: $sleepQuality)
                    sliderCard(for: .recovery,    value: $recovery)
                    sliderCard(for: .mood,        value: $mood)
                    sliderCard(for: .focus,       value: $focus)
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
            Text("Where are you on a scale of 1 to 5?")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Takes 30 seconds. Builds the correlation data that lets Atlas show you what's actually working.")
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

    private func sliderCard(for dimension: OutcomeDimension, value: Binding<Int>) -> some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(dimension.tint.opacity(0.20))
                            .frame(width: 32, height: 32)
                        Image(systemName: dimension.icon)
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(dimension.tint)
                    }
                    Text(dimension.displayName)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(value.wrappedValue)")
                        .font(AppFont.scaled(20, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(dimension.tint)
                        .contentTransition(.numericText())
                }
                fivePointPicker(value: value, tint: dimension.tint, dimension: dimension)
            }
        }
    }

    /// Custom 1-5 segmented picker. Five tappable pills give a
    /// faster, more accessible interaction than a continuous slider
    /// for a 5-point scale — VoiceOver users can hit a specific
    /// value directly instead of arrow-keying.
    private func fivePointPicker(
        value: Binding<Int>,
        tint: Color,
        dimension: OutcomeDimension
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            ForEach(1...5, id: \.self) { rating in
                pill(rating: rating, current: value.wrappedValue, tint: tint, dimension: dimension) {
                    if value.wrappedValue != rating {
                        Haptics.selection()
                        AppAnimation.with(AppAnimation.springSnappy) {
                            value.wrappedValue = rating
                        }
                    }
                }
                .accessibilityLabel("\(dimension.displayName) \(rating) of 5")
            }
        }
    }

    private func pill(
        rating: Int,
        current: Int,
        tint: Color,
        dimension: OutcomeDimension,
        action: @escaping () -> Void
    ) -> some View {
        let active = rating == current
        return Button(action: action) {
            Text("\(rating)")
                .font(AppFont.scaled(16, weight: active ? .heavy : .semibold))
                .monospacedDigit()
                .foregroundStyle(active ? AppColor.textPrimary : AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background {
                    // One selection fill per dimension that slides between
                    // ratings instead of jumping.
                    if active {
                        pillShape(fill: tint.opacity(0.22), border: tint.opacity(0.65))
                            .matchedGeometryEffect(id: dimension, in: pillNamespace)
                    }
                }
                .background {
                    pillShape(fill: AppColor.surfaceSecondary.opacity(0.5), border: AppColor.glassBorder)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private func pillShape(fill: Color, border: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
        return shape
            .fill(fill)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
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
