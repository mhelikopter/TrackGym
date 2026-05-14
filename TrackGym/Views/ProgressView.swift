import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var selectedExercise: Exercise?

    private var exercisesWithData: [Exercise] {
        exercises
            .filter { !$0.completedWorkoutEntries.isEmpty }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if exercisesWithData.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Daten vorhanden", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Speichere ein Training, um deinen Fortschritt zu sehen.")
                    }
                } else {
                    ExerciseSelectionPicker(
                        exercises: exercisesWithData,
                        selection: $selectedExercise
                    )

                    if let exercise = selectedExercise {
                        ExerciseProgressView(exercise: exercise)
                    } else {
                        OverallProgressView(exercises: exercisesWithData)
                    }
                }
            }
            .navigationTitle("Fortschritt")
            .onChange(of: exercisesWithData) { _, newValue in
                if let selected = selectedExercise,
                   !newValue.contains(where: { $0.persistentModelID == selected.persistentModelID }) {
                    selectedExercise = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }
}

// MARK: - Picker

private struct ExerciseSelectionPicker: View {
    let exercises: [Exercise]
    @Binding var selection: Exercise?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selection = nil
                } label: {
                    Text("Gesamt")
                        .font(.subheadline)
                        .fontWeight(selection == nil ? .semibold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selection == nil ? Color.blue : Color(.systemGray5))
                        .foregroundStyle(selection == nil ? .white : .primary)
                        .clipShape(Capsule())
                }

                ForEach(exercises) { exercise in
                    Button {
                        selection = exercise
                    } label: {
                        Text(exercise.name)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selection?.persistentModelID == exercise.persistentModelID ? Color.blue : Color(.systemGray5))
                            .foregroundStyle(selection?.persistentModelID == exercise.persistentModelID ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Overall Progress

private struct OverallProgressView: View {
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.kg.rawValue
    let exercises: [Exercise]

    private var workouts: [Workout] {
        let entries = exercises.flatMap(\.completedWorkoutEntries)
        let keyed: [PersistentIdentifier: Workout] = entries.reduce(into: [:]) { result, entry in
            guard let workout = entry.workout else { return }
            result[workout.persistentModelID] = workout
        }
        return keyed.values.sorted { $0.date < $1.date }
    }

    private var volumeByWorkout: [(id: PersistentIdentifier, date: Date, volume: Double)] {
        workouts.map { workout in
            (
                id: workout.persistentModelID,
                date: workout.date,
                volume: workout.entries.reduce(0) { $0 + $1.totalVolume }
            )
        }
    }

    private var totalWorkouts: Int {
        workouts.count
    }

    private var totalVolume: Double {
        volumeByWorkout.reduce(0) { $0 + $1.volume }
    }

    private var averageVolume: Double {
        totalWorkouts > 0 ? totalVolume / Double(totalWorkouts) : 0
    }

    var body: some View {
        List {
            if !volumeByWorkout.isEmpty {
                Section("Gesamtvolumen pro Training") {
                    Chart {
                        ForEach(volumeByWorkout, id: \.id) { point in
                            LineMark(
                                x: .value("Datum", point.date),
                                y: .value("Volumen (\(weightUnit))", point.volume)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)

                            PointMark(
                                x: .value("Datum", point.date),
                                y: .value("Volumen (\(weightUnit))", point.volume)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                    .chartYAxisLabel(weightUnit)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month())
                        }
                    }
                    .frame(height: 200)
                    .padding(.horizontal)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Zusammenfassung") {
                    StatRow(icon: "calendar", label: "Trainingstage", value: "\(totalWorkouts)")
                    StatRow(icon: "scalemass.fill", label: "Gesamtvolumen", value: formatWeight(totalVolume))
                    StatRow(icon: "chart.bar.fill", label: "Ø Volumen pro Training", value: formatWeight(averageVolume))
                    StatRow(icon: "dumbbell.fill", label: "Übungen trainiert", value: "\(exercises.count)")
                }
            }
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        let unit = weightUnit
        if weight >= 1000 {
            return String(format: "%.1f t", weight / 1000)
        }
        return String(format: "%.0f \(unit)", weight)
    }
}

private struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Exercise Progress

private struct ExerciseProgressView: View {
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.kg.rawValue
    let exercise: Exercise

    private var sortedEntries: [WorkoutEntry] {
        exercise.completedWorkoutEntries.sorted { $0.date < $1.date }
    }

    private var personalRecord: Double {
        exercise.completedWorkoutEntries.flatMap(\.sets).map(\.weight).max() ?? 0
    }

    var body: some View {
        List {
            if sortedEntries.isEmpty {
                Section {
                    Text("Noch keine Einträge für diese Übung.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Gewichtsentwicklung") {
                    Chart {
                        ForEach(sortedEntries) { entry in
                            LineMark(
                                x: .value("Datum", entry.date),
                                y: .value("Gewicht (\(weightUnit))", entry.maxWeight)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.blue)

                            PointMark(
                                x: .value("Datum", entry.date),
                                y: .value("Gewicht (\(weightUnit))", entry.maxWeight)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                    .chartYAxisLabel(weightUnit)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month())
                        }
                    }
                    .frame(height: 200)
                    .padding(.horizontal)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                if personalRecord > 0 {
                    Section {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            Text("Persönlicher Rekord")
                                .font(.headline)
                            Spacer()
                            Text("\(personalRecord, specifier: "%.1f") \(weightUnit)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Section("Trainingshistorie") {
                    ForEach(sortedEntries.reversed()) { entry in
                        HistoryEntryRow(entry: entry, personalRecord: personalRecord)
                    }
                }
            }
        }
    }
}

private extension Exercise {
    var completedWorkoutEntries: [WorkoutEntry] {
        workoutEntries.filter { $0.workout != nil }
    }
}

private struct HistoryEntryRow: View {
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.kg.rawValue
    let entry: WorkoutEntry
    let personalRecord: Double

    private var isPR: Bool {
        entry.maxWeight == personalRecord && personalRecord > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date, format: .dateTime.day().month().year())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if isPR {
                    Text("PR")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.3))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("Max: \(entry.maxWeight, specifier: "%.1f") \(weightUnit)")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            ForEach(entry.sortedSets) { set in
                HStack {
                    Text("Satz \(set.setNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(set.weight, specifier: "%.1f") \(weightUnit) × \(set.reps) Wdh")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
