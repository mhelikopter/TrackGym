# TrackGym

A native iOS and watchOS workout tracker. Plan your training on the iPhone, log sets from the Apple Watch in real time.

![Platforms](https://img.shields.io/badge/platforms-iOS%2018%20%7C%20watchOS%2010-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## What it does

- **Workout planning (iPhone)** — Build training plans from a built-in catalogue of ~80 exercises (German names), grouped by muscle group and equipment type. Add your own custom exercises.
- **Live tracking (iPhone)** — Start a plan, log sets with weight and reps, see the previous workout's numbers next to each exercise, run a built-in timer.
- **Watch companion (Apple Watch)** — While a workout is running on the phone, the watch shows the current exercise and lets you log sets via the Digital Crown. Sets sync back to the phone instantly.
- **Progress (iPhone)** — Charts for personal records and total volume per exercise or overall.
- **Backup** — Export and import all data as JSON.

The Apple Watch app is deliberately focused on logging only. Plan setup, history and configuration happen on the iPhone.

## Requirements

- Xcode 16 or newer
- iOS 18.0+ on the iPhone
- watchOS 10.0+ on the paired Apple Watch
- A real device pair is recommended for the WatchConnectivity flow; simulator works for the iOS app alone.

## Build

```bash
git clone https://github.com/<your-user>/TrackGym.git
cd TrackGym
open TrackGym.xcodeproj
```

Pick the **TrackGym** scheme for iPhone or **TrackGym Watch App Watch App** for the watch. Hit Run.

From the command line:

```bash
# iPhone (also embeds and builds the watch target)
xcodebuild -project TrackGym.xcodeproj \
  -scheme TrackGym \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build

# Watch (standalone)
xcodebuild -project TrackGym.xcodeproj \
  -scheme 'TrackGym Watch App Watch App' \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug build
```

## Run the tests

```bash
DEST=$(xcrun simctl list devices available \
  | sed -nE 's/.*iPhone.*\(([0-9A-F-]{36})\) \(Shutdown\).*/\1/p' \
  | head -1)

xcodebuild test \
  -project TrackGym.xcodeproj \
  -scheme TrackGym \
  -destination "id=$DEST"
```

## Architecture

- **SwiftUI** for both apps.
- **SwiftData** for persistence on iPhone (`Exercise`, `Workout`, `WorkoutEntry`, `WorkoutSet`, `WorkoutPlan`).
- **WatchConnectivity** for phone ↔ watch messaging. Active exercise state is pushed via `updateApplicationContext` (replayed on watch launch) plus a low-latency `sendMessage`; sets logged on the watch go through an acknowledged `sendMessage` with a queued `transferUserInfo` fallback, deduplicated by message id on the phone. The watch holds no persistent workout state of its own.
- **Charts** framework for the progress views.

```
TrackGym/                          # iOS app
├── Models/                        # @Model types
├── Data/                          # Seeding, JSON import/export, WCSession (phone side)
└── Views/                         # SwiftUI screens
TrackGym Watch App Watch App/      # watchOS app — minimal, tracking only
```

## Roadmap

- Schema migration to UUID-based exercise IDs for safer cross-device imports
- More charts (1RM estimation, per-muscle-group volume)
- Localization (currently German-only UI)
- iCloud sync

## License

[MIT](LICENSE) © 2026 Maximilian Ehling
