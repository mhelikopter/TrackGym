import Foundation
import SwiftData

@Model
final class Workout {
    var name: String
    var date: Date
    var duration: Int = 0  // in seconds

    @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.workout)
    var entries: [WorkoutEntry] = []

    init(name: String, date: Date, duration: Int = 0) {
        self.name = name
        self.date = date
        self.duration = duration
    }
}
