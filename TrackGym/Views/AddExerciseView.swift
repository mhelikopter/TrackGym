import SwiftUI
import SwiftData

struct AddExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedMuscleGroup: MuscleGroup = .chest
    @State private var selectedEquipmentType: EquipmentType = .freeWeight

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Übungsdetails") {
                    TextField("Name der Übung", text: $name)

                    Picker("Muskelgruppe", selection: $selectedMuscleGroup) {
                        ForEach(MuscleGroup.selectableCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }

                    Picker("Gerätetyp", selection: $selectedEquipmentType) {
                        ForEach(EquipmentType.selectableCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
            }
            .navigationTitle("Neue Übung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saveExercise()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func saveExercise() {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespaces),
            muscleGroup: selectedMuscleGroup,
            equipmentType: selectedEquipmentType,
            isCustom: true
        )
        modelContext.insert(exercise)
        dismiss()
    }
}
