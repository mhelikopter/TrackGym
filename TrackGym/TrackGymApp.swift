import SwiftUI
import SwiftData

@main
struct TrackGymApp: App {
    let sharedModelContainer: ModelContainer = {
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
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("ModelContainer konnte nicht geladen werden: \(error). Eine Migration ist evtl. erforderlich.")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    DefaultExercises.seedDefaultExercises(context: sharedModelContainer.mainContext)
                    PhoneConnectivityManager.shared.activate()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
