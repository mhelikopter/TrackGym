import Foundation
import SwiftData

/// Singleton row that records the schema seed version applied to this store.
///
/// Storing the flag in SwiftData (rather than `UserDefaults`) ensures it
/// travels with the data:
/// - iCloud-backed stores or device-to-device restores carry the flag along
///   with the seeded `Exercise` rows.
/// - A `modelContext.rollback()` after a failed seed reverts the flag for
///   free, so we cannot end up with an empty store that claims to be seeded.
@Model
final class SeedVersion {
    var version: Int

    init(version: Int) {
        self.version = version
    }
}
