# Training Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Übungs-Notizen, Volumen-pro-Muskelgruppe-Statistik, Pausen-Timer mit Watch-Haptik und Watch-Workout-Session mit Herzfrequenz — alles frei, für die persönliche Nutzung.

**Architecture:** Vier unabhängige Inkremente in Risiko-Reihenfolge. Statistik-Logik in einem testbaren Helper (`TrainingStatistics`), Timer-Zustand lebt am Phone und wird als `restEndsAt`-Stempel über das bestehende `activeExercise`-Payload gespiegelt (Haptik feuert lokal auf der Watch), HealthKit-Session in einem eigenen `WorkoutSessionController` auf der Watch mit sauberer Degradation bei fehlender Berechtigung.

**Tech Stack:** SwiftUI, SwiftData, Charts, WatchConnectivity, HealthKit (HKWorkoutSession + HKLiveWorkoutBuilder), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-25-training-features-design.md`

**Build-/Test-Kommandos (gelten für alle Tasks):**

```bash
# iOS-Tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project TrackGym.xcodeproj -scheme TrackGym \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -configuration Debug -only-testing:TrackGymTests

# Watch-Tests (UDID via: xcrun simctl list devices available | grep "Apple Watch")
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project TrackGym.xcodeproj -scheme 'TrackGym Watch App Watch App' \
  -destination 'id=<WATCH_SIM_UDID>' \
  -configuration Debug -only-testing:'TrackGym Watch App Watch AppTests'
```

Neue Swift-Dateien in den bestehenden Ordnern werden durch die Xcode-16-Ordnersynchronisation automatisch Teil des Targets — kein pbxproj-Edit nötig (Ausnahme: HealthKit-Capability in Task 4).

---

### Task 1: Übungs-Notizen

**Files:**
- Modify: `TrackGym/Models/Exercise.swift` (neues Feld)
- Modify: `TrackGym/Data/DataExporter.swift` (Backup-Roundtrip)
- Modify: `TrackGym/Views/AddExerciseView.swift` (Eingabe beim Anlegen)
- Modify: `TrackGym/Views/ActiveWorkoutView.swift` (Anzeige/Bearbeitung im Training)
- Test: `TrackGymTests/TrackGymTests.swift`

- [ ] **Step 1: Failing Test — Notiz übersteht Export/Import**

In `TrackGymTests.swift` vor `// MARK: - Helpers` einfügen:

```swift
    // MARK: - Übungs-Notizen

    func test_export_then_import_preservesExerciseNotes() throws {
        let exercise = Exercise(name: "Bench", muscleGroup: .chest, equipmentType: .freeWeight, isCustom: true)
        exercise.notes = "Sitz auf Position 4, enger Griff"
        context.insert(exercise)
        try context.save()

        let exported = try DataExporter.exportData(context: context)
        try DataExporter.importData(from: exported, context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.first?.notes, "Sitz auf Position 4, enger Griff")
    }

    func test_import_normalizesEmptyNotesToNil() throws {
        let payload = ExportData(
            exercises: [
                ExportExercise(id: nil, name: "Bench", muscleGroup: MuscleGroup.chest.rawValue, equipmentType: EquipmentType.freeWeight.rawValue, isCustom: true, imageURL: nil, notes: "   "),
            ],
            workoutPlans: [],
            workouts: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        try DataExporter.importData(from: data, context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertNil(exercises.first?.notes)
    }
```

- [ ] **Step 2: Test laufen lassen — erwarteter Fehler**

iOS-Test-Kommando (oben). Erwartet: Compile-Fehler (`Exercise` hat kein `notes`, `ExportExercise` keinen `notes`-Parameter).

- [ ] **Step 3: Model-Feld ergänzen**

`Exercise.swift`, nach `var imageURL: String?`:

```swift
    /// Freitext des Nutzers (Geräte-Einstellung, Grifftechnik). Leerstring
    /// wird an den Schreibstellen zu nil normalisiert.
    var notes: String?
```

- [ ] **Step 4: Backup-Roundtrip**

`DataExporter.swift` — `ExportExercise` erweitern (nach `imageURL`):

```swift
    var notes: String?
```

Im Export-Mapping (`exportExercises`) ergänzen:

