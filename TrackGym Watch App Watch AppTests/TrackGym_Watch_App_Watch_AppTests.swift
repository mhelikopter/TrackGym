//
//  TrackGym_Watch_App_Watch_AppTests.swift
//  TrackGym Watch App Watch AppTests
//
//  Created by Maximilian Ehling on 26.02.26.
//

import XCTest
@testable import TrackGym_Watch_App_Watch_App

final class TrackGym_Watch_App_Watch_AppTests: XCTestCase {

    // MARK: - applyStateSynchronously("activeExercise")

    /// Verifies that an "activeExercise" payload fully populates the manager's
    /// published state and flips workoutActive to true.
    @MainActor
    func testApplyState_activeExercise_updatesAllFields() {
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

        manager.applyStateSynchronously(payload)

        XCTAssertTrue(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "Bench Press")
        XCTAssertEqual(manager.muscleGroup, "Chest")
        XCTAssertEqual(manager.unit, "lbs")
        XCTAssertEqual(manager.sets.count, 2)
        XCTAssertEqual(manager.sets.first?.setNumber, 1)
        XCTAssertEqual(manager.sets.first?.weight, 60.0)
        XCTAssertEqual(manager.sets.first?.reps, 10)
    }

    // MARK: - Pausen-Timer

    @MainActor
    func testApplyState_parsesFutureRestEndsAt() {
        let manager = WatchConnectivityManager()
        let end = Date().addingTimeInterval(90).timeIntervalSince1970

        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [] as [[String: Any]], "restEndsAt": end
        ])

        XCTAssertEqual(manager.restEndDate?.timeIntervalSince1970 ?? 0, end, accuracy: 0.001)
    }

    @MainActor
    func testApplyState_ignoresExpiredRestEndsAt() {
        let manager = WatchConnectivityManager()
        let past = Date().addingTimeInterval(-10).timeIntervalSince1970

        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [] as [[String: Any]], "restEndsAt": past
        ])

        XCTAssertNil(manager.restEndDate)
    }

    @MainActor
    func testApplyState_clearsRestTimer_whenPayloadOmitsIt() {
        let manager = WatchConnectivityManager()
        let end = Date().addingTimeInterval(90).timeIntervalSince1970
        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [] as [[String: Any]], "restEndsAt": end
        ])

        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [] as [[String: Any]]
        ])

        XCTAssertNil(manager.restEndDate)
    }

    @MainActor
    func testApplyState_workoutEnded_clearsRestTimer() {
        let manager = WatchConnectivityManager()
        let end = Date().addingTimeInterval(90).timeIntervalSince1970
        manager.applyStateSynchronously([
            "type": "activeExercise", "exerciseName": "Bench", "muscleGroup": "chest",
            "unit": "kg", "sets": [] as [[String: Any]], "restEndsAt": end
        ])

        manager.applyStateSynchronously(["type": "workoutEnded"])

        XCTAssertNil(manager.restEndDate)
    }

    // MARK: - applyStateSynchronously("workoutEnded")

    /// Verifies that a "workoutEnded" payload clears workoutActive, exerciseName,
    /// and sets — even when a workout was previously active.
    @MainActor
    func testApplyState_workoutEnded_clearsState() {
        let manager = WatchConnectivityManager()

        // First put the manager into an active state.
        let startPayload: [String: Any] = [
            "type": "activeExercise",
            "exerciseName": "Squat",
            "muscleGroup": "Legs",
            "unit": "kg",
            "sets": [["setNumber": 1, "weight": 100.0, "reps": 5]]
        ]
        manager.applyStateSynchronously(startPayload)

        // Now end the workout.
        manager.applyStateSynchronously(["type": "workoutEnded"])

        XCTAssertFalse(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "")
        XCTAssertTrue(manager.sets.isEmpty)
    }

    // MARK: - applyStateSynchronously with unknown type

    /// Verifies that an unrecognised message type does not mutate state.
    @MainActor
    func testApplyState_unknownType_isIgnored() {
        let manager = WatchConnectivityManager()

        manager.applyStateSynchronously(["type": "unknownEvent", "data": "irrelevant"])

        // Default initial values must be preserved.
        XCTAssertFalse(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "")
        XCTAssertTrue(manager.sets.isEmpty)
    }

    // MARK: - applyStateSynchronously with missing type key

    /// Verifies that a payload without a "type" key is silently discarded.
    @MainActor
    func testApplyState_missingTypeKey_isIgnored() {
        let manager = WatchConnectivityManager()

        manager.applyStateSynchronously(["exerciseName": "Deadlift"])

        XCTAssertFalse(manager.workoutActive)
        XCTAssertEqual(manager.exerciseName, "")
    }

    // MARK: - shouldReplay (activation replay of stored applicationContext)

    private func context(sentAt: Double?) -> [String: Any] {
        var payload: [String: Any] = ["type": "activeExercise", "exerciseName": "Squat"]
        if let sentAt { payload["sentAt"] = sentAt }
        return payload
    }

    func testShouldReplay_isFalse_forEmptyContext() {
        XCTAssertFalse(WatchConnectivityManager.shouldReplay(context: [:], clearedStamp: 0, now: Date()))
    }

    func testShouldReplay_isTrue_forFreshContext() {
        let now = Date()
        let stamp = now.timeIntervalSince1970 - 60
        XCTAssertTrue(WatchConnectivityManager.shouldReplay(context: context(sentAt: stamp), clearedStamp: 0, now: now))
    }

    func testShouldReplay_isFalse_forTheStateTheUserDismissed() {
        let now = Date()
        let stamp = now.timeIntervalSince1970 - 60
        XCTAssertFalse(WatchConnectivityManager.shouldReplay(context: context(sentAt: stamp), clearedStamp: stamp, now: now))
    }

    func testShouldReplay_isFalse_forContextOlderThanMaxReplayAge() {
        // Phone app died mid-workout yesterday and never sent workoutEnded.
        let now = Date()
        let stamp = now.timeIntervalSince1970 - WatchConnectivityManager.maxReplayAge - 1
        XCTAssertFalse(WatchConnectivityManager.shouldReplay(context: context(sentAt: stamp), clearedStamp: 0, now: now))
    }

    func testShouldReplay_isTrue_justInsideMaxReplayAge() {
        let now = Date()
        let stamp = now.timeIntervalSince1970 - WatchConnectivityManager.maxReplayAge + 1
        XCTAssertTrue(WatchConnectivityManager.shouldReplay(context: context(sentAt: stamp), clearedStamp: 0, now: now))
    }

    func testShouldReplay_isTrue_forContextWithoutStamp() {
        // Older phone builds sent no sentAt; never lock those out.
        XCTAssertTrue(WatchConnectivityManager.shouldReplay(context: context(sentAt: nil), clearedStamp: 0, now: Date()))
    }
}
