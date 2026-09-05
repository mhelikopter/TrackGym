import Foundation
import SwiftData

@Model
final class WorkoutPlan {
    var name: String
    @Relationship(deleteRule: .nullify)
    var exercises: [Exercise] = []

    /// SwiftData to-many relationships are unordered sets under the hood, so
    /// the order the user arranged in the plan editor has to live here.
    /// Holds `Exercise.stableID`s; exercises that are not listed (older
    /// stores) are appended alphabetically by `orderedExercises`.
    var exerciseOrderIDs: [UUID] = []

    /// Inverse of `Workout.plan`. Without a declared inverse, deleting a plan
    /// leaves dangling `Workout.plan` references in the store (invalidated
    /// model instances that crash on attribute access). The nullify rule
    /// clears the back-reference on every linked workout instead.
    @Relationship(deleteRule: .nullify, inverse: \Workout.plan)
    var workouts: [Workout] = []

    init(name: String) {
        self.name = name
    }

    /// Exercises in the order the user arranged them. This is what the
    /// active workout, the watch and the plan views must iterate — never
    /// `exercises` directly.
    var orderedExercises: [Exercise] {
        let position = Dictionary(
            exerciseOrderIDs.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return exercises.sorted { lhs, rhs in
            switch (lhs.stableID.flatMap { position[$0] }, rhs.stableID.flatMap { position[$0] }) {
            case let (l?, r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.name < rhs.name
            }
        }
    }

    /// Replaces the plan's exercises and records their order.
    func setExercises(_ ordered: [Exercise]) {
        exercises = ordered
        exerciseOrderIDs = ordered.map { $0.ensureStableID() }
    }
}