```swift
                imageURL: exercise.imageURL,
                notes: exercise.notes
```

Im Import (nach `exercise.imageURL = nil`):

```swift
                exercise.notes = ex.notes.flatMap {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
```

- [ ] **Step 5: Test laufen lassen — grün**

- [ ] **Step 6: Eingabe in AddExerciseView**

Neuer `@State private var notes = ""` und in der Form-Section unter dem Gerätetyp-Picker:

```swift
                    TextField("Notiz (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
```

In `saveExercise()` vor `modelContext.insert(exercise)`:

```swift
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
```

- [ ] **Step 7: Anzeige/Bearbeitung im aktiven Training**

In `ActiveWorkoutView.swift`, `ActiveEntrySection`: direkt nach dem `Section {`-Beginn (vor der Previous-Reference) einfügen:

```swift
            if let exercise = entry.exercise {
                ExerciseNoteRow(exercise: exercise)
            }
```

Am Dateiende neue private View:

```swift
// MARK: - Exercise Note

private struct ExerciseNoteRow: View {
    @Bindable var exercise: Exercise

    private var noteBinding: Binding<String> {
        Binding(
            get: { exercise.notes ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                exercise.notes = trimmed.isEmpty ? nil : $0
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Notiz", text: noteBinding, axis: .vertical)
                .font(.caption)
                .lineLimit(1...3)
        }
    }
}
```

- [ ] **Step 8: iOS-Tests + beide Builds grün, Commit**

```bash
git add TrackGym/Models/Exercise.swift TrackGym/Data/DataExporter.swift TrackGym/Views/AddExerciseView.swift TrackGym/Views/ActiveWorkoutView.swift TrackGymTests/TrackGymTests.swift
git commit -m "feat: exercise notes, editable during workout, backed up"
```

---

### Task 2: Volumen pro Muskelgruppe

**Files:**
- Create: `TrackGym/Data/TrainingStatistics.swift`
- Create: `TrackGymTests/TrainingStatisticsTests.swift`
- Modify: `TrackGym/Views/ProgressView.swift` (neuer Abschnitt in `OverallProgressView`)

- [ ] **Step 1: Failing Tests**

`TrackGymTests/TrainingStatisticsTests.swift` (neue Datei):

```swift
import XCTest
import SwiftData
@testable import TrackGym

@MainActor
final class TrainingStatisticsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema([Exercise.self, Workout.self, WorkoutEntry.self, WorkoutSet.self, WorkoutPlan.self, SeedVersion.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func test_volumeByMuscleGroup_aggregatesPerGroup() throws {
        let chest = makeCompletedEntry(muscleGroup: .chest, sets: [(100, 10)], daysAgo: 1)
        _ = chest
        _ = makeCompletedEntry(muscleGroup: .chest, sets: [(50, 10)], daysAgo: 2)
        _ = makeCompletedEntry(muscleGroup: .legs, sets: [(200, 5)], daysAgo: 1)

        let result = TrainingStatistics.volumeByMuscleGroup(entries: allEntries(), since: nil)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.group, .chest)
        XCTAssertEqual(result.first?.volumeKg ?? 0, 1500, accuracy: 0.001)
        XCTAssertEqual(result.last?.volumeKg ?? 0, 1000, accuracy: 0.001)
    }

    func test_volumeByMuscleGroup_respectsSinceDate() throws {
        _ = makeCompletedEntry(muscleGroup: .chest, sets: [(100, 10)], daysAgo: 1)
        _ = makeCompletedEntry(muscleGroup: .chest, sets: [(100, 10)], daysAgo: 20)

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let result = TrainingStatistics.volumeByMuscleGroup(entries: allEntries(), since: weekAgo)

        XCTAssertEqual(result.first?.volumeKg ?? 0, 1000, accuracy: 0.001)
    }

    func test_volumeByMuscleGroup_excludesPendingAndOrphanedEntries() throws {
        // Pending: Eintrag ohne Workout
        let exercise = Exercise(name: "Bench", muscleGroup: .chest, equipmentType: .freeWeight)
        context.insert(exercise)
        let pending = WorkoutEntry(date: Date(), exercise: exercise)
        context.insert(pending)
        let set = WorkoutSet(setNumber: 1, weight: 100, reps: 10, workoutEntry: pending)
        context.insert(set)
        pending.sets.append(set)
        // Verwaist: Eintrag ohne Übung
        let workout = Workout(name: "W", date: Date(), duration: 60)
        context.insert(workout)
        let orphan = WorkoutEntry(date: Date(), exercise: nil)
        orphan.workout = workout
        context.insert(orphan)

        let result = TrainingStatistics.volumeByMuscleGroup(entries: allEntries(), since: nil)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Helpers

    private func allEntries() -> [WorkoutEntry] {
        (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
    }

    @discardableResult
    private func makeCompletedEntry(muscleGroup: MuscleGroup, sets: [(weight: Double, reps: Int)], daysAgo: Int) -> WorkoutEntry {
        let exercise = Exercise(name: "Ex-\(UUID().uuidString.prefix(6))", muscleGroup: muscleGroup, equipmentType: .freeWeight)
        context.insert(exercise)
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let workout = Workout(name: "W", date: date, duration: 3600)
        context.insert(workout)
        let entry = WorkoutEntry(date: date, exercise: exercise)
        entry.workout = workout
        context.insert(entry)
        for (index, pair) in sets.enumerated() {
            let set = WorkoutSet(setNumber: index + 1, weight: pair.weight, reps: pair.reps, workoutEntry: entry)
            context.insert(set)
            entry.sets.append(set)
        }
        return entry
    }
}
```

