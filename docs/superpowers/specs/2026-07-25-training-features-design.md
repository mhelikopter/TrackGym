# TrackGym Training Features — Design

**Datum:** 2026-07-25
**Status:** Vom Nutzer freigegeben
**Ziel:** Vier Trainings-Features für die persönliche Nutzung. Alles frei, keine Paywall. Spätere Kommerzialisierung (Pro-Unlock) bleibt möglich, ist aber nicht Teil dieses Designs.

## Scope

1. Übungs-Notizen
2. Volumen pro Muskelgruppe (Statistik)
3. Pausen-Timer mit Watch-Haptik
4. Watch-Workout-Session mit Live-Herzfrequenz (HealthKit)

**Explizit außerhalb des Scopes:** 1RM-Schätzung, PR-Timeline, iCloud-Sync, Phone-seitiger Health-Export ohne Watch-Session, Push-Notification-Fallback für den Timer, Timer-Skip auf der Watch, Themes, Lokalisierung, Onboarding.

## Ausgangslage

iOS-App (Deployment Target 18.0) mit SwiftData, watchOS-Companion (10.0) ohne eigene Persistenz. WatchConnectivity-Protokoll mit Ack (sendMessage + replyHandler), Dedup über Message-IDs, Application-Context-Replay mit `sentAt`-Stempeln. Xcode-16-Projekt mit ordnersynchronisierten Gruppen — neue Swift-Dateien werden automatisch Teil des jeweiligen Targets.

---

## F1: Übungs-Notizen

**Model:** Neues Feld `Exercise.notes: String?`. Optionales Feld, SwiftData migriert ohne Zutun. Leerstring wird beim Speichern zu `nil` normalisiert.

**UI:**
- `ActiveEntrySection` (aktives Training): einzeilige Notiz-Anzeige unter dem Übungsnamen, tippbar zum Bearbeiten (TextField). Änderungen speichern direkt am `@Bindable`-Model.
- `AddExerciseView`: Notiz-Feld beim Anlegen einer Übung.

**Backup:** `ExportExercise.notes: String?` — optional, alte Backups ohne Feld decodieren unverändert. Import übernimmt die Notiz verbatim.

---

## F2: Volumen pro Muskelgruppe

**Berechnung:** Neuer testbarer Helper `TrainingStatistics` (enum mit statischen Funktionen) in `TrackGym/Data/`:

```
volumeByMuscleGroup(entries: [WorkoutEntry], since: Date?) -> [(group: MuscleGroup, volumeKg: Double)]
```

- Zeiträume sind **rollierende Fenster**: Woche = letzte 7 Tage, Monat = letzte 30 Tage, Gesamt = alles (`since: nil`). Bewusst keine Kalenderwochen — einfacher und für den Balance-Check genauso aussagekräftig.
- Nur abgeschlossene Einträge (`entry.workout != nil`). Einträge ohne Übung (gelöschte Übung) fallen raus, da keine Muskelgruppe zuordenbar. `.unknown` erscheint als „Unbekannt", wenn vorhanden.
- Rückgabe in kg; die View rechnet in die Anzeige-Einheit um (bestehendes `WeightUnit`-Muster).

**UI:** Neuer Abschnitt „Volumen pro Muskelgruppe" in `OverallProgressView` (Fortschritt-Tab, Gesamt-Ansicht): Segmented-Picker Woche/Monat/Gesamt, horizontales Balkendiagramm (Charts, `BarMark`), absteigend nach Volumen sortiert, Gruppen mit 0 kg ausgeblendet.

**Tests:** Aggregation, Zeitraum-Filterung, Ausschluss unfertiger/übungsloser Einträge.

---

## F3: Pausen-Timer

**Einstellung:** `restTimerDuration` (Sekunden) via `@AppStorage`, Default 90, Bereich 0–300 in 15er-Schritten, 0 = deaktiviert. Neuer Abschnitt „Training" in `SettingsView`.

**Startauslöser (bei aktivierter Einstellung):**
- iPhone: Tippen auf „Satz hinzufügen" in `ActiveEntrySection` (separater Callback `onSetLogged`, nicht der bestehende `onSetsChanged`, der auch bei Löschungen feuert)
- Watch: erfolgreich gespeicherter Satz (`addSetFromWatch`)
- Jeder neue Satz startet den Timer neu (letzter gewinnt)

