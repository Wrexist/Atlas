import SwiftUI

/// The user's daily supplements: each with its last seven days and its
/// run of days in a row, plus one-tap presets to add more. Setting one up
/// is a single tap on a preset; time of day and a reminder are a tap on
/// the card away, never required.
struct SupplementsSheet: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let supplement: Supplement
        let isNew: Bool
        var id: UUID { supplement.id }
    }

    private var supplements: [Supplement] {
        SupplementEngine.ordered(dataStore.profile.supplements)
    }

    /// Presets not already on the list, matched by name so a renamed
    /// preset frees its chip again.
    private var availablePresets: [SupplementPreset] {
        let names = Set(supplements.map { $0.name.lowercased() })
        return SupplementPreset.allCases.filter { !names.contains($0.name.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("One check a day on Today. No cycles, no protocol.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)

                    if !supplements.isEmpty {
                        VStack(spacing: Spacing.md) {
                            ForEach(supplements) { supplement in
                                card(supplement)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                    }

                    addSection
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxl)
                .readableContentWidth()
                .appAnimation(AppAnimation.springSnappy, value: supplements)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { target in
                SupplementEditSheet(
                    supplement: target.supplement,
                    isNew: target.isNew,
                    onSave: { dataStore.saveSupplement($0) },
                    onDelete: { id in
                        AppAnimation.with(AppAnimation.springSnappy) { dataStore.deleteSupplement(id: id) }
                    }
                )
                .environment(dataStore)
            }
        }
    }

    // MARK: - Cards

    private func card(_ supplement: Supplement) -> some View {
        let now = Date()
        let streak = SupplementEngine.streak(supplement, now: now, calendar: .current)
        let week = SupplementEngine.week(supplement, now: now, calendar: .current)
        let takenThisWeek = week.filter(\.isTaken).count
        return Button {
            Haptics.impact(.light)
            editing = EditTarget(supplement: supplement, isNew: false)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: supplement.symbol)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.accentLight)
                        .frame(width: Spacing.minimumHitTarget, height: Spacing.minimumHitTarget)
                        .background(Circle().fill(AppColor.accentPrimary.opacity(0.15)))

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(supplement.name)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        if !supplement.detailText.isEmpty {
                            Text(supplement.detailText)
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }

                    Spacer(minLength: Spacing.sm)

                    if streak > 0 {
                        Label(String(streak), systemImage: "flame.fill")
                            .font(AppFont.chipText)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(AppColor.accentLight)
                    }
                    if supplement.reminderEnabled, supplement.minuteOfDay != nil {
                        Image(systemName: "bell.fill")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }

                weekDots(week)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Spacing.controlCornerRadius)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(supplement.name))
        .accessibilityValue(Text("Days in a row: \(streak). Taken \(takenThisWeek) of the last 7 days."))
        .accessibilityHint(Text("Opens the supplement's settings"))
    }

    /// Seven quiet dots, oldest first, with today ringed.
    private func weekDots(_ week: [SupplementEngine.DayDot]) -> some View {
        HStack(spacing: 0) {
            ForEach(week) { dot in
                VStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(dot.isTaken ? AppColor.accentPrimary : AppColor.surfaceSecondary)
                        .overlay {
                            if dot.isToday {
                                Circle().strokeBorder(AppColor.accentLight, lineWidth: 1.5)
                            }
                        }
                        .frame(width: Spacing.md, height: Spacing.md)
                    Text(dot.day.formatted(.dateTime.weekday(.narrow)))
                        .font(AppFont.badgeSmall)
                        .foregroundStyle(dot.isToday ? AppColor.textPrimary : AppColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Add

    private var addSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Add")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)

            FlowLayout(spacing: Spacing.sm) {
                ForEach(availablePresets) { preset in
                    chip(preset.name, symbol: preset.symbol) { add(preset) }
                        .accessibilityHint(Text("Adds \(preset.name) with \(preset.dose)"))
                }
                chip(String(localized: "Custom"), symbol: "plus") {
                    editing = EditTarget(supplement: Supplement(name: ""), isNew: true)
                }
                .accessibilityHint(Text("Name your own supplement"))
            }
        }
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(AppFont.chipText)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: Spacing.minimumHitTarget)
                .glassControl(.capsule, interactive: false)
        }
        .buttonStyle(ScalePressStyle())
    }

    /// A preset goes straight onto the list with its usual dose.
    private func add(_ preset: SupplementPreset) {
        Haptics.success()
        AppAnimation.with(AppAnimation.springSnappy) {
            dataStore.saveSupplement(preset.makeSupplement())
        }
    }
}