- [ ] **Step 2: Laufen lassen — Compile-Fehler erwartet** (`TrainingStatistics` existiert nicht)

- [ ] **Step 3: Implementierung**

`TrackGym/Data/TrainingStatistics.swift` (neue Datei):

```swift
import Foundation

enum TrainingStatistics {
    /// Gesamtvolumen (kg) je Muskelgruppe über abgeschlossene Einträge,
    /// absteigend nach Volumen sortiert. `since` nil = gesamter Zeitraum.
    /// Einträge ohne Workout (noch nicht gespeichert) oder ohne Übung
    /// (Übung gelöscht) fließen nicht ein.
    static func volumeByMuscleGroup(entries: [WorkoutEntry], since: Date?) -> [(group: MuscleGroup, volumeKg: Double)] {
        var totals: [MuscleGroup: Double] = [:]
        for entry in entries {
            guard entry.workout != nil, let exercise = entry.exercise else { continue }
            if let since, entry.date < since { continue }
            let volume = entry.totalVolume
            guard volume > 0 else { continue }
            totals[exercise.muscleGroup, default: 0] += volume
        }
        return totals
            .map { (group: $0.key, volumeKg: $0.value) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }
}
```

- [ ] **Step 4: Tests grün, Commit**

```bash
git add TrackGym/Data/TrainingStatistics.swift TrackGymTests/TrainingStatisticsTests.swift
git commit -m "feat: muscle-group volume aggregation with tests"
```

- [ ] **Step 5: Chart-Abschnitt im Fortschritt-Tab**

`ProgressView.swift`, in `OverallProgressView`: nach dem `private var averageVolume`-Property ergänzen:

```swift
    @State private var volumePeriod: VolumePeriod = .week

    private var muscleVolumeData: [(group: MuscleGroup, volume: Double)] {
        let entries = exercises.flatMap(\.workoutEntries)
        return TrainingStatistics.volumeByMuscleGroup(entries: entries, since: volumePeriod.since)
            .map { (group: $0.group, volume: selectedUnit.displayValue(fromKilograms: $0.volumeKg)) }
    }
```

Am Dateiende:

```swift
private enum VolumePeriod: String, CaseIterable, Identifiable {
    case week = "Woche"
    case month = "Monat"
    case all = "Gesamt"

    var id: String { rawValue }

    /// Rollierendes Fenster (7/30 Tage), kein Kalenderbezug.
    var since: Date? {
        switch self {
        case .week: Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .month: Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .all: nil
        }
    }
}
```

Im `body` von `OverallProgressView`, nach der Section „Zusammenfassung" (innerhalb des `if !volumeByWorkout.isEmpty`-Blocks):

