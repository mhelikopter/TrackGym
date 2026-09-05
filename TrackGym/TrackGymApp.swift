import SwiftUI
import SwiftData
import OSLog

@main
struct TrackGymApp: App {
    private static let log = Logger(subsystem: "de.ehling.TrackGym", category: "AppLaunch")

    private let modelContainerResult: Result<ModelContainer, Error> = {
        let schema = Schema([
            Exercise.self,
            WorkoutEntry.self,
            WorkoutSet.self,
            WorkoutPlan.self,
            Workout.self,
            SeedVersion.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return .success(try ModelContainer(for: schema, configurations: [modelConfiguration]))
        } catch {
            log.error("ModelContainer load failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }()

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch modelContainerResult {
        case .success(let modelContainer):
            ContentView()
                .onAppear {
                    DefaultExercises.seedDefaultExercises(context: modelContainer.mainContext)
                    do {
                        try Exercise.backfillStableIDs(context: modelContainer.mainContext)
                    } catch {
                        Self.log.error("Exercise stable ID backfill failed: \(error.localizedDescription, privacy: .public)")
                    }
                    do {
                        let removed = try WorkoutHistory.deleteOrphanedEntries(in: modelContainer.mainContext)
                        if removed > 0 {
                            Self.log.notice("Removed \(removed) orphaned workout entries left by an interrupted workout")
                        }
                    } catch {
                        Self.log.error("Orphaned entry cleanup failed: \(error.localizedDescription, privacy: .public)")
                    }
                    PhoneConnectivityManager.shared.activate()
                }
                .modelContainer(modelContainer)
        case .failure(let error):
            StoreUnavailableView(error: error)
        }
    }
}

private struct StoreUnavailableView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Daten konnten nicht geladen werden", systemImage: "exclamationmark.triangle.fill")
        } description: {
            VStack(spacing: 8) {
                Text("TrackGym kann die lokale Datenbank gerade nicht öffnen.")
                Text("Beende die App vollständig und starte sie erneut. Wenn das Problem bestehen bleibt, aktualisiere die App oder kontaktiere den Support, bevor du App-Daten löschst.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
