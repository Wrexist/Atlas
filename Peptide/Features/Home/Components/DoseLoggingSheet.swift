import SwiftUI

struct DoseLoggingSheet: View {
    let entry: ProtocolEntry
    /// The site of the previous injection, tagged on its chip so the user
    /// can rotate away from it without remembering where it was.
    let lastInjectionSite: String?
    let onLog: (String?, Date?, String?, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var actualDose: String
    @State private var actualTime: Date
    @State private var selectedSite: String?
    @State private var notes: String

    init(
        entry: ProtocolEntry,
        lastInjectionSite: String? = nil,
        onLog: @escaping (String?, Date?, String?, String) -> Void
    ) {
        self.entry = entry
        self.lastInjectionSite = lastInjectionSite
        self.onLog = onLog
        _actualDose = State(initialValue: entry.actualDose ?? entry.dose)
        _actualTime = State(initialValue: entry.defaultLoggedTime())
        _selectedSite = State(initialValue: entry.injectionSite)
        _notes = State(initialValue: entry.notes)
    }

    private var scheduledLine: String {
        let time = entry.date.formatted(.dateTime.hour().minute())
        return entry.dose.isEmpty
            ? String(localized: "Scheduled at \(time)")
            : String(localized: "Scheduled: \(entry.dose) at \(time)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Peptide info
                    GlassCard(tinted: true) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: entry.peptide.imageSystemName)
                                .font(AppFont.scaled(24))
                                .foregroundStyle(entry.peptide.category.color)
                                .frame(width: 48, height: 48)
                                .accessibilityHidden(true)              // peptide name + dose alongside carry the label
                                .background {
                                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                        .fill(entry.peptide.category.color.opacity(0.15))
                                }

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(entry.peptide.name)
                                    .font(AppFont.headline)
                                    .foregroundStyle(AppColor.textPrimary)
                                Text(scheduledLine)
                                    .font(AppFont.caption2)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer()
                        }
                    }

                    // Actual dose
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Actual dose", systemImage: "syringe.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            TextField("e.g., 250 mcg", text: $actualDose)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textPrimary)
                                .tint(AppColor.accentPrimary)
                                .padding(Spacing.md)
                                .background {
                                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                        .fill(AppColor.surfaceElevated)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                        }
                                }
                        }
                    }

                    // Time
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Time taken", systemImage: "clock.fill")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            // Never in the future; a dose from an earlier day can
                            // also move across midnight.
                            DatePicker(
                                "Time taken",
                                selection: $actualTime,
                                in: ...Date.now,
                                displayedComponents: Calendar.current.isDateInToday(entry.date)
                                    ? .hourAndMinute
                                    : [.date, .hourAndMinute]
                            )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(AppColor.accentPrimary)
                        }
                    }

                    // Injection site
                    if isInjectable {
                        GlassCard {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Label("Injection site", systemImage: "figure.arms.open")
                                        .font(AppFont.headline)
                                        .foregroundStyle(AppColor.textPrimary)
                                    if let lastSiteName {
                                        Text("Last used: \(lastSiteName) — pick another to rotate.")
                                            .font(AppFont.caption2)
                                            .foregroundStyle(AppColor.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                                    ForEach(InjectionSite.allCases, id: \.rawValue) { site in
                                        let isSelected = selectedSite == site.rawValue
                                        let isLastUsed = lastInjectionSite == site.rawValue
                                        Button {
                                            AppAnimation.with(AppAnimation.springBouncy) {
                                                selectedSite = isSelected ? nil : site.rawValue
                                            }
                                            Haptics.selection()
                                        } label: {
                                            HStack(spacing: Spacing.xs) {
                                                if isLastUsed {
                                                    Image(systemName: "clock.arrow.circlepath")
                                                        .font(AppFont.badgeSmall)
                                                        .accessibilityHidden(true)
                                                }
                                                Text(site.displayName)
                                            }
                                            .font(AppFont.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Spacing.sm)
                                            .frame(minHeight: Spacing.minimumHitTarget)
                                            .glassControl(
                                                .rect(cornerRadius: Spacing.chipCornerRadius),
                                                tint: isSelected ? AppColor.accentPrimary.opacity(0.25) : AppColor.surfaceElevated,
                                                border: isSelected ? AppColor.glassBorderActive : AppColor.glassBorder
                                            )
                                        }
                                        .buttonStyle(ScalePressStyle())
                                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                                        .accessibilityValue(isLastUsed ? Text("Last used") : Text(verbatim: ""))
                                    }
                                }
                            }
                        }
                    }

                    // Notes
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Label("Notes", systemImage: "note.text")
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            TextField("Optional notes", text: $notes, axis: .vertical)
                                .font(AppFont.body)
                                .foregroundStyle(AppColor.textPrimary)
                                .tint(AppColor.accentPrimary)
                                .lineLimit(2...4)
                                .padding(Spacing.md)
                                .background {
                                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                        .fill(AppColor.surfaceElevated)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                                        }
                                }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            // Pinned so the primary action is reachable without
            // scrolling past every field first.
            .pinnedFooter {
                // Re-opening a taken dose edits it rather than logging a second one.
                GlassButton(title: entry.completed ? "Save changes" : "Log dose", icon: "checkmark.circle.fill", style: .primary, isFullWidth: true) {
                    Haptics.success()
                    onLog(actualDose, actualTime, selectedSite, notes)
                    dismiss()
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.md)
            }
            .keyboardDoneButton()
            .background(AppColor.background)
            .navigationTitle(entry.completed ? "Edit dose" : "Log dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var lastSiteName: String? {
        guard let lastInjectionSite else { return nil }
        guard let site = InjectionSite(rawValue: lastInjectionSite) else { return lastInjectionSite }
        return String(localized: site.displayName)
    }

    /// Routes that take an injection site — intramuscular as well as
    /// subcutaneous, which the old substring check left out.
    private var isInjectable: Bool {
        let route = entry.peptide.adminRoute.lowercased()
        return route.contains("subcutaneous") || route.contains("intramuscular")
    }
}

extension ProtocolEntry {
    /// What the logging sheet's time picker starts on. A dose being logged
    /// on its own day starts at now — the actual time, which dose-timing
    /// insights read — rather than the scheduled time, which may still be
    /// ahead. An edit keeps the recorded time; a past day keeps its slot.
    func defaultLoggedTime(now: Date = Date(), calendar: Calendar = .current) -> Date {
        if let actualTime { return actualTime }
        if !completed, calendar.isDate(date, inSameDayAs: now) { return now }
        return min(date, now)
    }

    /// The site of the most recent injection logged at or before `now`,
    /// other than this dose — what the logging sheet tags for rotation.
    func lastInjectionSite(in entries: [ProtocolEntry], now: Date = Date()) -> String? {
        entries
            // An unchecked dose keeps its site but was never taken.
            .filter { $0.id != id && $0.completed }
            .compactMap { other -> (site: String, time: Date)? in
                guard let site = other.injectionSite, !site.isEmpty else { return nil }
                return (site, other.actualTime ?? other.date)
            }
            .filter { $0.time <= now }
            .max { $0.time < $1.time }?
            .site
    }
}
