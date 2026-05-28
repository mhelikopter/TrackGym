import Foundation
import SwiftData

// MARK: - Export/Import DTOs

struct ExportData: Codable {
    var exercises: [ExportExercise]
    var workoutPlans: [ExportWorkoutPlan]
    var workouts: [ExportWorkout]
}

struct ExportExercise: Codable {
    var name: String
    var muscleGroup: String
    var equipmentType: String
    var isCustom: Bool
    var imageURL: String?
}

struct ExportWorkoutPlan: Codable {
    var name: String
    var exerciseNames: [String]
}

struct ExportWorkout: Codable {
    var name: String
    var date: Date
    var duration: Int
    var entries: [ExportWorkoutEntry]
}

struct ExportWorkoutEntry: Codable {
    /// Optional so entries whose exercise was deleted (or never linked) survive
    /// a round-trip without being silently dropped on import.
    var exerciseName: String?
    var date: Date
    var sets: [ExportWorkoutSet]
}

struct ExportWorkoutSet: Codable {
    var setNumber: Int
    var weight: Double
    var weightUnit: String?
    var reps: Int

    var resolvedWeightUnit: WeightUnit {
        weightUnit.flatMap(WeightUnit.init(rawValue:)) ?? .kg
    }
}

// MARK: - Errors

enum DataExporterError: LocalizedError {
    /// Two or more exercises in the export share the same name, which would
    /// silently merge them on import and re-link history to the wrong row.
    case duplicateExerciseNames([String])

    var errorDescription: String? {
        switch self {
        case .duplicateExerciseNames(let names):
            let joined = names.joined(separator: ", ")
            return "Import abgebrochen: doppelte Übungsnamen erkannt (\(joined))."
        }
    }
}

// MARK: - Exporter

enum DataExporter {
    static func exportData(context: ModelContext) throws -> Data {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>())
        let workouts = try context.fetch(FetchDescriptor<Workout>())

        let exportExercises = exercises.map { exercise in
            ExportExercise(
                name: exercise.name,
                muscleGroup: exercise.muscleGroupRaw,
                equipmentType: exercise.equipmentTypeRaw,
                isCustom: exercise.isCustom,
                imageURL: exercise.imageURL
            )
        }

        let exportPlans = plans.map { plan in
            ExportWorkoutPlan(
                name: plan.name,
                exerciseNames: plan.exercises.map(\.name)
            )
        }

        let exportWorkouts = workouts.map { workout in
            ExportWorkout(
                name: workout.name,
                date: workout.date,
                duration: workout.duration,
                entries: workout.entries.map { entry in
                    ExportWorkoutEntry(
                        exerciseName: entry.exercise?.name,
                        date: entry.date,
                        sets: entry.sortedSets.map { set in
                            ExportWorkoutSet(
                                setNumber: set.setNumber,
                                weight: set.weight,
                                weightUnit: WeightUnit.kg.rawValue,
                                reps: set.reps
                            )
                        }
                    )
                }
            )
        }

        let exportData = ExportData(
            exercises: exportExercises,
            workoutPlans: exportPlans,
            workouts: exportWorkouts
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportData)
    }

    static func importData(from data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importData = try decoder.decode(ExportData.self, from: data)

        // MHE-5: Reject imports that contain duplicate exercise names up-front.
        // The import path resolves entries by name only, so silently merging
        // duplicates would re-link history to the wrong Exercise on round-trip.
        let normalizedToOriginal = importData.exercises.reduce(into: [String: String]()) { mapping, exercise in
            let normalized = Exercise.normalizedName(exercise.name)
            mapping[normalized] = mapping[normalized] ?? exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let duplicates = importData.exercises
            .map { Exercise.normalizedName($0.name) }
            .reduce(into: [String: Int]()) { counts, name in counts[name, default: 0] += 1 }
            .filter { $0.value > 1 }
            .compactMap { normalizedToOriginal[$0.key] }
            .sorted()
        if !duplicates.isEmpty {
            throw DataExporterError.duplicateExerciseNames(duplicates)
        }

        do {
            // MHE-7: Delete only the roots and let SwiftData's cascade rules
            // (`Workout.entries` -> `WorkoutEntry.sets`) propagate. This removes
            // the brittle fixed-order fetch/delete that could leave the store
            // inconsistent on partial failure.
            try deleteAll(Workout.self, in: context)
            try deleteAll(WorkoutPlan.self, in: context)
            try deleteAll(Exercise.self, in: context)

            var exerciseMap: [String: Exercise] = [:]
            for ex in importData.exercises {
                let exercise = Exercise(
                    name: ex.name,
                    muscleGroup: MuscleGroup(rawValue: ex.muscleGroup) ?? .chest,
                    equipmentType: EquipmentType(rawValue: ex.equipmentType) ?? .machine,
                    isCustom: ex.isCustom
                )
                exercise.imageURL = nil
                context.insert(exercise)
                exerciseMap[Exercise.normalizedName(ex.name)] = exercise
            }

            for planData in importData.workoutPlans {
                let plan = WorkoutPlan(name: planData.name)
                plan.exercises = planData.exerciseNames.compactMap {
                    exerciseMap[Exercise.normalizedName($0)]
                }
                context.insert(plan)
            }

            for workoutData in importData.workouts {
                let workout = Workout(name: workoutData.name, date: workoutData.date, duration: workoutData.duration)
                context.insert(workout)

                for entryData in workoutData.entries {
                    // MHE-6: Preserve entries whose exercise reference is nil
                    // (or whose name didn't resolve, e.g. data from an older
                    // export with an empty string). The Workout model already
                    // tolerates `exercise: nil`, so dropping these silently
                    // was the only thing causing data loss.
                    let exercise: Exercise? = entryData.exerciseName.flatMap {
                        exerciseMap[Exercise.normalizedName($0)]
                    }
                    let entry = WorkoutEntry(date: entryData.date, exercise: exercise)
                    entry.workout = workout
                    context.insert(entry)

                    for setData in entryData.sets {
                        let workoutSet = WorkoutSet(
                            setNumber: setData.setNumber,
                            weight: setData.weight,
                            reps: setData.reps,
                            unit: setData.resolvedWeightUnit,
                            workoutEntry: entry
                        )
                        context.insert(workoutSet)
                        entry.sets.append(workoutSet)
                    }
                }
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        for item in items { context.delete(item) }
    }
}
