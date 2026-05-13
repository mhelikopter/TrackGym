import Foundation
import SwiftData

enum WorkoutHistory {
    static func previousEntry(
        for exercise: Exercise?,
        in context: ModelContext,
        excluding currentEntries: [WorkoutEntry] = [],
        activeWorkout: Workout? = nil
    ) -> WorkoutEntry? {
        guard let exercise else { return nil }
        let exerciseName = exercise.name
        var descriptor = FetchDescriptor<WorkoutEntry>(
            predicate: #Predicate { $0.exercise?.name == exerciseName },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        let entries = (try? context.fetch(descriptor)) ?? []
        let currentIDs = Set(currentEntries.map(\.persistentModelID))
        let activeID = activeWorkout?.persistentModelID
        return entries.first { entry in
            !currentIDs.contains(entry.persistentModelID) &&
            (activeID == nil || entry.workout?.persistentModelID != activeID)
        }
    }

    @discardableResult
    static func appendSet(
        weight: Double,
        reps: Int,
        to entry: WorkoutEntry,
        in context: ModelContext
    ) -> WorkoutSet {
        let nextNumber = (entry.sets.map(\.setNumber).max() ?? 0) + 1
        let newSet = WorkoutSet(setNumber: nextNumber, weight: weight, reps: reps, workoutEntry: entry)
        context.insert(newSet)
        entry.sets.append(newSet)
        return newSet
    }
}
