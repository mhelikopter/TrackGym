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
    var exerciseName: String
    var date: Date
    var sets: [ExportWorkoutSet]
}

struct ExportWorkoutSet: Codable {
    var setNumber: Int
    var weight: Double
    var reps: Int
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
                        exerciseName: entry.exercise?.name ?? "",
                        date: entry.date,
                        sets: entry.sortedSets.map { set in
                            ExportWorkoutSet(
                                setNumber: set.setNumber,
                                weight: set.weight,
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

        do {
            try deleteAll(WorkoutSet.self, in: context)
            try deleteAll(WorkoutEntry.self, in: context)
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
                exercise.imageURL = ex.imageURL
                context.insert(exercise)
                exerciseMap[ex.name] = exercise
            }

            for planData in importData.workoutPlans {
                let plan = WorkoutPlan(name: planData.name)
                plan.exercises = planData.exerciseNames.compactMap { exerciseMap[$0] }
                context.insert(plan)
            }

            for workoutData in importData.workouts {
                let workout = Workout(name: workoutData.name, date: workoutData.date, duration: workoutData.duration)
                context.insert(workout)

                for entryData in workoutData.entries {
                    guard let exercise = exerciseMap[entryData.exerciseName] else { continue }
                    let entry = WorkoutEntry(date: entryData.date, exercise: exercise)
                    entry.workout = workout
                    context.insert(entry)

                    for setData in entryData.sets {
                        let workoutSet = WorkoutSet(
                            setNumber: setData.setNumber,
                            weight: setData.weight,
                            reps: setData.reps,
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
