import SwiftUI

/// The routine library — the Train tab's answer to "what am I doing
/// today?". Cards are a `List` rather than the usual `LazyVStack` so
/// drag-to-reorder, swipe-to-delete and their VoiceOver equivalents come
/// from the system instead of being re-implemented on a stack; the row
/// chrome is still `RoutineCard`, so it reads as the same surface.
struct RoutinesView: View {
    /// The Train tab's navigation path, so creating a routine can push
    /// straight into its builder instead of leaving the user to find the
    /// empty row they just made.
    @Binding var path: [TrainNavigation]

    @State private var store = RoutineStore.shared
    @State private var library = ExerciseLibrary.shared
    /// Library lookups resolved off the render path — see `RoutineSummary`.
    @State private var summaries: [RoutineSummary] = []
    @State private var renaming: Routine?
    @State private var renameText: String = ""
    @State private var pendingDeletion: Routine?

    var body: some View {
        Group {
            if store.routines.isEmpty {
                emptyState
            } else {
                routineList
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .toolbar {
            if !store.routines.isEmpty {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
        .task {
            await library.load()
            store.load()
            // Explicit rebuild as well as the .task(id:) below: if the
            // library finishes loading after an unchanged routine list,
            // nothing else would resolve the exercise names.
            rebuildSummaries()
        }
        .task(id: store.routines) { rebuildSummaries() }
        .alert("Rename routine", isPresented: renameBinding) {
            TextField("Routine name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let routine = renaming {
                    store.rename(id: routine.id, to: renameText)
                }
                renaming = nil
            }
        }
        .alert(
            "Delete routine?",
            isPresented: deleteBinding,
            presenting: pendingDeletion
        ) { routine in
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                withAnimation(AppAnimation.springSnappy) { store.delete(id: routine.id) }
                pendingDeletion = nil
            }
        } message: { routine in
            Text("\"\(routine.name)\" will be removed. Workouts you already logged from it are kept.")
        }
    }

    // MARK: - List

    private var routineList: some View {
        VStack(spacing: 0) {
            newRoutineButton
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.sm)

            List {
                ForEach(summaries) { summary in
                    RoutineCard(
                        summary: summary,
                        onOpen: { open(summary.routine.id) },
                        onStart: { start(summary.routine) }
                    )
                    .listRowInsets(EdgeInsets(
                        top: Spacing.xs,
                        leading: Spacing.screenPadding,
                        bottom: Spacing.xs,
                        trailing: Spacing.screenPadding
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .contextMenu { menu(for: summary.routine) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = summary.routine
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    store.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .padding(.top, Spacing.xs)
    }

    private var newRoutineButton: some View {
        GlassButton(title: "New routine", icon: "plus", style: .secondary, isFullWidth: true) {
            open(store.create(name: RoutineStore.untitledName).id)
        }
    }

    @ViewBuilder
    private func menu(for routine: Routine) -> some View {
        Button {
            open(routine.id)
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }
        Button {
            renameText = routine.name
            renaming = routine
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            if let copy = store.duplicate(id: routine.id) {
                Haptics.success()
                open(copy.id)
            }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) {
            pendingDeletion = routine
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                EmptyStateView(
                    icon: "list.bullet.rectangle.portrait.fill",
                    title: "No routines yet",
                    message: "A routine is your workout written down — the lifts, in order, with the sets and reps you're aiming for. Save one and every session after this starts with a single tap.",
                    action: .init(title: "Build a routine", icon: "plus") {
                        open(store.create(name: RoutineStore.untitledName).id)
                    }
                )

                StarterRoutineSuggestions { create(from: $0) }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    // MARK: - Actions

    private func create(from template: RoutineTemplate) {
        open(store.create(name: template.name, exercises: template.makeExercises()).id)
    }

    private func open(_ id: UUID) {
        path.append(.routineBuilder(id))
    }

    private func start(_ routine: Routine) {
        store.startWorkout(from: routine)
    }

    private func rebuildSummaries() {
        summaries = store.routines.map { routine in
            RoutineSummary.make(routine: routine) { library.lookup(id: $0) }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }
}

#Preview("Routines") {
    @Previewable @State var path: [TrainNavigation] = []
    NavigationStack(path: $path) {
        RoutinesView(path: $path)
            .navigationTitle("Train")
    }
    .preferredColorScheme(.dark)
}
