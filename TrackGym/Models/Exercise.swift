import Foundation
import SwiftData

@Model
final class Exercise {
    var stableID: UUID?
    var name: String
    var muscleGroupRaw: String
    var equipmentTypeRaw: String
    var isCustom: Bool
    var imageURL: String?
    /// Freitext des Nutzers (Geräte-Einstellung, Grifftechnik). Leerstring
    /// wird an den Schreibstellen zu nil normalisiert.
    var notes: String?

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

    init(name: String, muscleGroup: MuscleGroup, equipmentType: EquipmentType, isCustom: Bool = false, stableID: UUID = UUID()) {
        self.stableID = stableID
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentTypeRaw = equipmentType.rawValue
        self.isCustom = isCustom
    }

    @discardableResult
    func ensureStableID() -> UUID {
        if let stableID {
            return stableID
        }
        let stableID = UUID()
        self.stableID = stableID
        return stableID
    }

    static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func backfillStableIDs(context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        var changed = false
        for exercise in exercises where exercise.stableID == nil {
            exercise.stableID = UUID()
            changed = true
        }
        if changed {
            try context.save()
        }
    }
}