```swift
                Section("Volumen pro Muskelgruppe") {
                    Picker("Zeitraum", selection: $volumePeriod) {
                        ForEach(VolumePeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    if muscleVolumeData.isEmpty {
                        Text("Keine Trainings im gewählten Zeitraum.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(muscleVolumeData, id: \.group) { item in
                                BarMark(
                                    x: .value("Volumen (\(selectedUnit.rawValue))", item.volume),
                                    y: .value("Muskelgruppe", item.group.displayName)
                                )
                                .foregroundStyle(.blue)
                            }
                        }
                        .chartXAxisLabel(selectedUnit.rawValue)
                        .frame(height: CGFloat(muscleVolumeData.count) * 36 + 24)
                        .padding(.vertical, 4)
                    }
                }
```

- [ ] **Step 6: iOS-Build + Tests grün, Commit**

```bash
git add TrackGym/Views/ProgressView.swift
git commit -m "feat: muscle-group volume chart in progress tab"
```

---

### Task 3: Pausen-Timer

**Files:**
- Modify: `TrackGym/Views/SettingsView.swift` (Einstellung)
- Modify: `TrackGym/Views/ActiveWorkoutView.swift` (Timer-Zustand, Countdown-UI, Trigger)
- Modify: `TrackGym/Data/PhoneConnectivityManager.swift` (`restEndsAt` im Payload)
- Modify: `TrackGym Watch App Watch App/WatchConnectivityManager.swift` (Parsing, Haptik)
- Modify: `TrackGym Watch App Watch App/WorkoutSessionView.swift` (Countdown)
- Test: `TrackGym Watch App Watch AppTests/TrackGym_Watch_App_Watch_AppTests.swift`

- [ ] **Step 1: Failing Watch-Tests — restEndsAt-Parsing**

In der Watch-Testdatei ergänzen:

```swift
    // MARK: - Pausen-Timer

    @MainActor
    func testApplyState_parsesFutureRestEndsAt() {
        let manager = WatchConnectivityManager()
        let end = Date().addingTimeInterval(90).timeIntervalSince1970

        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [], "restEndsAt": end
        ])

        XCTAssertEqual(manager.restEndDate?.timeIntervalSince1970 ?? 0, end, accuracy: 0.001)
    }

    @MainActor
    func testApplyState_ignoresExpiredRestEndsAt() {
        let manager = WatchConnectivityManager()
        let past = Date().addingTimeInterval(-10).timeIntervalSince1970

        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [], "restEndsAt": past
        ])

        XCTAssertNil(manager.restEndDate)
    }

    @MainActor
    func testApplyState_clearsRestTimer_whenPayloadOmitsIt() {
        let manager = WatchConnectivityManager()
        let end = Date().addingTimeInterval(90).timeIntervalSince1970
        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [], "restEndsAt": end
        ])

        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": []
        ])

        XCTAssertNil(manager.restEndDate)
    }

    @MainActor
    func testApplyState_workoutEnded_clearsRestTimer() {
        let manager = WatchConnectivityManager()
        let end = Date().addingTimeInterval(90).timeIntervalSince1970
        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [], "restEndsAt": end
        ])

        manager.applyStateSynchronously(["type": "workoutEnded"])

        XCTAssertNil(manager.restEndDate)
    }
```

- [ ] **Step 2: Laufen lassen — Compile-Fehler erwartet** (`restEndDate` existiert nicht)

- [ ] **Step 3: Watch-Manager erweitern**

`WatchConnectivityManager.swift`: `import WatchKit` ergänzen. Neue Properties nach `isReachable`:

```swift
    /// Endzeitpunkt der laufenden Satzpause; nil wenn kein Timer aktiv.
    var restEndDate: Date?

    @ObservationIgnored
    private var restHapticTask: Task<Void, Never>?
```

In `applyStateSynchronously`, Case `"activeExercise"`, nach `self.workoutActive = true`:

```swift
            if let ends = message["restEndsAt"] as? Double,
               ends > Date().timeIntervalSince1970 {
                self.restEndDate = Date(timeIntervalSince1970: ends)
            } else {
                self.restEndDate = nil
            }
            scheduleRestHaptic()
```

Case `"workoutEnded"`, nach `self.sets = []`:

```swift
            self.restEndDate = nil
            restHapticTask?.cancel()
```

In `clearLocalState()`, nach `sets = []`:

