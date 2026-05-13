//
//  TrackGym_Watch_App_Watch_AppTests.swift
//  TrackGym Watch App Watch AppTests
//
//  Created by Maximilian Ehling on 26.02.26.
//

import XCTest
@testable import TrackGym_Watch_App_Watch_App

final class TrackGym_Watch_App_Watch_AppTests: XCTestCase {

    // MARK: - applyState("activeExercise")

    /// Verifies that an "activeExercise" payload fully populates the manager's
    /// published state and flips workoutActive to true.
    func testApplyState_activeExercise_updatesAllFields() async throws {
        let manager = WatchConnectivityManager()

        let payload: [String: Any] = [
            "type": "activeExercise",
            "exerciseName": "Bench Press",
            "muscleGroup": "Chest",
            "unit": "lbs",
            "sets": [
                ["setNumber": 1, "weight": 60.0, "reps": 10],
                ["setNumber": 2, "weight": 65.0, "reps": 8]
            ]
        ]

        manager.applyState(payload)

        // applyState dispatches onto @MainActor; yield so it can run.
        await Task.yield()
        // Give the MainActor task time to complete.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        XCTAssertTrue(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "Bench Press")
        XCTAssertEqual(manager.muscleGroup, "Chest")
        XCTAssertEqual(manager.unit, "lbs")
        XCTAssertEqual(manager.sets.count, 2)
        XCTAssertEqual(manager.sets.first?.setNumber, 1)
        XCTAssertEqual(manager.sets.first?.weight, 60.0)
        XCTAssertEqual(manager.sets.first?.reps, 10)
    }

    // MARK: - applyState("workoutEnded")

    /// Verifies that a "workoutEnded" payload clears workoutActive, exerciseName,
    /// and sets — even when a workout was previously active.
    func testApplyState_workoutEnded_clearsState() async throws {
        let manager = WatchConnectivityManager()

        // First put the manager into an active state.
        let startPayload: [String: Any] = [
            "type": "activeExercise",
            "exerciseName": "Squat",
            "muscleGroup": "Legs",
            "unit": "kg",
            "sets": [["setNumber": 1, "weight": 100.0, "reps": 5]]
        ]
        manager.applyState(startPayload)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Now end the workout.
        manager.applyState(["type": "workoutEnded"])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "")
        XCTAssertTrue(manager.sets.isEmpty)
    }

    // MARK: - applyState with unknown type

    /// Verifies that an unrecognised message type does not mutate state.
    func testApplyState_unknownType_isIgnored() async throws {
        let manager = WatchConnectivityManager()

        manager.applyState(["type": "unknownEvent", "data": "irrelevant"])
        try await Task.sleep(nanoseconds: 50_000_000)

        // Default initial values must be preserved.
        XCTAssertFalse(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "")
        XCTAssertTrue(manager.sets.isEmpty)
    }

    // MARK: - applyState with missing type key

    /// Verifies that a payload without a "type" key is silently discarded.
    func testApplyState_missingTypeKey_isIgnored() async throws {
        let manager = WatchConnectivityManager()

        manager.applyState(["exerciseName": "Deadlift"])
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "")
    }
}
