import XCTest
@testable import TrackGym

@MainActor
final class RecentIDBufferTests: XCTestCase {

    func test_insert_acceptsNewIDs_andRejectsDuplicates() {
        var buffer = RecentIDBuffer(capacity: 4)

        XCTAssertTrue(buffer.insert("a"))
        XCTAssertTrue(buffer.insert("b"))
        XCTAssertFalse(buffer.insert("a"), "second delivery of the same id must be flagged")
        XCTAssertEqual(buffer.ids, ["a", "b"])
    }

    func test_insert_evictsOldestBeyondCapacity() {
        var buffer = RecentIDBuffer(capacity: 3)
        for id in ["a", "b", "c", "d"] {
            buffer.insert(id)
        }

        XCTAssertEqual(buffer.ids, ["b", "c", "d"])
        XCTAssertTrue(buffer.insert("a"), "an evicted id is not remembered anymore")
        XCTAssertFalse(buffer.contains("b"))
    }

    func test_init_keepsOnlyTheNewestIDs_whenGivenMoreThanCapacity() {
        let buffer = RecentIDBuffer(capacity: 2, ids: ["a", "b", "c"])
        XCTAssertEqual(buffer.ids, ["b", "c"])
    }

    func test_persistence_roundTripsThroughUserDefaults() throws {
        let suite = "RecentIDBufferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var buffer = RecentIDBuffer(capacity: 8)
        buffer.insert("first")
        buffer.insert("second")
        buffer.save(to: defaults, key: "ids")

        let restored = RecentIDBuffer.load(from: defaults, key: "ids", capacity: 8)
        XCTAssertEqual(restored, buffer)
        XCTAssertFalse(restored.contains("third"))
    }

    func test_load_returnsEmptyBuffer_whenNothingStored() throws {
        let suite = "RecentIDBufferTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let buffer = RecentIDBuffer.load(from: defaults, key: "missing")
        XCTAssertTrue(buffer.ids.isEmpty)
        XCTAssertEqual(buffer.capacity, 64)
    }
}