```swift
        restEndDate = nil
        restHapticTask?.cancel()
```

Neue Methode (unter `clearLocalState`):

```swift
    /// Terminiert die Handgelenk-Haptik lokal auf der Watch — kein Timing
    /// über die Funkverbindung. Jedes neue Payload ersetzt den Termin.
    @MainActor
    private func scheduleRestHaptic() {
        restHapticTask?.cancel()
        guard let end = restEndDate else { return }
        let interval = end.timeIntervalSinceNow
        guard interval > 0 else { return }
        restHapticTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, self.workoutActive else { return }
            WKInterfaceDevice.current().play(.notification)
        }
    }
```

- [ ] **Step 4: Watch-Tests grün**

- [ ] **Step 5: Countdown in WorkoutSessionView**

Nach dem Sets-Block (vor dem zweiten `Divider()`):

```swift
                if let restEnd = connectivity.restEndDate {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let remaining = Int(restEnd.timeIntervalSince(timeline.date).rounded(.up))
                        if remaining > 0 {
                            HStack {
                                Image(systemName: "hourglass")
                                    .foregroundStyle(.orange)
                                Text("Pause")
                                    .font(.caption)
                                Spacer()
                                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
```

- [ ] **Step 6: Phone-Payload — `restEndsAt` senden**

`PhoneConnectivityManager.swift`, Signatur erweitern:

```swift
    func sendActiveExercise(name: String, muscleGroup: String, unit: String, sets: [WatchSetPayload], restEndsAt: Double? = nil) {
```

Payload-Dictionary vor `pushState` ergänzen:

```swift
        var payload: [String: Any] = [
            "type": "activeExercise",
            "exerciseName": name,
            "muscleGroup": muscleGroup,
            "unit": unit,
            "sets": setsDicts
        ]
        if let restEndsAt {
            payload["restEndsAt"] = restEndsAt
        }
        pushState(payload)
```

- [ ] **Step 7: Einstellung in SettingsView**

Neue Section vor „Backup":

```swift
            Section("Training") {
                Stepper(value: $restTimerDuration, in: 0...300, step: 15) {
                    HStack {
                        Label("Pausen-Timer", systemImage: "timer")
                        Spacer()
                        Text(restTimerDuration == 0 ? "Aus" : "\(restTimerDuration) s")
                            .foregroundStyle(.secondary)
                    }
                }
            }
```

Property dazu:

```swift
    @AppStorage("restTimerDuration") private var restTimerDuration: Int = 90
```

- [ ] **Step 8: Timer-Logik in ActiveWorkoutView**

Neue Properties:

```swift
    @AppStorage("restTimerDuration") private var restTimerDuration: Int = 90
    @State private var restEndDate: Date?
```

Neue Methoden (bei den anderen private funcs):

```swift
    private func startRestTimer() {
        guard restTimerDuration > 0 else { return }
        restEndDate = Date().addingTimeInterval(Double(restTimerDuration))
    }

    private func skipRestTimer() {
        restEndDate = nil
        sendCurrentExerciseToWatch()
    }

    private func activeRestEndsAt() -> Double? {
        guard let restEndDate, restEndDate > Date() else { return nil }
        return restEndDate.timeIntervalSince1970
    }
```

`sendCurrentExerciseToWatch()` — Aufruf erweitern:

```swift
        PhoneConnectivityManager.shared.sendActiveExercise(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup.rawValue,
            unit: selectedUnit.rawValue,
            sets: payload,
            restEndsAt: activeRestEndsAt()
        )
```

`addSetFromWatch` — vor `sendCurrentExerciseToWatch()`:

```swift
        startRestTimer()
```

`ActiveEntrySection` bekommt einen zusätzlichen Callback (Satz geloggt ≠ Satz gelöscht):

```swift
    /// Feuert, wenn ein neuer Satz angelegt wurde (startet die Pause).
    let onSetLogged: () -> Void
```

In `addSet()` die Zeile `onSetsChanged()` ersetzen durch `onSetLogged()`. `deleteSets` behält `onSetsChanged()`. Aufrufstelle im `ForEach`:

