import Foundation
import SwiftData

@Model
final class WorkoutPlan {
    var name: String
    @Relationship(deleteRule: .nullify, inverse: \Exercise.workoutPlans)
    var exercises: [Exercise] = []

    init(name: String) {
        self.name = name
    }
}
