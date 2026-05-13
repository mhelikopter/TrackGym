import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum AppColorScheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: "Geräteeinstellung"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var icon: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum WeightUnit: String, CaseIterable {
    case kg = "kg"
    case lbs = "lbs"

    var displayName: String {
        switch self {
        case .kg: "Kilogramm (kg)"
        case .lbs: "Pfund (lbs)"
        }
    }

    var short: String { rawValue }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appColorScheme") private var appColorScheme: String = AppColorScheme.system.rawValue
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.kg.rawValue
    @State private var showingDeleteAll = false
    @State private var showingDeleteProgress = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingImportConfirmation = false
    @State private var importFileURL: URL?
    @State private var exportData: Data?
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private var selectedScheme: AppColorScheme {
        AppColorScheme(rawValue: appColorScheme) ?? .system
    }

    private var selectedUnit: WeightUnit {
        WeightUnit(rawValue: weightUnit) ?? .kg
    }

    var body: some View {
        Form {
            Section("Erscheinungsbild") {
                ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                    Button {
                        appColorScheme = scheme.rawValue
                    } label: {
                        HStack {
                            Label(scheme.displayName, systemImage: scheme.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedScheme == scheme {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section("Einheiten") {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Button {
                        weightUnit = unit.rawValue
                    } label: {
                        HStack {
                            Text(unit.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedUnit == unit {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    prepareExport()
                } label: {
                    Label("Daten exportieren", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("Daten importieren", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Exportiert alle Daten als JSON-Datei. Beim Import werden bestehende Daten ersetzt.")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteProgress = true
                } label: {
                    Label("Fortschritte löschen", systemImage: "chart.line.downtrend.xyaxis")
                }

                Button(role: .destructive) {
                    showingDeleteAll = true
                } label: {
                    Label("Alle Daten löschen", systemImage: "trash")
                }
            } header: {
                Text("Daten")
            } footer: {
                Text("\"Fortschritte löschen\" entfernt alle gespeicherten Trainings. Pläne und Übungen bleiben erhalten.\n\"Alle Daten löschen\" entfernt alles. Standard-Übungen werden beim nächsten Start wiederhergestellt.")
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showingExporter,
            document: JSONDocument(data: exportData ?? Data()),
            contentType: .json,
            defaultFilename: "TrackGym-Backup"
        ) { result in
            switch result {
            case .success:
                alertMessage = "Daten erfolgreich exportiert."
                showingAlert = true
            case .failure(let error):
                alertMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
                showingAlert = true
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                importFileURL = url
                showingImportConfirmation = true
            case .failure(let error):
                alertMessage = "Datei konnte nicht geladen werden: \(error.localizedDescription)"
                showingAlert = true
            }
        }
        .confirmationDialog(
            "Daten importieren?",
            isPresented: $showingImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Importieren und ersetzen", role: .destructive) {
                performImport()
            }
            Button("Abbrechen", role: .cancel) {
                importFileURL = nil
            }
        } message: {
            Text("Alle bestehenden Daten werden durch die importierten Daten ersetzt.")
        }
        .confirmationDialog(
            "Fortschritte löschen?",
            isPresented: $showingDeleteProgress,
            titleVisibility: .visible
        ) {
            Button("Fortschritte löschen", role: .destructive) {
                deleteProgress()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle gespeicherten Trainings und Einträge werden gelöscht. Pläne und Übungen bleiben erhalten.")
        }
        .confirmationDialog(
            "Alle Daten löschen?",
            isPresented: $showingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Alle Daten löschen", role: .destructive) {
                deleteAllData()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Trainings, Pläne und eigene Übungen werden unwiderruflich gelöscht.")
        }
        .alert("Info", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Export / Import

    private func prepareExport() {
        do {
            exportData = try DataExporter.exportData(context: modelContext)
            showingExporter = true
        } catch {
            alertMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func performImport() {
        guard let url = importFileURL else { return }
        defer { importFileURL = nil }

        do {
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "Kein Zugriff auf die Datei."
                showingAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = try Data(contentsOf: url)
            try DataExporter.importData(from: data, context: modelContext)
            alertMessage = "Daten erfolgreich importiert."
            showingAlert = true
        } catch {
            alertMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    // MARK: - Delete

    private func deleteProgress() {
        do {
            try deleteAll(WorkoutSet.self)
            try deleteAll(WorkoutEntry.self)
            try deleteAll(Workout.self)
            try modelContext.save()
            alertMessage = "Fortschritte gelöscht."
            showingAlert = true
        } catch {
            alertMessage = "Löschen fehlgeschlagen: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func deleteAllData() {
        do {
            try deleteAll(WorkoutSet.self)
            try deleteAll(WorkoutEntry.self)
            try deleteAll(Workout.self)
            try deleteAll(WorkoutPlan.self)
            try deleteAll(Exercise.self)
            try modelContext.save()
            DefaultExercises.resetSeedFlag()
            DefaultExercises.seedDefaultExercises(context: modelContext)
            try modelContext.save()
            alertMessage = "Alle Daten gelöscht."
            showingAlert = true
        } catch {
            alertMessage = "Löschen fehlgeschlagen: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items { modelContext.delete(item) }
    }
}

// MARK: - JSON File Document

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
