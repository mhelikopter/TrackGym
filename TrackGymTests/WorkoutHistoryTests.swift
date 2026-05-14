import XCTest
import SwiftData
@testable import TrackGym

@MainActor
final class WorkoutHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema([
            Exercise.self,
            Workout.self,
            WorkoutEntry.self,
            WorkoutSet.self,
            WorkoutPlan.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - previousEntry

    func test_previousEntry_returnsNil_forNilExercise() {
        XCTAssertNil(WorkoutHistory.previousEntry(for: nil, in: context))
    }

    func test_previousEntry_returnsNil_whenNoHistory() {
        let exercise = makeExercise("Bench Press")
        XCTAssertNil(WorkoutHistory.previousEntry(for: exercise, in: context))
    }

    func test_previousEntry_returnsMostRecentMatchingEntry() throws {
        let exercise = makeExercise("Bench Press")
        let older = makeEntry(for: exercise, daysAgo: 7)
        let newer = makeEntry(for: exercise, daysAgo: 1)
        try context.save()

        let result = WorkoutHistory.previousEntry(for: exercise, in: context)
        XCTAssertEqual(result?.persistentModelID, newer.persistentModelID)
        _ = older
    }

    func test_previousEntry_ignoresOtherExercises() throws {
        let bench = makeExercise("Bench Press")
        let squat = makeExercise("Squat")
        _ = makeEntry(for: squat, daysAgo: 1)
        try context.save()

        XCTAssertNil(WorkoutHistory.previousEntry(for: bench, in: context))
    }

    func test_previousEntry_excludesCurrentInProgressEntries() throws {
        let exercise = makeExercise("Bench Press")
        let current = makeEntry(for: exercise, daysAgo: 1)
        try context.save()

        let result = WorkoutHistory.previousEntry(
            for: exercise,
            in: context,
            excluding: [current]
        )
        XCTAssertNil(result)
    }

    func test_previousEntry_excludesEntriesFromActiveWorkout() throws {
        let exercise = makeExercise("Bench Press")
        let workout = Workout(name: "Today", date: .now, duration: 0)
        context.insert(workout)
        let activeEntry = makeEntry(for: exercise, daysAgo: 0)
        activeEntry.workout = workout
        try context.save()

        let result = WorkoutHistory.previousEntry(
            for: exercise,
            in: context,
            activeWorkout: workout
        )
        XCTAssertNil(result)
    }

    func test_previousEntry_fallsBackThroughHistory_whenRecentIsExcluded() throws {
        let exercise = makeExercise("Bench Press")
        let older = makeEntry(for: exercise, daysAgo: 7)
        let newer = makeEntry(for: exercise, daysAgo: 1)
        try context.save()

        let result = WorkoutHistory.previousEntry(
            for: exercise,
            in: context,
            excluding: [newer]
        )
        XCTAssertEqual(result?.persistentModelID, older.persistentModelID)
    }

    // MARK: - appendSet

    func test_appendSet_assignsSetNumberOne_whenEntryIsEmpty() throws {
        let exercise = makeExercise("Bench Press")
        let entry = makeEntry(for: exercise, daysAgo: 0)
        try context.save()

        let added = WorkoutHistory.appendSet(weight: 60, reps: 10, to: entry, in: context)

        XCTAssertEqual(added.setNumber, 1)
        XCTAssertEqual(added.weight, 60)
        XCTAssertEqual(added.reps, 10)
        XCTAssertEqual(entry.sets.count, 1)
    }

    func test_appendSet_incrementsFromHighestExistingSetNumber() throws {
        let exercise = makeExercise("Bench Press")
        let entry = makeEntry(for: exercise, daysAgo: 0)
        let s1 = WorkoutSet(setNumber: 1, weight: 60, reps: 10, workoutEntry: entry)
        let s3 = WorkoutSet(setNumber: 3, weight: 70, reps: 8, workoutEntry: entry)
        context.insert(s1)
        context.insert(s3)
        entry.sets = [s1, s3]
        try context.save()

        let added = WorkoutHistory.appendSet(weight: 80, reps: 6, to: entry, in: context)

        XCTAssertEqual(added.setNumber, 4)
        XCTAssertEqual(entry.sets.count, 3)
    }

    func test_appendSet_inserts_intoModelContext() throws {
        let exercise = makeExercise("Bench Press")
        let entry = makeEntry(for: exercise, daysAgo: 0)
        let initialSetCount = entry.sets.count
        try context.save()

        let added = WorkoutHistory.appendSet(weight: 50, reps: 12, to: entry, in: context)
        try context.save()

        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        XCTAssertEqual(allSets.count, 1)
        XCTAssertEqual(allSets.first?.weight, 50)
        // Guard against regressions that insert the set into the context but
        // forget to attach it to `entry.sets` (MHE-28).
        XCTAssertEqual(entry.sets.count, initialSetCount + 1)
        XCTAssertTrue(entry.sets.contains { $0.persistentModelID == added.persistentModelID })
    }

    // MARK: - Helpers

    private func makeExercise(_ name: String) -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: .chest, equipmentType: .freeWeight)
        context.insert(exercise)
        return exercise
    }

    private func makeEntry(for exercise: Exercise, daysAgo: Int) -> WorkoutEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let entry = WorkoutEntry(date: date, exercise: exercise)
        context.insert(entry)
        return entry
    }
}
