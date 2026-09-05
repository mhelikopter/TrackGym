import XCTest
@testable import TrackGym

/// Covers the phone-side parsing of watch messages. The delegate callbacks
/// themselves need a live WCSession, but everything they do with a payload
/// goes through `parseAddSet`.
final class WatchPayloadTests: XCTestCase {

    func test_parseAddSet_readsAllFields() throws {
        let request = try XCTUnwrap(PhoneConnectivityManager.parseAddSet([
            "type": "addSet",
            "weight": 82.5,
            "reps": 8,
            "exerciseName": "Bankdrücken",
            "id": "ABC-123",
            "sentAt": 1_700_000_000.0,
        ]))

        XCTAssertEqual(request.weight, 82.5)
        XCTAssertEqual(request.reps, 8)
        XCTAssertEqual(request.exerciseName, "Bankdrücken")
        XCTAssertEqual(request.id, "ABC-123")
        XCTAssertEqual(request.sentAt, 1_700_000_000.0)
    }

    func test_parseAddSet_treatsEmptyExerciseNameAsMissing() throws {
        let request = try XCTUnwrap(PhoneConnectivityManager.parseAddSet([
            "type": "addSet", "weight": 10.0, "reps": 5, "exerciseName": "",
        ]))
        XCTAssertNil(request.exerciseName)
        XCTAssertNil(request.id)
    }

    func test_parseAddSet_rejectsOtherMessageTypes() {
        XCTAssertNil(PhoneConnectivityManager.parseAddSet(["type": "activeExercise", "weight": 10.0, "reps": 5]))
        XCTAssertNil(PhoneConnectivityManager.parseAddSet([:]))
    }

    func test_parseAddSet_rejectsMalformedNumbers() {
        XCTAssertNil(PhoneConnectivityManager.parseAddSet(["type": "addSet", "weight": "80", "reps": 5]))
        XCTAssertNil(PhoneConnectivityManager.parseAddSet(["type": "addSet", "weight": 80.0]))
    }

    func test_parseAddSet_rejectsImplausibleValues() {
        XCTAssertNil(PhoneConnectivityManager.parseAddSet(["type": "addSet", "weight": -1.0, "reps": 5]))
        XCTAssertNil(PhoneConnectivityManager.parseAddSet(["type": "addSet", "weight": 80.0, "reps": 0]))
        XCTAssertNil(PhoneConnectivityManager.parseAddSet(["type": "addSet", "weight": Double.infinity, "reps": 5]))
    }
}
