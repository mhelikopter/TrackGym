import WatchConnectivity
import Foundation

struct WatchSetPayload: Hashable {
    let setNumber: Int
    let weight: Double
    let reps: Int
}

final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendActiveExercise(name: String, muscleGroup: String, unit: String, sets: [WatchSetPayload]) {
        guard WCSession.default.isReachable else { return }
        let setsDicts: [[String: Any]] = sets.map {
            ["setNumber": $0.setNumber, "weight": $0.weight, "reps": $0.reps]
        }
        let message: [String: Any] = [
            "type": "activeExercise",
            "exerciseName": name,
            "muscleGroup": muscleGroup,
            "unit": unit,
            "sets": setsDicts
        ]
        WCSession.default.sendMessage(message, replyHandler: nil)
    }

    func sendWorkoutEnded() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["type": "workoutEnded"], replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String, type == "addSet",
              let weight = message["weight"] as? Double,
              let reps = message["reps"] as? Int else { return }
        var payload: [AnyHashable: Any] = ["weight": weight, "reps": reps]
        if let name = message["exerciseName"] as? String, !name.isEmpty {
            payload["exerciseName"] = name
        }
        Task { @MainActor in
            NotificationCenter.default.post(name: .watchDidAddSet, object: nil, userInfo: payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}

extension Notification.Name {
    static let watchDidAddSet = Notification.Name("watchDidAddSet")
}
