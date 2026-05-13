import Foundation

enum EquipmentType: String, Codable, CaseIterable, Identifiable {
    case machine, freeWeight, bodyweight, cable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .machine: "Maschine"
        case .freeWeight: "Freihantel"
        case .bodyweight: "Körpergewicht"
        case .cable: "Kabelzug"
        }
    }

    var icon: String {
        switch self {
        case .machine: "gearshape.fill"
        case .freeWeight: "dumbbell.fill"
        case .bodyweight: "figure.stand"
        case .cable: "cable.connector"
        }
    }
}