```swift
                            ActiveEntrySection(
                                entry: entry,
                                previousEntry: cachedPreviousEntry(for: entry.exercise),
                                onSave: { saveEntry(entry) },
                                onSetsChanged: { sendCurrentExerciseToWatch() },
                                onSetLogged: {
                                    startRestTimer()
                                    sendCurrentExerciseToWatch()
                                }
                            )
```

Countdown-UI in der Timer-Section, innerhalb der bestehenden `TimelineView` nach dem Trainingszeit-HStack:

```swift
                                if let restEnd = restEndDate, restEnd > context.date {
                                    HStack {
                                        Label("Pause", systemImage: "hourglass")
                                        Spacer()
                                        Text(restTimeString(until: restEnd, now: context.date))
                                            .font(.headline.monospacedDigit())
                                            .foregroundStyle(.orange)
                                        Button {
                                            skipRestTimer()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
```

Hinweis: Die bestehende `TimelineView` umschließt aktuell nur den Trainingszeit-HStack — beide Zeilen in ein `VStack`/`Group` innerhalb der `TimelineView` legen. Hilfsfunktion:

```swift
    private func restTimeString(until end: Date, now: Date) -> String {
        let remaining = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
```

- [ ] **Step 9: Beide Builds + beide Testsuiten grün, Commit**

```bash
git add TrackGym/Views/SettingsView.swift TrackGym/Views/ActiveWorkoutView.swift TrackGym/Data/PhoneConnectivityManager.swift "TrackGym Watch App Watch App/WatchConnectivityManager.swift" "TrackGym Watch App Watch App/WorkoutSessionView.swift" "TrackGym Watch App Watch AppTests/TrackGym_Watch_App_Watch_AppTests.swift"
git commit -m "feat: rest timer with watch haptic"
```

---

### Task 4: Watch-Workout-Session mit Herzfrequenz

**Files:**
- Create: `TrackGym Watch App Watch App/TrackGymWatch.entitlements`
- Modify: `TrackGym.xcodeproj/project.pbxproj` (Entitlements-Pfad + Usage-Strings, Watch-Target, Debug+Release)
- Create: `TrackGym Watch App Watch App/WorkoutSessionController.swift`
- Modify: `TrackGym Watch App Watch App/ContentView.swift` (Session-Lifecycle)
- Modify: `TrackGym Watch App Watch App/WorkoutSessionView.swift` (Puls/Kalorien-Anzeige)

- [ ] **Step 1: Entitlements + Capability**

`TrackGym Watch App Watch App/TrackGymWatch.entitlements` (neue Datei):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
</dict>
</plist>
```

In `project.pbxproj`, in BEIDEN buildSettings-Blöcken des Watch-App-Targets (erkennbar an `WATCHOS_DEPLOYMENT_TARGET` + `PRODUCT_NAME`-Kontext des App-Targets, nicht der Test-Targets) ergänzen:

```
				CODE_SIGN_ENTITLEMENTS = "TrackGym Watch App Watch App/TrackGymWatch.entitlements";
				INFOPLIST_KEY_NSHealthShareUsageDescription = "TrackGym liest Herzfrequenz und Kalorien, um sie während des Trainings anzuzeigen.";
				INFOPLIST_KEY_NSHealthUpdateUsageDescription = "TrackGym speichert dein Krafttraining in Apple Health.";
```

Danach: `xcodebuild -list` (Projekt lesbar?) und Watch-Build für den Simulator. **Signing-Hinweis:** Simulator-Builds validieren das Entitlement nicht gegen den Account — der Free-Account-Check passiert beim nächsten Geräte-Deploy; HealthKit gehört zu den für Personal Teams erlaubten Capabilities.

- [ ] **Step 2: WorkoutSessionController**

`TrackGym Watch App Watch App/WorkoutSessionController.swift` (neue Datei):

```swift
import Foundation
import HealthKit
import Observation
import OSLog

/// Besitzt die HealthKit-Workout-Session der Watch. Verweigerte Berechtigung
/// oder Session-Fehler blockieren nichts: das Workout-Tracking über
/// WatchConnectivity läuft unverändert, es fehlen nur Puls/Kalorien/Ringe.
@Observable
final class WorkoutSessionController: NSObject {
    static let shared = WorkoutSessionController()
    private static let log = Logger(subsystem: "de.ehling.TrackGym.watchkitapp", category: "WorkoutSession")

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var heartRate: Double?
    var activeEnergy: Double?
    var isRunning = false

