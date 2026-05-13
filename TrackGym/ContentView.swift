import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("appColorScheme") private var appColorScheme: String = AppColorScheme.system.rawValue

    private var colorScheme: ColorScheme? {
        (AppColorScheme(rawValue: appColorScheme) ?? .system).colorScheme
    }

    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            ExerciseListView()
                .tag(0)
                .tabItem {
                    Label("Übungen", systemImage: "dumbbell.fill")
                }

            WorkoutView()
                .tag(1)
                .tabItem {
                    Label("Meine Trainings", systemImage: "figure.strengthtraining.traditional")
                }

            ProgressTabView()
                .tag(2)
                .tabItem {
                    Label("Fortschritt", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
        .preferredColorScheme(colorScheme)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, WorkoutEntry.self, WorkoutSet.self, WorkoutPlan.self, Workout.self], inMemory: true)
}
