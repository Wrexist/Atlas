import SwiftUI

/// Wraps the Track-tab calendar surface: filter shelf on top, month
/// navigation header, the 6-row grid, and the per-day detail panel
/// underneath. Self-contained so it can drop into the existing
/// `ProtocolListView` scroll content without entangling its other cards.
struct TrackCalendarSection: View {
    let entries: [ProtocolEntry]
    let protocols: [PeptideProtocol]
    let activePeptides: [Peptide]

    @State private var monthDate: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var filterPeptideID: UUID?
    @State private var displayMode: CalendarDisplayMode = .schedule

    private var filteredMap: [Date: [CalendarDoseMark]] {
        let raw = DoseDayMap.build(
            for: monthDate,
            entries: entries,
            protocols: protocols
        )
        guard let id = filterPeptideID else { return raw }
        return raw.mapValues { marks in
            marks.filter { $0.peptideID == id }
        }
    }

    private var bandsPerRow: [[CycleBand]] {
        let grid = CalendarMonth.grid(
            for: monthDate,
            firstWeekday: Calendar.current.firstWeekday
        )
        let scoped = filterPeptideID
            .map { id in protocols.filter { $0.peptides.contains(where: { $0.id == id }) } }
            ?? protocols
        return CycleBands.bands(for: grid, protocols: scoped)
    }

    private var selectedDayMarks: [CalendarDoseMark] {
        filteredMap[Calendar.current.startOfDay(for: selectedDay)] ?? []
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            if !activePeptides.isEmpty {
                filterShelf
            }

            modeToggle

            calendarCard

            DoseDayDetailPanel(day: selectedDay, marks: selectedDayMarks)
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
        .background {
            Capsule()
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    Capsule()
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .liquidGlass(.capsule)
    }

    private func modeChip(_ mode: CalendarDisplayMode) -> some View {
        let isSelected = displayMode == mode
        return Button {
            withAnimation(AppAnimation.springSnappy) { displayMode = mode }
            UISelectionFeedbackGenerator().selectionChanged()
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
                            .fill(AppColor.accentPrimary.opacity(0.28))
                            .overlay {
                                Capsule()
                                    .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                            }
                            .liquidGlass(.capsule)
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
            UISelectionFeedbackGenerator().selectionChanged()
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
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 2) {
                VialIllustration(
                    compoundName: peptide.name,
                    liquidLevel: 0.85,
                    labelText: nil,
                    size: .sm
                )

                Text(peptide.abbreviation)
                    .font(.system(size: 10, weight: .semibold))
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
        GlassCard {
            VStack(spacing: Spacing.md) {
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
        HStack {
            chevronButton(direction: -1, icon: "chevron.left")

            Spacer()

            Text(monthDate.formatted(.dateTime.month(.wide).year()))
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())

            Spacer()

            chevronButton(direction: 1, icon: "chevron.right")
        }
    }

    private func chevronButton(direction: Int, icon: String) -> some View {
        Button {
            shiftMonth(by: direction)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? "Previous month" : "Next month")
    }

    private func shiftMonth(by months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: monthDate) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            monthDate = Calendar.current.startOfMonth(for: next)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