    @MainActor
    func startIfNeeded() {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] granted, error in
            if let error {
                Self.log.error("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
            }
            guard granted else { return }
            Task { @MainActor in
                self?.beginSession()
            }
        }
    }

    @MainActor
    private func beginSession() {
        guard !isRunning else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, error in
                if let error {
                    Self.log.error("beginCollection failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            isRunning = true
        } catch {
            Self.log.error("Workout session start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Beendet die Session und speichert das Workout in HealthKit
    /// (zählt für die Aktivitätsringe).
    @MainActor
    func end() {
        guard isRunning, let session, let builder else { return }
        isRunning = false
        session.end()
        builder.endCollection(withEnd: Date()) { _, error in
            if let error {
                Self.log.error("endCollection failed: \(error.localizedDescription, privacy: .public)")
            }
            builder.finishWorkout { _, error in
                if let error {
                    Self.log.error("finishWorkout failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        self.session = nil
        self.builder = nil
        heartRate = nil
        activeEnergy = nil
    }
}

extension WorkoutSessionController: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Self.log.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.end()
        }
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: quantityType) else { continue }
            let heartRateType = HKQuantityType(.heartRate)
            let energyType = HKQuantityType(.activeEnergyBurned)
            Task { @MainActor in
                switch quantityType {
                case heartRateType:
                    self.heartRate = stats.mostRecentQuantity()?
                        .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                case energyType:
                    self.activeEnergy = stats.sumQuantity()?
                        .doubleValue(for: .kilocalorie())
                default:
                    break
                }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
```

- [ ] **Step 3: Lifecycle-Anbindung in ContentView (Watch)**

```swift
import SwiftUI

struct ContentView: View {
    @State private var connectivity = WatchConnectivityManager.shared
    @State private var sessionController = WorkoutSessionController.shared

    var body: some View {
        Group {
            if connectivity.workoutActive {
                WorkoutSessionView()
                    .environment(connectivity)
                    .environment(sessionController)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.largeTitle)
                    Text("Starte ein Workout auf dem iPhone")
                        .multilineTextAlignment(.center)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: connectivity.workoutActive) { _, isActive in
            if isActive {
                sessionController.startIfNeeded()
            } else {
                sessionController.end()
            }
        }
    }
}
```

- [ ] **Step 4: Puls/Kalorien im Header der WorkoutSessionView**

Property ergänzen:

```swift
    @Environment(WorkoutSessionController.self) private var sessionController
```

Nach dem Exercise-Header-HStack (vor `Text(muscleDisplayName)`):

```swift
                if sessionController.heartRate != nil || sessionController.activeEnergy != nil {
                    HStack(spacing: 12) {
                        if let hr = sessionController.heartRate {
                            Label("\(Int(hr))", systemImage: "heart.fill")
                                .foregroundStyle(.red)
                        }
                        if let kcal = sessionController.activeEnergy {
                            Label("\(Int(kcal)) kcal", systemImage: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }
```

- [ ] **Step 5: Beide Builds + beide Testsuiten grün** (Watch-Tests laufen im Test-Runner ohne HealthKit-Auth — der Controller wird dort nicht angefasst)

- [ ] **Step 6: Manueller Simulator-Test**

Gepaartes Simulator-Paar starten (iPhone + Watch), Workout am Phone starten, prüfen: Watch fragt HealthKit-Berechtigung an, danach erscheint simulierter Puls. Workout beenden → Session endet.

- [ ] **Step 7: Commit**

```bash
git add "TrackGym Watch App Watch App/TrackGymWatch.entitlements" TrackGym.xcodeproj/project.pbxproj "TrackGym Watch App Watch App/WorkoutSessionController.swift" "TrackGym Watch App Watch App/ContentView.swift" "TrackGym Watch App Watch App/WorkoutSessionView.swift"
git commit -m "feat: HealthKit workout session with live heart rate on watch"
```

---

### Abschluss

- [ ] Beide Schemes bauen, beide Testsuiten grün
- [ ] Push + CI beobachten
- [ ] Frischen Build in den Simulator installieren
