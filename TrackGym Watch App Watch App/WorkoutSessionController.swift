import Foundation
import HealthKit
import Observation
import OSLog

/// Besitzt die HealthKit-Workout-Session der Watch. Verweigerte Berechtigung
/// oder Session-Fehler blockieren nichts: das Workout-Tracking über
/// WatchConnectivity läuft unverändert, es fehlen nur Puls/Kalorien/Ringe.
@Observable
final class WorkoutSessionController: NSObject {
    static let shared = WorkoutSessionController()
    private static let log = Logger(subsystem: "de.ehling.TrackGym.watchkitapp", category: "WorkoutSession")

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var heartRate: Double?
    var activeEnergy: Double?
    var isRunning = false

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
            guard granted, let self else { return }
            Task { @MainActor in
                self.beginSession()
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
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, error in
                if let error {
                    Self.log.error("beginCollection failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            isRunning = true
        } catch {
            Self.log.error("Workout session start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Beendet die Session und speichert das Workout in HealthKit
    /// (zählt für die Aktivitätsringe).
    @MainActor
    func end() {
        guard isRunning, let session, let builder else { return }
        isRunning = false
        session.end()
        builder.endCollection(withEnd: Date()) { _, error in
            if let error {
                Self.log.error("endCollection failed: \(error.localizedDescription, privacy: .public)")
            }
            builder.finishWorkout { _, error in
                if let error {
                    Self.log.error("finishWorkout failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        self.session = nil
        self.builder = nil
        heartRate = nil
        activeEnergy = nil
    }
}

extension WorkoutSessionController: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Self.log.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.end()
        }
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: quantityType) else { continue }
            Task { @MainActor in
                switch quantityType {
                case heartRateType:
                    self.heartRate = stats.mostRecentQuantity()?
                        .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                case energyType:
                    self.activeEnergy = stats.sumQuantity()?
                        .doubleValue(for: .kilocalorie())
                default:
                    break
                }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
