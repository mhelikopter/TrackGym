import Foundation

/// Bounded FIFO of recently seen identifiers. The watch re-sends a set via
/// `transferUserInfo` when `sendMessage` reports an error even though the
/// message may already have been delivered, so the phone has to recognise
/// the second copy. Persisted through `UserDefaults` so a relaunch of the
/// phone app between the two deliveries does not reopen that window.
struct RecentIDBuffer: Equatable {
    let capacity: Int
    private(set) var ids: [String]

    init(capacity: Int = 64, ids: [String] = []) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        self.ids = Array(ids.suffix(capacity))
    }

    /// Records `id`. Returns false when it was already present, i.e. the
    /// caller is looking at a duplicate delivery.
    @discardableResult
    mutating func insert(_ id: String) -> Bool {
        if ids.contains(id) { return false }
        ids.append(id)
        if ids.count > capacity {
            ids.removeFirst(ids.count - capacity)
        }
        return true
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    // MARK: - Persistence

    static func load(from defaults: UserDefaults, key: String, capacity: Int = 64) -> RecentIDBuffer {
        RecentIDBuffer(capacity: capacity, ids: defaults.stringArray(forKey: key) ?? [])
    }

    func save(to defaults: UserDefaults, key: String) {
        defaults.set(ids, forKey: key)
    }
}
