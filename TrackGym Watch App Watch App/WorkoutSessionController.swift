import Foundation
import HealthKit
import Observation
import OSLog

/// Besitzt die HealthKit-Workout-Session der Watch. Verweigerte Berechtigung
/// oder Session-Fehler blockieren nichts: das Workout-Tracking über
/// WatchConnectivity läuft unverändert, es fehlen nur Puls/Kalorien/Ringe.
///
/// Lifecycle folgt Apples Reihenfolge: `startActivity` + `beginCollection`
/// beim Start; beim Ende erst `session.end()`, dann — sobald die Session
/// `.ended` meldet — `endCollection(withEnd:)` mit dem Session-Datum und
/// `finishWorkout`. Eine nach einem Absturz von HealthKit weitergeführte
/// Session wird beim Start übernommen statt mit einer zweiten zu kollidieren.
@Observable
final class WorkoutSessionController: NSObject {
    static let shared = WorkoutSessionController()
    nonisolated private static let log = Logger(subsystem: "de.ehling.TrackGym.watchkitapp", category: "WorkoutSession")

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var heartRate: Double?
    var activeEnergy: Double?
    var isRunning = false
    /// Fehlertext des letzten `finishWorkout`; nil, solange nichts fehlschlug.
    /// Damit kann die UI sagen, ob das Training in Health angekommen ist.
    var lastSaveError: String?

    @MainActor
    func startIfNeeded() {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] granted, error in
            if let error {
                Self.log.error("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
            }
            // `granted` only says the sheet was handled, not that the user
            // said yes; a denied share right surfaces as an error on
            // startActivity/finishWorkout and is logged there.
            guard granted, let self else { return }
            Task { @MainActor in
                self.beginSession()
            }
        }
    }

    /// Übernimmt eine Session, die HealthKit nach Absturz/Terminierung der
    /// App am Leben gehalten hat. Ohne das schlägt der nächste Start mit
    /// einer zweiten Session fehl und das verwaiste Training wird nie
    /// gespeichert. `keepRunning` entscheidet (auf dem Main Actor), ob das
    /// Workout laut Phone noch läuft; sonst wird die Session sofort beendet.
    @MainActor
    func recoverIfNeeded(keepRunning: @escaping @MainActor () -> Bool) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            if let error {
                Self.log.error("Workout session recovery failed: \(error.localizedDescription, privacy: .public)")
            }
            guard let recovered else { return }
            Task { @MainActor in
                guard let self, !self.isRunning else { return }
                Self.log.notice("Adopted a workout session left over from a previous launch")
                self.adopt(recovered)
                if !keepRunning() {
                    self.end()
                }
            }
        }
    }

    @MainActor
    private func beginSession() {
        guard !isRunning else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            adopt(session)
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, error in
                if let error {
                    Self.log.error("beginCollection failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            Self.log.error("Workout session start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func adopt(_ session: HKWorkoutSession) {
        let builder = session.associatedWorkoutBuilder()
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        lastSaveError = nil
        isRunning = true
    }

    /// Beendet die Session. Das Speichern in HealthKit (zählt für die
    /// Aktivitätsringe) passiert in `finalize`, sobald die Session `.ended`
    /// meldet — mit dem Enddatum, das HealthKit dafür liefert.
    @MainActor
    func end() {
        guard isRunning, let session else { return }
        isRunning = false
        session.end()
    }

    @MainActor
    private func finalize(endDate: Date) {
        guard let builder else { return }
        self.builder = nil
        self.session = nil
        heartRate = nil
        activeEnergy = nil
        builder.endCollection(withEnd: endDate) { [weak self] _, error in
            if let error {
                Self.log.error("endCollection failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in self?.lastSaveError = error.localizedDescription }
                return
            }
            builder.finishWorkout { [weak self] _, error in
                if let error {
                    Self.log.error("finishWorkout failed: \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in self?.lastSaveError = error?.localizedDescription }
            }
        }
    }
}

extension WorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in
            self.finalize(endDate: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Self.log.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            // A failed session may never report .ended; finish what we have.
            self.isRunning = false
            self.finalize(endDate: Date())
        }
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        // Read the statistics on the callback queue and hop with plain values.
        let heartRate = collectedTypes.contains(heartRateType)
            ? workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            : nil
        let energy = collectedTypes.contains(energyType)
            ? workoutBuilder.statistics(for: energyType)?.sumQuantity()?
                .doubleValue(for: .kilocalorie())
            : nil
        guard heartRate != nil || energy != nil else { return }
        Task { @MainActor in
            if let heartRate { self.heartRate = heartRate }
            if let energy { self.activeEnergy = energy }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
