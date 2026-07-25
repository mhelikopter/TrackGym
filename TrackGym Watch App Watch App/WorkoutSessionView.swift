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

                Text(muscleDisplayName)
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

                if let restEnd = connectivity.restEndDate {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let remaining = Int(restEnd.timeIntervalSince(timeline.date).rounded(.up))
                        if remaining > 0 {
                            HStack {
                                Image(systemName: "hourglass")
                                    .foregroundStyle(.orange)
                                Text("Pause")
                                    .font(.caption)
                                Spacer()
                                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.orange)
                            }
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

                // Always available: WCSession.isReachable stays true whenever
                // the iPhone is in Bluetooth range even if the phone app was
                // killed mid-workout, so gating this on reachability would
                // hide it in exactly the stuck-state scenario it exists for.
                // It only clears local watch state; the phone re-pushes its
                // context on the next real workout.
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
        // Switch on MuscleGroup.rawValue (stable English identifier sent by the phone)
        // rather than the localised displayName so icon mapping is locale-independent.
        switch connectivity.muscleGroup {
        case "chest":     return "figure.strengthtraining.traditional"
        case "back":      return "figure.rowing"
        case "shoulders": return "figure.arms.open"
        case "arms":      return "dumbbell.fill"
        case "legs":      return "figure.walk"
        case "core":      return "figure.core.training"
        default:          return "figure.strengthtraining.traditional"
        }
    }

    /// The phone sends the raw identifier ("chest"); map it to the German
    /// label locally so the user never sees the internal value.
    private var muscleDisplayName: String {
        switch connectivity.muscleGroup {
        case "chest":     return "Brust"
        case "back":      return "Rücken"
        case "shoulders": return "Schultern"
        case "arms":      return "Arme"
        case "legs":      return "Beine"
        case "core":      return "Core"
        case "unknown", "": return "Unbekannt"
        default:          return connectivity.muscleGroup
        }
    }
}
