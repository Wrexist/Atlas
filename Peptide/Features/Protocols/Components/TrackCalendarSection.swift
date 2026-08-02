import SwiftUI

/// Wraps the Track-tab calendar surface: filter shelf on top, month
/// navigation header, the 6-row grid, and the per-day detail panel
/// underneath. Self-contained so it can drop into the existing
/// `ProtocolListView` scroll content without entangling its other cards.
struct TrackCalendarSection: View {
    @Environment(DataStore.self) private var dataStore

    let entries: [ProtocolEntry]
    let protocols: [PeptideProtocol]
    let activePeptides: [Peptide]

    /// Single calendar reference shared across the grid build, the
    /// mark build, the day-of-month math, and the per-day selection.
    /// If `Calendar.current.firstWeekday` ever changes mid-session
    /// (locale flip, user-region change), capturing once into @State
    /// keeps the grid and the marks in lockstep. Re-init on the
    /// view's `.task` so a relaunch picks up the new locale.
    @State private var calendar: Calendar = .current
    @State private var monthDate: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var filterPeptideID: UUID?
    @State private var displayMode: CalendarDisplayMode = .schedule
    /// Drives the dose edit sheet. Set when the user taps a logged mark
    /// in the day panel or picks "Edit" from its context menu. `.sheet(item:)`
    /// owns presentation so SwiftUI cleans the modal up after dismiss.
    @State private var editingEntry: ProtocolEntry?

    private var filteredMap: [Date: [CalendarDoseMark]] {
        let raw = DoseDayMap.build(
            for: monthDate,
            entries: entries,
            protocols: protocols,
            calendar: calendar
        )
        guard let id = filterPeptideID else { return raw }
        return raw.mapValues { marks in
            marks.filter { $0.peptideID == id }
        }
    }

    private var bandsPerRow: [[CycleBand]] {
        let grid = CalendarMonth.grid(
            for: monthDate,
            firstWeekday: calendar.firstWeekday,
            calendar: calendar
        )
        let scoped = filterPeptideID
            .map { id in protocols.filter { $0.peptides.contains(where: { $0.id == id }) } }
            ?? protocols
        return CycleBands.bands(for: grid, protocols: scoped)
    }

