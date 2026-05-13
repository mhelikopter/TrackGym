import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, arms, legs, core

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Brust"
        case .back: "Rücken"
        case .shoulders: "Schultern"
        case .arms: "Arme"
        case .legs: "Beine"
        case .core: "Core"
        }
    }

    var icon: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rowing"
        case .shoulders: "figure.arms.open"
        case .arms: "dumbbell.fill"
        case .legs: "figure.walk"
        case .core: "figure.core.training"
        }
    }
}
