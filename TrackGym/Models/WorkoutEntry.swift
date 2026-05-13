import Foundation
import SwiftData

@Model
final class WorkoutEntry {
    var date: Date
    var exercise: Exercise?
    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutEntry)
    var sets: [WorkoutSet] = []

    var sortedSets: [WorkoutSet] {
        sets.sorted { $0.setNumber < $1.setNumber }
    }

    var maxWeight: Double {
        sets.map(\.weight).max() ?? 0
    }

    var totalVolume: Double {
        sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    init(date: Date, exercise: Exercise) {
        self.date = date
        self.exercise = exercise
    }
}
