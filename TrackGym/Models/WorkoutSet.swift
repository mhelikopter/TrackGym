import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var setNumber: Int
    var weight: Double
    var reps: Int
    var workoutEntry: WorkoutEntry?

    init(setNumber: Int, weight: Double, reps: Int, workoutEntry: WorkoutEntry? = nil) {
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.workoutEntry = workoutEntry
    }
}
