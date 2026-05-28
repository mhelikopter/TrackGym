import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.kg.rawValue
    let plan: WorkoutPlan

    @State private var workoutEntries: [WorkoutEntry] = []
    @State private var workoutDate = Date()
    @State private var activeWorkout: Workout?
    @State private var showingCancelAlert = false
    @State private var showingFinishAlert = false
    @State private var showingAddExercise = false
    @State private var persistenceErrorMessage = ""
    @State private var showingPersistenceError = false
    @State private var previousEntries: [PersistentIdentifier: WorkoutEntry] = [:]

    @State private var startTime = Date()

    private func elapsedSeconds(now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(startTime)))
    }

    private func elapsedTimeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        NavigationStack {
            Group {
                if workoutEntries.isEmpty && activeWorkout == nil {
                    ContentUnavailableView {
                        Label("Keine Übungen", systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("Der Plan enthält keine Übungen.")
                    }
                } else {
                    List {
                        Section {
                            TimelineView(.periodic(from: startTime, by: 1)) { context in
                                HStack {
                                    Label("Trainingszeit", systemImage: "timer")
                                    Spacer()
                                    Text(elapsedTimeString(elapsedSeconds(now: context.date)))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(.blue)
                                }
                            }
                            DatePicker("Datum", selection: $workoutDate, displayedComponents: .date)
                        }

                        // Exercise sections
                        ForEach(workoutEntries, id: \.persistentModelID) { entry in
                            ActiveEntrySection(
                                entry: entry,
                                previousEntry: cachedPreviousEntry(for: entry.exercise),
                                onSave: { saveEntry(entry) }
                            )
                        }

                        // Add exercise button below all exercises
                        Section {
                            Button {
                                showingAddExercise = true
                            } label: {
                                Label("Übung hinzufügen", systemImage: "plus.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle(plan.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        showingCancelAlert = true
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Beenden") {
                        showingFinishAlert = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                startTime = Date()
                setupExercises()
                sendCurrentExerciseToWatch()
            }
            .onChange(of: workoutDate) { _, newDate in
                for entry in workoutEntries {
                    entry.date = newDate
                }
                activeWorkout?.date = newDate
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchDidAddSet)) { notification in
                guard let info = notification.userInfo,
                      let weight = info["weight"] as? Double,
                      let reps = info["reps"] as? Int,
                      let entry = workoutEntries.first,
                      let currentName = entry.exercise?.name else { return }
                if let expected = info["exerciseName"] as? String,
                   !expected.isEmpty,
                   expected != currentName {
                    return
                }
                addSetFromWatch(to: entry, weight: weight, reps: reps)
            }
            .alert("Training abbrechen?", isPresented: $showingCancelAlert) {
                Button("Training abbrechen", role: .destructive) { cancelWorkout() }
                Button("Weiter trainieren", role: .cancel) {}
            } message: {
                Text("Alle nicht gespeicherten Sätze gehen verloren.")
            }
            .alert("Training beenden?", isPresented: $showingFinishAlert) {
                Button("Beenden & speichern") { finishAllAndEnd() }
                Button("Weiter trainieren", role: .cancel) {}
            } message: {
                Text("Alle verbleibenden Übungen werden gespeichert.")
            }
            .alert("Training konnte nicht gespeichert werden", isPresented: $showingPersistenceError) {
                Button("OK") {}
            } message: {
                Text(persistenceErrorMessage)
            }
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerView { exercises in
                    for exercise in exercises {
                        addExercise(exercise)
                    }
                }
            }
        }
    }

    // MARK: - Setup

    private func setupExercises() {
        // Guard against re-runs (e.g. when the view re-appears after a sheet
        // is dismissed or the app returns from background). Without this, the
        // plan's exercises get appended again, creating duplicate entries.
        guard workoutEntries.isEmpty && activeWorkout == nil else { return }
        for exercise in plan.exercises {
            addExercise(exercise)
        }
    }

    // MARK: - Logic

    private func addExercise(_ exercise: Exercise) {
        let previousEntry = findPreviousEntry(for: exercise)
        if let previousEntry {
            previousEntries[exercise.persistentModelID] = previousEntry
        }
        let previousFirstSet = previousEntry?.sortedSets.first

        let entry = WorkoutEntry(date: workoutDate, exercise: exercise)
        modelContext.insert(entry)

        let firstSet = WorkoutSet(
            setNumber: 1,
            weight: previousFirstSet?.weight ?? 0,
            reps: previousFirstSet?.reps ?? 0,
            workoutEntry: entry
        )
        modelContext.insert(firstSet)
        entry.sets.append(firstSet)
        workoutEntries.append(entry)
    }

    private func cachedPreviousEntry(for exercise: Exercise?) -> WorkoutEntry? {
        guard let exercise else { return nil }
        return previousEntries[exercise.persistentModelID]
    }

    private func findPreviousEntry(for exercise: Exercise?) -> WorkoutEntry? {
        WorkoutHistory.previousEntry(
            for: exercise,
            in: modelContext,
            excluding: workoutEntries,
            activeWorkout: activeWorkout
        )
    }

    private func saveEntry(_ entry: WorkoutEntry) {
        let seconds = elapsedSeconds(now: Date())
        if activeWorkout == nil {
            let workout = Workout(name: plan.name, date: workoutDate, duration: seconds)
            workout.plan = plan
            modelContext.insert(workout)
            activeWorkout = workout
        } else {
            activeWorkout?.duration = seconds
        }

        entry.date = workoutDate
        entry.workout = activeWorkout

        guard persistWorkoutChanges() else { return }

        withAnimation {
            workoutEntries.removeAll { $0.persistentModelID == entry.persistentModelID }
        }

        if workoutEntries.isEmpty {
            // Saving the last remaining entry also ends the workout, so the
            // watch must be told to clear its active-exercise UI.
            PhoneConnectivityManager.shared.sendWorkoutEnded()
            dismiss()
        } else {
            sendCurrentExerciseToWatch()
        }
    }

    private func finishAllAndEnd() {
        let seconds = elapsedSeconds(now: Date())
        if activeWorkout == nil && !workoutEntries.isEmpty {
            let workout = Workout(name: plan.name, date: workoutDate, duration: seconds)
            workout.plan = plan
            modelContext.insert(workout)
            activeWorkout = workout
        } else {
            activeWorkout?.duration = seconds
        }
        for entry in workoutEntries {
            entry.date = workoutDate
            entry.workout = activeWorkout
        }

        guard persistWorkoutChanges() else { return }

        workoutEntries.removeAll()
        PhoneConnectivityManager.shared.sendWorkoutEnded()
        dismiss()
    }

    private func cancelWorkout() {
        // Delete any pending in-memory entries that were never attached to a
        // workout. Entries already linked to `activeWorkout` will be removed by
        // the cascade rule on `Workout.entries` when we delete the workout.
        for entry in workoutEntries where entry.workout == nil {
            modelContext.delete(entry)
        }

        // If the user already saved at least one entry mid-workout, the
        // partial `Workout` was inserted into the context. Without this delete
        // it would be silently persisted (potentially with zero entries).
        if let workout = activeWorkout {
            modelContext.delete(workout)
        }

        guard persistWorkoutChanges(
            failureMessage: "Das abgebrochene Training konnte nicht vollständig verworfen werden. Bitte versuche es erneut."
        ) else { return }

        workoutEntries.removeAll()
        activeWorkout = nil
        PhoneConnectivityManager.shared.sendWorkoutEnded()
        dismiss()
    }

    // MARK: - Watch Connectivity

    private func sendCurrentExerciseToWatch() {
        guard let entry = workoutEntries.first,
              let exercise = entry.exercise else { return }
        let payload = entry.sortedSets.map {
            WatchSetPayload(setNumber: $0.setNumber, weight: $0.weight, reps: $0.reps)
        }
        PhoneConnectivityManager.shared.sendActiveExercise(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup.rawValue,
            unit: weightUnit,
            sets: payload
        )
    }

    private func addSetFromWatch(to entry: WorkoutEntry, weight: Double, reps: Int) {
        WorkoutHistory.appendSet(weight: weight, reps: reps, to: entry, in: modelContext)
        sendCurrentExerciseToWatch()
    }

    private func persistWorkoutChanges(
        failureMessage: String = "Deine Änderungen wurden nicht dauerhaft gespeichert. Bitte versuche es erneut."
    ) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            persistenceErrorMessage = failureMessage
            showingPersistenceError = true
            return false
        }
    }
}