**Phone-State & UI:** `restEndDate: Date?` als `@State` in `ActiveWorkoutView`. Anzeige als Countdown-Zeile in der Timer-Section, berechnet über die vorhandene `TimelineView` (kein zusätzlicher Timer-Publisher). Überspringen-Button setzt `restEndDate = nil`. Nach Ablauf verschwindet die Zeile automatisch.

**Watch-Sync:** Das `activeExercise`-Payload erhält optional `restEndsAt: Double` (timeIntervalSince1970). Regel: Jedes Payload trägt den aktuell gültigen Endzeitpunkt oder lässt das Feld weg; die Watch ersetzt ihren lokalen Timer-Zustand bei jedem Payload vollständig (auch Löschung). Da nach jedem Satz-Log ohnehin ein Push erfolgt, braucht es keine eigene Message-Art.

**Watch-Verhalten:** Countdown in `WorkoutSessionView`; bei Ablauf `WKInterfaceDevice.play(.notification)` — nur wenn `workoutActive`. Die Haptik wird lokal auf der Watch terminiert (kein Timing über die Funkverbindung); die laufende Workout-Session (F4) hält die App dafür wach.

**Tests:** Payload-Parsing inkl. `restEndsAt` (Watch-Testsuite), Countdown-Randfälle (abgelaufener Endzeitpunkt wird ignoriert).

---

## F4: Watch-Workout-Session mit Herzfrequenz

**Capability:** HealthKit-Entitlement für das Watch-Target, `NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription` in der Watch-Info.plist. **Schritt 0 der Umsetzung: verifizieren, dass HealthKit mit dem kostenlosen Personal Team signiert.** Unabhängig davon degradiert das Feature zur Laufzeit sauber (siehe Fehlerbehandlung).

**Neue Komponente (Watch):** `WorkoutSessionController` (`@Observable`), besitzt `HKHealthStore`, `HKWorkoutSession`, `HKLiveWorkoutBuilder`:
- `requestAuthorization()` beim ersten Workout-Start — Schreiben: Workouts; Lesen: Herzfrequenz, Aktivkalorien
- `start()` wenn `workoutActive` von false auf true wechselt (beobachtet in der View-Schicht via `onChange`); Aktivitätstyp `.traditionalStrengthTraining`, `.indoor`
- Live-Metriken `heartRate` (BPM) und `activeEnergy` (kcal) als published Properties aus den Builder-Callbacks
- `end()` bei `workoutEnded` und bei `clearLocalState` — beendet Collection und speichert das Workout in HealthKit (zählt für Aktivitätsringe)

**UI:** Kopfzeile in `WorkoutSessionView`: Herz-Symbol + BPM, Flammen-Symbol + kcal. Ausgeblendet, solange keine Werte vorliegen.

**Fehlerbehandlung:** Verweigerte HealthKit-Berechtigung oder Session-Fehler blockieren nichts — das Workout-Tracking über WatchConnectivity funktioniert unverändert, es fehlen lediglich Puls/Kalorien/Ringe. Fehler werden geloggt (OSLog), keine modalen Alerts auf der Watch.

**Datenhoheit:** Das iPhone bleibt einzige Quelle für Sätze/Gewichte. HealthKit erhält nur Dauer, Herzfrequenz, Kalorien.

**Tests:** Simulator liefert synthetische Herzfrequenz (manueller Test); Realtest auf Apple Watch. Die Controller-Logik wird so geschnitten, dass Zustandsübergänge (idle → running → ended) ohne HealthKit-Store testbar sind, soweit praktikabel.

---

## Protokoll-Änderungen (zusammengefasst)

`activeExercise`-Payload: + `restEndsAt: Double?`. Beide Seiten parsen tolerant; fehlende Felder sind gültig (Abwärtskompatibilität mit sich selbst ist irrelevant, da beide Apps zusammen deployt werden — die Toleranz ist trotzdem Konvention im Projekt).

## Reihenfolge der Umsetzung

1. F1 Notizen (kleinster Eingriff, wärmt Backup-Pfad auf)
2. F2 Volumen-Statistik (reine Ergänzung, risikofrei)
3. F3 Pausen-Timer (Protokoll-Änderung)
4. F4 Watch-Session (Capability-Risiko zuerst isoliert verifizieren, dann Einbau)

Nach jedem Schritt: Build beider Schemes + Testlauf, ein Commit pro Feature.
