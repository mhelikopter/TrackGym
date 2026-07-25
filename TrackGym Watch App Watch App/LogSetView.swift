import SwiftUI
import WatchKit

struct LogSetView: View {
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(\.dismiss) private var dismiss

    @State private var weight: Double = 0
    @State private var reps: Int = 1

    /// Crown range in the *display* unit: 300 kg and its lbs equivalent,
    /// so heavy lifts stay loggable regardless of the selected unit.
    private var maxWeight: Double {
        connectivity.unit == "lbs" ? 660 : 300
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gewicht (\(connectivity.unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(weight, specifier: "%.1f") \(connectivity.unit)")
                        .font(.title3.bold())
                        .focusable()
                        .digitalCrownRotation(
                            $weight,
                            from: 0,
                            through: maxWeight,
                            by: 0.5,
                            sensitivity: .medium,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Wiederholungen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(reps) Wdh")
                        .font(.title3.bold())
                        .focusable()
                        .digitalCrownRotation(
                            Binding(
                                get: { Double(reps) },
                                set: { reps = max(1, Int($0.rounded())) }
                            ),
                            from: 1,
                            through: 50,
                            by: 1,
                            sensitivity: .medium,
                            isContinuous: false,
                            isHapticFeedbackEnabled: true
                        )
                }

                Divider()

                Button {
                    saveSet()
                } label: {
                    Label("Speichern", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
        .navigationTitle("Satz loggen")
        .onAppear {
            // Prefill from the most recent set so the user only fine-tunes.
            if weight == 0, let last = connectivity.sets.last {
                weight = last.weight
                reps = max(1, last.reps)
            }
        }
    }

    private func saveSet() {
        // Haptic reflects the real outcome instead of unconditional success:
        // .success = phone accepted, .click = queued for later delivery,
        // .failure = phone refused (stale exercise / no active workout).
        connectivity.sendSet(weight: weight, reps: reps) { outcome in
            switch outcome {
            case .delivered:
                WKInterfaceDevice.current().play(.success)
            case .queued:
                WKInterfaceDevice.current().play(.click)
            case .rejected:
                WKInterfaceDevice.current().play(.failure)
            }
        }
        dismiss()
    }
}
