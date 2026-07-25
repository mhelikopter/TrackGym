import WatchConnectivity
import Foundation

struct WatchSetPayload: Hashable {
    let setNumber: Int
    let weight: Double
    let reps: Int
}

/// A set logged on the watch, validated and ready for the active workout.
struct WatchAddSetRequest {
    let weight: Double
    let reps: Int
    let exerciseName: String?
    /// Watch-side timestamp (timeIntervalSince1970). Used to drop stale sets
    /// that were queued during an earlier workout.
    let sentAt: Double?
}

final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()
    static let maximumAcceptedWeight = 2_000.0
    static let maximumAcceptedReps = 1_000

    /// Registered by ActiveWorkoutView while a workout is running. Returns
    /// true when the set was accepted and appended to the current exercise.
    @MainActor var addSetHandler: ((WatchAddSetRequest) -> Bool)?

    /// Ids of recently processed sets. The watch re-sends the identical
    /// payload via transferUserInfo when sendMessage reports an error even
    /// though the message may have been delivered — duplicates land here.
    @MainActor private var recentSetIDs: [String] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendActiveExercise(name: String, muscleGroup: String, unit: String, sets: [WatchSetPayload]) {
        let setsDicts: [[String: Any]] = sets.map {
            ["setNumber": $0.setNumber, "weight": $0.weight, "reps": $0.reps]
        }
        pushState([
            "type": "activeExercise",
            "exerciseName": name,
            "muscleGroup": muscleGroup,
            "unit": unit,
            "sets": setsDicts
        ])
    }

    func sendWorkoutEnded() {
        pushState(["type": "workoutEnded"])
    }

    private func pushState(_ payload: [String: Any]) {
        var payload = payload
        // Fresh stamp per push: makes every applicationContext update distinct
        // (identical dictionaries are not redelivered) and lets the watch
        // remember which state the user dismissed locally.
        payload["sentAt"] = Date().timeIntervalSince1970
        // Application context survives unreachability and is replayed on watch wake.
        do {
            try WCSession.default.updateApplicationContext(payload)
        } catch {
            NSLog("updateApplicationContext failed: %@", error.localizedDescription)
        }
        // Best-effort immediate delivery when the watch is awake and reachable.
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil) { error in
            NSLog("sendMessage state failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Incoming sets

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            _ = self.deliverAddSet(message)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            let accepted = self.deliverAddSet(message)
            replyHandler(["status": accepted ? "ok" : "rejected"])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            _ = self.deliverAddSet(userInfo)
        }
    }

    @MainActor
    private func deliverAddSet(_ message: [String: Any]) -> Bool {
        guard let type = message["type"] as? String, type == "addSet",
              let weight = message["weight"] as? Double,
              let reps = message["reps"] as? Int else { return false }
        guard Self.isValidAddSetPayload(weight: weight, reps: reps) else {
            NSLog("Ignoring invalid watch addSet payload")
            return false
        }
        if let id = message["id"] as? String, !markSetIDProcessed(id) {
            // Duplicate delivery of a set that was already accepted.
            return true
        }
        let request = WatchAddSetRequest(
            weight: weight,
            reps: reps,
            exerciseName: (message["exerciseName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            sentAt: message["sentAt"] as? Double
        )
        guard let handler = addSetHandler else {
            // No workout is running on the phone — clear the watch so it does
            // not keep showing a stale session and swallowing sets.
            sendWorkoutEnded()
            return false
        }
        return handler(request)
    }

    /// Returns false when the id was already processed.
    @MainActor
    private func markSetIDProcessed(_ id: String) -> Bool {
        if recentSetIDs.contains(id) { return false }
        recentSetIDs.append(id)
        if recentSetIDs.count > 64 {
            recentSetIDs.removeFirst(recentSetIDs.count - 64)
        }
        return true
    }

    static func isValidAddSetPayload(weight: Double, reps: Int) -> Bool {
        weight.isFinite &&
        weight >= 0 &&
        weight <= maximumAcceptedWeight &&
        reps > 0 &&
        reps <= maximumAcceptedReps
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