// MARK: - Active Entry Section

private struct ActiveEntrySection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: WorkoutEntry
    let previousEntry: WorkoutEntry?
    let onSave: () -> Void

    var body: some View {
        Section {
            if let prev = previousEntry {
                ActivePreviousReference(entry: prev)
            }

            ForEach(entry.sortedSets) { set in
                ActiveSetRow(set: set)
            }
            .onDelete { offsets in
                deleteSets(at: offsets)
            }

            Button {
                addSet()
            } label: {
                Label("Satz hinzufügen", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } header: {
            HStack {
                Text(entry.exercise?.name ?? "Übung")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    onSave()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
            .textCase(nil)
        }
    }

    private func addSet() {
        let nextNumber = (entry.sets.map(\.setNumber).max() ?? 0) + 1
        let previousSet = previousEntry?.sortedSets.first { $0.setNumber == nextNumber }
            ?? previousEntry?.sortedSets.last

        let newSet = WorkoutSet(
            setNumber: nextNumber,
            weight: previousSet?.weight ?? 0,
            reps: previousSet?.reps ?? 0,
            workoutEntry: entry
        )
        modelContext.insert(newSet)
        entry.sets.append(newSet)
    }

    private func deleteSets(at offsets: IndexSet) {
        let sorted = entry.sortedSets
        for index in offsets {
            let set = sorted[index]
            entry.sets.removeAll { $0.persistentModelID == set.persistentModelID }
            modelContext.delete(set)
        }
    }
}

// MARK: - Set Row

private struct ActiveSetRow: View {
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.kg.rawValue
    @Bindable var set: WorkoutSet

    var body: some View {
        HStack(spacing: 12) {
            Text("Satz \(set.setNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 4) {
                TextField("0", value: $set.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text(weightUnit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                TextField("0", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("Wdh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previous Workout Reference

private struct ActivePreviousReference: View {
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.kg.rawValue
    let entry: WorkoutEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Letztes Training: \(entry.date, format: .dateTime.day().month())")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(entry.sortedSets) { set in
                Text("\(set.weight, specifier: "%.1f") \(weightUnit) × \(set.reps) Wdh")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
