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
    /// mark build, the day-of-month math, the month paging and the
    /// per-day selection. If `Calendar.current.firstWeekday` changes
    /// mid-session (locale flip, user-region change), capturing once
    /// into @State keeps the grid and the marks in lockstep; a relaunch
    /// picks up the new locale.
    @State private var calendar: Calendar = .current
    /// +1 when paging forward, -1 back — picks the side the next month
    /// slides in from.
    @State private var monthDirection = 1
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

    var body: some View {
        // Built once per body: the grid and the detail panel both read it.
        let doseMap = filteredMap
        VStack(spacing: Spacing.md) {
            if !activePeptides.isEmpty {
                filterShelf
            }

            modeToggle

            calendarCard(doseMap)

            DoseDayDetailPanel(
                day: selectedDay,
                marks: doseMap[calendar.startOfDay(for: selectedDay)] ?? [],
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
        // A filtered peptide whose protocol is paused or completed drops
        // out of the shelf; clear the filter with it so the calendar
        // can't stay stuck on a peptide with no pill (or no shelf) left.
        .onChange(of: activePeptides.map(\.id)) { _, ids in
            if let id = filterPeptideID, !ids.contains(id) {
                filterPeptideID = nil
            }
        }
    }

    // MARK: - Schedule / Cycle toggle

    private var modeToggle: some View {
        GlassSegmentedControl(
            options: CalendarDisplayMode.allCases,
            selected: $displayMode,
            label: { $0.label }
        )
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
        GlassChip("All", isSelected: filterPeptideID == nil) {
            AppAnimation.with(AppAnimation.springSnappy) { filterPeptideID = nil }
        }
    }

    private func filterPill(for peptide: Peptide) -> some View {
        let isActive = filterPeptideID == peptide.id
        return Button {
            AppAnimation.with(AppAnimation.springSnappy) {
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
        .accessibilityLabel("Show only \(peptide.name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Calendar card

    private func calendarCard(_ doseMap: [Date: [CalendarDoseMark]]) -> some View {
        GlassCard(padding: Spacing.lg) {
            VStack(spacing: Spacing.lg) {
                navigationHeader
                CalendarMonthView(
                    monthDate: monthDate,
                    dosesByDay: doseMap,
                    displayMode: displayMode,
                    bandsPerRow: bandsPerRow,
                    selectedDay: $selectedDay
                )
                .id(monthDate)
                .transition(.push(from: monthDirection > 0 ? .trailing : .leading))
            }
            .clipped()
        }
    }

    private var navigationHeader: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthDate.formatted(.dateTime.month(.wide)))
                    .font(AppFont.scaled(20, weight: .medium))
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

    /// Only shown off the current month — there's nowhere to jump to
    /// otherwise.
    @ViewBuilder
    private var todayButton: some View {
        let now = Date()
        if !calendar.isDate(monthDate, equalTo: now, toGranularity: .month) {
            Button {
                monthDirection = monthDate < now ? 1 : -1
                AppAnimation.with(AppAnimation.step) {
                    monthDate = calendar.startOfMonth(for: now)
                    selectedDay = calendar.startOfDay(for: now)
                }
                Haptics.selection()
            } label: {
                Text("Today")
                    .font(AppFont.badgeSmall)
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background {
                        Capsule()
                            .strokeBorder(AppColor.accentPrimary.opacity(0.4), lineWidth: 0.5)
                    }
                    .minimumHitArea()
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.9))
            .transition(.opacity.combined(with: .scale))
            .accessibilityLabel("Jump to today")
        }
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
        guard let next = calendar.date(byAdding: .month, value: months, to: monthDate) else { return }
        let newMonth = calendar.startOfMonth(for: next)
        let now = Date()
        monthDirection = months
        AppAnimation.with(AppAnimation.step) {
            monthDate = newMonth
            // Keep the detail panel on a day that's actually on screen:
            // today if it falls in the new month, else the 1st.
            selectedDay = calendar.isDate(newMonth, equalTo: now, toGranularity: .month)
                ? calendar.startOfDay(for: now)
                : newMonth
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
