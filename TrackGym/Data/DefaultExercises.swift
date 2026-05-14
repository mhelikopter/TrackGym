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

    static let currentSeedVersion = 1

    /// Seeds the default exercises into the store, idempotently.
    ///
    /// The seed-version flag lives in SwiftData (see `SeedVersion`) so it
    /// travels with the store and is rolled back automatically when a
    /// `modelContext.rollback()` undoes a failed seed (MHE-24).
    ///
    /// On a fetch failure we log loudly and bail out instead of silently
    /// re-inserting every default and creating duplicates against a broken
    /// store (MHE-26).
    static func seedDefaultExercises(context: ModelContext) {
        let storedVersion: SeedVersion?
        do {
            storedVersion = try context.fetch(FetchDescriptor<SeedVersion>()).first
        } catch {
            assertionFailure("Failed to read SeedVersion, aborting seed to avoid duplicates: \(error)")
            return
        }

        if let storedVersion, storedVersion.version >= currentSeedVersion {
            return
        }

        let existingExercises: [Exercise]
        do {
            existingExercises = try context.fetch(FetchDescriptor<Exercise>())
        } catch {
            assertionFailure("Failed to fetch existing Exercises, aborting seed to avoid duplicates: \(error)")
            return
        }
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

        // Upsert the seed-version marker. Both the inserted Exercises above
        // and this row become part of the same unsaved-changes set, so a
        // single rollback() restores both to their previous state.
        if let storedVersion {
            storedVersion.version = currentSeedVersion
        } else {
            context.insert(SeedVersion(version: currentSeedVersion))
        }
    }

    /// Clears the SwiftData-backed seed-version flag so the next call to
    /// `seedDefaultExercises` will re-seed. Used by destructive flows like
    /// "Alle Daten löschen" and by tests.
    static func resetSeedFlag(context: ModelContext) {
        do {
            let stored = try context.fetch(FetchDescriptor<SeedVersion>())
            for row in stored { context.delete(row) }
        } catch {
            assertionFailure("Failed to reset SeedVersion: \(error)")
        }
    }
}
