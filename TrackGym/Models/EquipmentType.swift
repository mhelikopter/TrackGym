import Foundation

enum EquipmentType: String, Codable, CaseIterable, Identifiable {
    case machine, freeWeight, bodyweight, cable
    case unknown

    var id: String { rawValue }

    static var selectableCases: [Self] { allCases.filter { $0 != .unknown } }

    var displayName: String {
        switch self {
        case .machine: "Maschine"
        case .freeWeight: "Freihantel"
        case .bodyweight: "Körpergewicht"
        case .cable: "Kabelzug"
        case .unknown: "Unbekannt"
        }
    }

    var icon: String {
        switch self {
        case .machine: "gearshape.fill"
        case .freeWeight: "dumbbell.fill"
        case .bodyweight: "figure.stand"
        case .cable: "cable.connector"
        case .unknown: "questionmark.circle"
        }
    }
}
