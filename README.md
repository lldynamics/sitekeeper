# 工地掌柜 (iOS / iPadOS)

A SwiftUI toolbox for construction-site calculation, project records, quoting, daily logs, progress tracking, backup, and export.

Minimum OS: iOS 17.0+ / iPadOS 17.0+ (uses Swift Observation APIs).

Chinese guide: `README.zh-CN.md`

## Current Features

- Dashboard: quick access, pending material reminders, and recent project activity.
- Calculators: current, voltage drop with wire-size recommendation, conduit fill, cable tray fill, breaker selection, lighting estimate, concrete, rebar, tile, wall area, and unit conversion.
- Lists: material list, labor records, quote management, custom material library, and project-linked records.
- Projects: project list, business dashboard, project detail summary, editable progress tasks, calculation history, and enhanced daily logs.
- Daily logs: list/calendar views, project/date/search filters, safety and material notes, weather capture, and multiple photo attachments.
- Export and backup: CSV, PDF, Excel-compatible HTML, quote PDF export, full ZIP backup with original files, import merge/overwrite, iCloud backup/restore preview, and large-file ZIP64 streaming export.
- Data health: one-click checks for missing files, orphan project links, and invalid references.
- Widget: risk-priority project list (overdue/pending first), todo and stock snapshot, and sync timestamp.
- Release basics: generated app icon, privacy manifest, bundle ID, version/build number, shared test scheme, and unit tests.

## Quick Start

1. Use the full Xcode toolchain:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

2. Generate the Xcode project:

   ```sh
   xcodegen generate
   ```

3. Open and run:

   ```sh
   open sitekeeper.xcodeproj
   ```

4. Select the `sitekeeper-iOS` scheme and run on an iPhone or iPad simulator.

## One-Command Bootstrap

```sh
bash bootstrap.sh
```

## Verification

Find an available simulator UDID first (tests require a concrete device):

```sh
xcrun simctl list devices available
```

Build (app only):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -configuration Debug -destination 'id=<SIMULATOR_UDID>' build
```

Unit tests:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS -destination 'id=<SIMULATOR_UDID>'
```

UI tests:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project sitekeeper.xcodeproj -scheme sitekeeper-iOS-UITests -destination 'id=<SIMULATOR_UDID>'
```

Release preflight:

```sh
scripts/release/preflight.sh
```

Enable local pre-commit guards (one time):

```sh
scripts/dev/install_git_hooks.sh
```

## Project Layout

- `Sources/App`: app entry point and tab navigation.
- `Sources/Features`: feature views grouped by app tab.
- `Sources/Shared`: models, services, helpers, and reusable views.
- `Sources/Resources`: app resources, privacy manifest, and asset catalog.
- `Tests`: unit tests for conversion, quotes, backup compatibility, deletion, and engineering recommendations.

## Extending

- Add a calculator view under `Sources/Features/计算`, then register it in `CalculatorTabView.calcDefs`.
- Add shared persisted data in `DataStore.swift` and include it in backup/export when needed.
- Add reusable engineering formulas in `EngineeringCalculations.swift` and cover them with tests.
