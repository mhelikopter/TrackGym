import WatchConnectivity
import Foundation
import Observation

struct WatchSet: Identifiable, Hashable {
    let setNumber: Int
    let weight: Double
    let reps: Int

    var id: Int { setNumber }
}

@Observable
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    var exerciseName: String = ""
    var muscleGroup: String = ""
    var unit: String = "kg"
    var sets: [WatchSet] = []
    var workoutActive: Bool = false
    var isReachable: Bool = false

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendSet(weight: Double, reps: Int) {
        let message: [String: Any] = [
            "type": "addSet",
            "weight": weight,
            "reps": reps,
            "exerciseName": exerciseName
        ]
        // Prefer immediate delivery; fall back to a guaranteed queued transfer
        // so a set logged while the phone is briefly unreachable is not lost.
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                NSLog("addSet sendMessage failed, queuing: %@", error.localizedDescription)
                WCSession.default.transferUserInfo(message)
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyState(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyState(applicationContext)
    }

    func applyState(_ message: [String: Any]) {
        Task { @MainActor in
            guard let type = message["type"] as? String else { return }
            switch type {
            case "activeExercise":
                self.exerciseName = message["exerciseName"] as? String ?? ""
                self.muscleGroup = message["muscleGroup"] as? String ?? ""
                self.unit = message["unit"] as? String ?? "kg"
                let raw = message["sets"] as? [[String: Any]] ?? []
                self.sets = raw.compactMap { dict in
                    guard let n = dict["setNumber"] as? Int,
                          let w = dict["weight"] as? Double,
                          let r = dict["reps"] as? Int else { return nil }
                    return WatchSet(setNumber: n, weight: w, reps: r)
                }
                self.workoutActive = true
            case "workoutEnded":
                self.workoutActive = false
                self.exerciseName = ""
                self.sets = []
            default:
                break
            }
        }
    }

    /// Clears workout state locally without requiring the phone to be reachable.
    /// Use this as an escape hatch when the phone process was killed mid-workout
    /// and the watch is stuck with workoutActive = true.
    @MainActor
    func clearLocalState() {
        workoutActive = false
        exerciseName = ""
        muscleGroup = ""
        unit = "kg"
        sets = []
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }
}
