import Foundation
import SwiftData

@Model
final class WorkoutPlan {
    var name: String
    @Relationship(deleteRule: .nullify)
    var exercises: [Exercise] = []

    /// Inverse of `Workout.plan`. Without a declared inverse, deleting a plan
    /// leaves dangling `Workout.plan` references in the store (invalidated
    /// model instances that crash on attribute access). The nullify rule
    /// clears the back-reference on every linked workout instead.
    @Relationship(deleteRule: .nullify, inverse: \Workout.plan)
    var workouts: [Workout] = []

    init(name: String) {
        self.name = name
    }
}
