import SwiftUI

struct WorkoutSessionView: View {
    @Environment(WatchConnectivityManager.self) private var connectivity
    @State private var showingLogSet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: muscleIcon)
                        .foregroundStyle(.blue)
                    Text(connectivity.exerciseName)
                        .font(.headline)
                        .lineLimit(2)
                }
                .padding(.bottom, 4)

                Text(connectivity.muscleGroup)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                if connectivity.sets.isEmpty {
                    Text("Noch keine Sätze")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(connectivity.sets) { set in
                        HStack {
                            Text("Satz \(set.setNumber)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(set.weight, specifier: "%.1f") \(connectivity.unit) × \(set.reps)")
                                .font(.caption)
                        }
                    }
                }

                Divider()

                Button {
                    showingLogSet = true
                } label: {
                    Label("Satz hinzufügen", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(role: .destructive) {
                    connectivity.clearLocalState()
                } label: {
                    Label("Workout beenden", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Workout")
        .sheet(isPresented: $showingLogSet) {
            LogSetView()
                .environment(connectivity)
        }
    }

    private var muscleIcon: String {
        switch connectivity.muscleGroup {
        case "Brust": return "figure.strengthtraining.traditional"
        case "Rücken": return "figure.rowing"
        case "Schultern": return "figure.arms.open"
        case "Arme": return "dumbbell.fill"
        case "Beine": return "figure.walk"
        case "Core": return "figure.core.training"
        default: return "figure.strengthtraining.traditional"
        }
    }
}
