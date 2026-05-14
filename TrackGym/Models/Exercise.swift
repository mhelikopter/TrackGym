import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var muscleGroupRaw: String
    var equipmentTypeRaw: String
    var isCustom: Bool
    var imageURL: String?

    @Relationship(deleteRule: .nullify, inverse: \WorkoutEntry.exercise)
    var workoutEntries: [WorkoutEntry] = []

    @Relationship(inverse: \WorkoutPlan.exercises)
    var workoutPlans: [WorkoutPlan] = []

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .unknown }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var equipmentType: EquipmentType {
        get { EquipmentType(rawValue: equipmentTypeRaw) ?? .unknown }
        set { equipmentTypeRaw = newValue.rawValue }
    }

    init(name: String, muscleGroup: MuscleGroup, equipmentType: EquipmentType, isCustom: Bool = false) {
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentTypeRaw = equipmentType.rawValue
        self.isCustom = isCustom
    }

    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