    private var selectedDayMarks: [CalendarDoseMark] {
        filteredMap[calendar.startOfDay(for: selectedDay)] ?? []
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            if !activePeptides.isEmpty {
                filterShelf
            }

            modeToggle

            calendarCard

            DoseDayDetailPanel(
                day: selectedDay,
                marks: selectedDayMarks,
                onEditEntry: { entryID in
                    // Resolve to the live entry — the panel only carries the
                    // ID, not the full ProtocolEntry, so re-renders after a
                    // log mutation always pick up the latest snapshot.
                    editingEntry = entries.first { $0.id == entryID }
                },
                onDeleteEntry: { entryID in
                    dataStore.unlogDose(entryId: entryID)
                }
            )
        }
        .sheet(item: $editingEntry) { entry in
            DoseLoggingSheet(entry: entry) { actualDose, actualTime, site, notes in
                dataStore.logDose(
                    entryId: entry.id,
                    actualDose: actualDose,
                    actualTime: actualTime,
                    injectionSite: site,
                    notes: notes
                )
            }
            .liquidGlassPresentation()
        }
    }

    // MARK: - Schedule / Cycle toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(CalendarDisplayMode.allCases) { mode in
                modeChip(mode)
            }
        }
        .padding(4)
        .glassControl(.capsule)
    }

    private func modeChip(_ mode: CalendarDisplayMode) -> some View {
        let isSelected = displayMode == mode
        return Button {
            withAnimation(AppAnimation.springSnappy) { displayMode = mode }
            Haptics.selection()
        } label: {
            Text(mode.label)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(AppColor.accentPrimary.opacity(0.18))
                            .overlay {
                                Capsule()
                                    .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                            }
                    }
                }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Filter shelf

    private var filterShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                allFilterPill

                ForEach(activePeptides) { peptide in
                    filterPill(for: peptide)
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
        }
    }

    private var allFilterPill: some View {
        let isActive = filterPeptideID == nil
        return Button {
            withAnimation(AppAnimation.springSnappy) { filterPeptideID = nil }
            Haptics.selection()
        } label: {
            Text("All")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isActive ? AppColor.textPrimary : AppColor.textSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background {
                    Capsule()
                        .fill(isActive ? AppColor.accentPrimary.opacity(0.22) : AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            Capsule().strokeBorder(
                                isActive ? AppColor.accentPrimary.opacity(0.45) : AppColor.glassBorder,
                                lineWidth: 0.5
                            )
                        }
                }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
    }

    private func filterPill(for peptide: Peptide) -> some View {
        let isActive = filterPeptideID == peptide.id
        return Button {
            withAnimation(AppAnimation.springSnappy) {
                filterPeptideID = isActive ? nil : peptide.id
            }
            Haptics.selection()
        } label: {
            VStack(spacing: 2) {
                CompoundVial(
                    compoundName: peptide.name,
                    category: peptide.category,
                    liquidLevel: 0.85,
                    labelText: nil,
                    size: .sm
                )

                Text(peptide.abbreviation)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(isActive ? AppColor.accentPrimary : AppColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(isActive ? AppColor.accentPrimary.opacity(0.15) : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(
                                isActive ? AppColor.accentPrimary.opacity(0.45) : Color.clear,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
    }

    // MARK: - Calendar card

    private var calendarCard: some View {
        GlassCard(padding: Spacing.lg) {
            VStack(spacing: Spacing.lg) {
                navigationHeader
                CalendarMonthView(
                    monthDate: monthDate,
                    dosesByDay: filteredMap,
                    displayMode: displayMode,
                    bandsPerRow: bandsPerRow,
                    selectedDay: $selectedDay
                )
            }
        }
    }

    private var navigationHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthDate.formatted(.dateTime.month(.wide)))
                    .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
                Text(monthDate.formatted(.dateTime.year()))
                    .font(AppFont.scaled(11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            todayButton

            HStack(spacing: 4) {
                chevronButton(direction: -1, icon: "chevron.left")
                chevronButton(direction: 1, icon: "chevron.right")
            }
        }
    }

    private var todayButton: some View {
        let isOnCurrentMonth = Calendar.current.isDate(
            monthDate,
            equalTo: Date(),
            toGranularity: .month
        )
        return Button {
            let now = Date()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                monthDate = Calendar.current.startOfMonth(for: now)
                selectedDay = Calendar.current.startOfDay(for: now)
            }
            Haptics.selection()
        } label: {
            Text("Today")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(isOnCurrentMonth ? AppColor.textTertiary : AppColor.accentLight)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .strokeBorder(
                            isOnCurrentMonth ? AppColor.glassBorder : AppColor.accentPrimary.opacity(0.4),
                            lineWidth: 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(isOnCurrentMonth)
        .opacity(isOnCurrentMonth ? 0.55 : 1)
        .accessibilityLabel("Jump to today")
    }

    private func chevronButton(direction: Int, icon: String) -> some View {
        Button {
            shiftMonth(by: direction)
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(AppColor.surfaceElevated.opacity(0.6))
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
                .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.9))
        .accessibilityLabel(direction < 0 ? "Previous month" : "Next month")
    }

    private func shiftMonth(by months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: monthDate) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            monthDate = Calendar.current.startOfMonth(for: next)
        }
        Haptics.impact(.light)
    }
}

// MARK: - Calendar helper

extension Calendar {
    /// Returns the first instant of the month that contains `date`. Used
    /// to pin `monthDate` to a stable anchor regardless of which day in
    /// the month the user happened to be on when navigation started.
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
