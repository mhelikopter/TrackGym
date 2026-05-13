import SwiftUI
import WatchKit

struct LogSetView: View {
    @Environment(WatchConnectivityManager.self) private var connectivity
    @Environment(\.dismiss) private var dismiss

    @State private var weight: Double = 0
    @State private var reps: Int = 1

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
                            through: 300,
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
    }

    private func saveSet() {
        WKInterfaceDevice.current().play(.success)
        connectivity.sendSet(weight: weight, reps: reps)
        dismiss()
    }
}
