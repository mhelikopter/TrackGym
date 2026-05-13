import SwiftUI

struct ContentView: View {
    @State private var connectivity = WatchConnectivityManager.shared

    var body: some View {
        if connectivity.workoutActive {
            WorkoutSessionView()
                .environment(connectivity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.largeTitle)
                Text("Starte ein Workout auf dem iPhone")
                    .multilineTextAlignment(.center)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}
