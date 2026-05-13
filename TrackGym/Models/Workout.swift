import Foundation
import SwiftData

@Model
final class Workout {
    var name: String
    var date: Date
    var duration: Int = 0  // in seconds

    @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.workout)
    var entries: [WorkoutEntry] = []

    /// The plan this workout was performed against. Used to link history by
    /// identity rather than by the plan's mutable `name` string.
    var plan: WorkoutPlan?

    init(name: String, date: Date, duration: Int = 0) {
        self.name = name
        self.date = date
        self.duration = duration
    }
}
