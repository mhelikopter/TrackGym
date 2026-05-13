import Foundation
import SwiftData

struct DefaultExercises {
    static let exercises: [(name: String, muscleGroup: MuscleGroup, equipmentType: EquipmentType)] = [
        // MARK: - Brust
        ("Bankdrücken", .chest, .freeWeight),
        ("Bankdrücken Kurzhantel", .chest, .freeWeight),
        ("Schrägbankdrücken", .chest, .freeWeight),
        ("Schrägbankdrücken Kurzhantel", .chest, .freeWeight),
        ("Negativ Bankdrücken", .chest, .freeWeight),
        ("Fliegende Kurzhantel", .chest, .freeWeight),
        ("Brustpresse", .chest, .machine),
        ("Butterfly", .chest, .machine),
        ("Kabelzug Crossover", .chest, .cable),
        ("Kabelzug Fliegende", .chest, .cable),
        ("Liegestütze", .chest, .bodyweight),

        // MARK: - Rücken
        ("Latzug breit", .back, .cable),
        ("Latzug eng", .back, .cable),
        ("Rudern Langhantel", .back, .freeWeight),
        ("Rudern Kurzhantel", .back, .freeWeight),
        ("T-Bar Rudern", .back, .freeWeight),
        ("Rudermaschine", .back, .machine),
        ("Klimmzüge", .back, .bodyweight),
        ("Klimmzüge eng", .back, .bodyweight),
        ("Kabelrudern", .back, .cable),
        ("Kreuzheben", .back, .freeWeight),
        ("Hyperextensions", .back, .bodyweight),
        ("Latzug Maschine", .back, .machine),
        ("Rückenstrecker", .back, .machine),
        ("Einarmiges Kabelrudern", .back, .cable),

        // MARK: - Schultern
        ("Schulterdrücken Langhantel", .shoulders, .freeWeight),
        ("Schulterdrücken Kurzhantel", .shoulders, .freeWeight),
        ("Seitheben Kurzhantel", .shoulders, .freeWeight),
        ("Frontheben", .shoulders, .freeWeight),
        ("Schulterpresse Maschine", .shoulders, .machine),
        ("Face Pulls", .shoulders, .cable),
        ("Reverse Butterfly", .shoulders, .machine),
        ("Seithebemaschine", .shoulders, .machine),
        ("Aufrechtes Rudern", .shoulders, .freeWeight),
        ("Seitheben Kabelzug", .shoulders, .cable),
        ("Arnold Press", .shoulders, .freeWeight),
        ("Shrugs", .shoulders, .freeWeight),

        // MARK: - Arme
        ("Bizeps-Curls Langhantel", .arms, .freeWeight),
        ("Bizeps-Curls Kurzhantel", .arms, .freeWeight),
        ("SZ-Curls", .arms, .freeWeight),
        ("Hammercurls", .arms, .freeWeight),
        ("Konzentrationscurls", .arms, .freeWeight),
        ("Cable Curls", .arms, .cable),
        ("Bizepsmaschine", .arms, .machine),
        ("Bizepsmaschine einzeln", .arms, .machine),
        ("Trizepsdrücken Kabel", .arms, .cable),
        ("French Press", .arms, .freeWeight),
        ("Trizeps Kickbacks", .arms, .freeWeight),
        ("Overhead Trizepsdrücken", .arms, .freeWeight),
        ("Trizepsmaschine", .arms, .machine),
        ("Dips", .arms, .bodyweight),
        ("Unterarm-Curls", .arms, .freeWeight),

        // MARK: - Beine
        ("Kniebeugen", .legs, .freeWeight),
        ("Frontkniebeugen", .legs, .freeWeight),
        ("Beinpresse", .legs, .machine),
        ("Beinstrecker", .legs, .machine),
        ("Beinbeuger liegend", .legs, .machine),
        ("Beinbeuger sitzend", .legs, .machine),
        ("Wadenheben stehend", .legs, .machine),
        ("Wadenheben sitzend", .legs, .machine),
        ("Ausfallschritte", .legs, .freeWeight),
        ("Bulgarische Kniebeugen", .legs, .freeWeight),
        ("Rumänisches Kreuzheben", .legs, .freeWeight),
        ("Hackenschmidt", .legs, .machine),
        ("Goblet Squat", .legs, .freeWeight),
        ("Hip Thrust", .legs, .freeWeight),
        ("Adduktoren", .legs, .machine),
        ("Abduktoren", .legs, .machine),

        // MARK: - Core
        ("Crunches", .core, .bodyweight),
        ("Plank", .core, .bodyweight),
        ("Russian Twist", .core, .freeWeight),
        ("Beinheben", .core, .bodyweight),
        ("Beinheben hängend", .core, .bodyweight),
        ("Kabelzug Crunches", .core, .cable),
        ("Seitliche Crunches", .core, .bodyweight),
        ("Bauchpresse", .core, .machine),
        ("Ab Roller", .core, .bodyweight),
    ]

    private static let seedVersionKey = "defaultExercisesSeedVersion"
    private static let currentSeedVersion = 1

    static func seedDefaultExercises(context: ModelContext) {
        let stored = UserDefaults.standard.integer(forKey: seedVersionKey)
        guard stored < currentSeedVersion else { return }

        let descriptor = FetchDescriptor<Exercise>()
        let existingExercises = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existingExercises.map(\.name))

        for entry in exercises {
            guard !existingNames.contains(entry.name) else { continue }
            let exercise = Exercise(
                name: entry.name,
                muscleGroup: entry.muscleGroup,
                equipmentType: entry.equipmentType,
                isCustom: false
            )
            context.insert(exercise)
        }

        UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
    }

    static func resetSeedFlag() {
        UserDefaults.standard.removeObject(forKey: seedVersionKey)
    }
}
