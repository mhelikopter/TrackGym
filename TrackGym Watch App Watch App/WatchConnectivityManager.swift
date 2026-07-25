import WatchConnectivity
import Foundation
import Observation
import WatchKit

struct WatchSet: Identifiable, Hashable {
    let setNumber: Int
    let weight: Double
    let reps: Int

    var id: Int { setNumber }
}

/// Outcome of logging a set from the watch, surfaced as haptic feedback.
enum SetDeliveryOutcome {
    /// The phone accepted the set into the running workout.
    case delivered
    /// The phone was unreachable — queued via transferUserInfo for guaranteed
    /// later delivery.
    case queued
    /// The phone refused the set (stale exercise state or no active workout).
    case rejected
}

@Observable
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private static let clearedContextStampKey = "clearedContextStamp"

    var exerciseName: String = ""
    var muscleGroup: String = ""
    var unit: String = "kg"
    var sets: [WatchSet] = []
    var workoutActive: Bool = false
    var isReachable: Bool = false

    /// Endzeitpunkt der laufenden Satzpause; nil wenn kein Timer aktiv.
    var restEndDate: Date?

    @ObservationIgnored
    private var restHapticTask: Task<Void, Never>?

    /// Stamp (`sentAt`) of the state currently applied. Persisted on
    /// clearLocalState so activation replay cannot resurrect a workout the
    /// user dismissed on the watch.
    private var lastContextStamp: Double = 0

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendSet(weight: Double, reps: Int, completion: @escaping (SetDeliveryOutcome) -> Void) {
        let message: [String: Any] = [
            "type": "addSet",
            "weight": weight,
            "reps": reps,
            "exerciseName": exerciseName,
            "id": UUID().uuidString,
            "sentAt": Date().timeIntervalSince1970
        ]
        let finish: (SetDeliveryOutcome) -> Void = { outcome in
            Task { @MainActor in completion(outcome) }
        }
        guard WCSession.default.isReachable else {
            WCSession.default.transferUserInfo(message)
            finish(.queued)
            return
        }
        WCSession.default.sendMessage(message, replyHandler: { reply in
            finish((reply["status"] as? String) == "ok" ? .delivered : .rejected)
        }, errorHandler: { error in
            NSLog("addSet sendMessage failed, queuing: %@", error.localizedDescription)
            WCSession.default.transferUserInfo(message)
            finish(.queued)
        })
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyState(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyState(applicationContext)
    }

    /// Entry point for incoming WCSession payloads. WCSessionDelegate callbacks
    /// arrive on a background queue, so this wrapper hops to the main actor and
    /// invokes the synchronous mutation core. Production call sites are unchanged.
    func applyState(_ message: [String: Any]) {
        Task { @MainActor in
            self.applyStateSynchronously(message)
        }
    }

    /// Synchronous, MainActor-isolated mutation core. Exposed at internal
    /// visibility so unit tests can drive state transitions deterministically
    /// without relying on `Task.sleep` to bridge the async hop.
    @MainActor
    func applyStateSynchronously(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        lastContextStamp = message["sentAt"] as? Double ?? 0
        switch type {
        case "activeExercise":
            self.exerciseName = message["exerciseName"] as? String ?? ""
            self.muscleGroup = message["muscleGroup"] as? String ?? ""
            self.unit = message["unit"] as? String ?? "kg"
            let raw = message["sets"] as? [[String: Any]] ?? []
            // Tolerant number parsing: values boxed as Swift Int or Double do
            // not cross-cast through Any, and payloads produced in-process
            // (tests) or via plist decoding may carry either representation.
            self.sets = raw.compactMap { dict in
                guard let n = Self.intValue(dict["setNumber"]),
                      let w = Self.doubleValue(dict["weight"]),
                      let r = Self.intValue(dict["reps"]) else { return nil }
                return WatchSet(setNumber: n, weight: w, reps: r)
            }
            self.workoutActive = true
            if let ends = message["restEndsAt"] as? Double,
               ends > Date().timeIntervalSince1970 {
                self.restEndDate = Date(timeIntervalSince1970: ends)
            } else {
                self.restEndDate = nil
            }
            scheduleRestHaptic()
        case "workoutEnded":
            self.workoutActive = false
            self.exerciseName = ""
            self.sets = []
            self.restEndDate = nil
            restHapticTask?.cancel()
        default:
            break
        }
    }

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

    /// Clears workout state locally without requiring the phone to be reachable.
    /// Use this as an escape hatch when the phone process was killed mid-workout
    /// and the watch is stuck with workoutActive = true.
    @MainActor
    func clearLocalState() {
        // Remember which pushed state was dismissed so the activation replay
        // below does not immediately resurrect it on the next app launch.
        UserDefaults.standard.set(lastContextStamp, forKey: Self.clearedContextStampKey)
        workoutActive = false
        exerciseName = ""
        muscleGroup = ""
        unit = "kg"
        sets = []
        restEndDate = nil
        restHapticTask?.cancel()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // didReceiveApplicationContext only fires for content that has not
        // been delivered yet; a context received before the watch app was
        // terminated is never replayed by the system. Restore it manually so
        // a relaunched watch app rejoins the still-running workout.
        let stored = session.receivedApplicationContext
        Task { @MainActor in
            self.isReachable = session.isReachable
            guard !stored.isEmpty else { return }
            let stamp = stored["sentAt"] as? Double ?? 0
            let clearedStamp = UserDefaults.standard.double(forKey: Self.clearedContextStampKey)
            if stamp != 0 && stamp == clearedStamp {
                return  // the user dismissed exactly this state via clearLocalState
            }
            self.applyStateSynchronously(stored)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double, d.isFinite { return Int(d) }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
