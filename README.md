# 工地掌柜 (iOS / iPadOS)

A SwiftUI toolbox for construction-site calculation, project records, quoting, daily logs, progress tracking, backup, and export.

Minimum OS: iOS 17.0+ / iPadOS 17.0+ (uses Swift Observation APIs).

Chinese guide: `README.zh-CN.md`

## Current Features

- Dashboard: quick access, pending material reminders, and recent project activity.
- Calculators: current, voltage drop with wire-size recommendation, conduit fill, cable tray fill, breaker selection, concrete, rebar, tile, wall area, and unit conversion.
- Lists: material list, labor records, quote management, custom material library, and project-linked records.
- Projects: project list, business dashboard, project detail summary, editable progress tasks, calculation history, and enhanced daily logs.
- Daily logs: list/calendar views, project/date/search filters, safety and material notes, weather capture, and multiple photo attachments.
- Export and backup: CSV, PDF, HTML webpage reports (.html), quote PDF export, full ZIP backup with original files, import merge/overwrite, iCloud backup/restore preview, and large-file ZIP64 streaming export.
- Data health: one-click checks for missing files, orphan project links, and invalid references.
- Widget: risk-priority project list (overdue/pending first), todo and stock snapshot, and sync timestamp.
- Release basics: generated app icon, privacy manifest, bundle ID, version/build number, shared test scheme, and unit tests.

## Data Safety and Confirmation Flows

- Backup restore uses a persistent transaction journal. If a restore is interrupted, the recovery package and journal are retained so the app can recover on the next load. Data clearing, storage cleanup, and other maintenance actions stay unavailable until loading and recovery finish. Local and cloud exports also hold a read lease that blocks cleanup and restore until archive reading finishes.
- An iCloud backup is recorded as uploaded only after both its ZIP archive and checksum file are confirmed uploaded. Retention can keep the latest 3, 5, 10, or 20 confirmed uploads; pruning uses confirmed upload status when the backup list is refreshed, while pending and failed uploads are retained. These rules describe the app's upload-status handling and do not replace checking iCloud availability on the device.
- Quote generation requires an explicit material pricing choice: use the stored material price as a cost reference, set one customer-facing price, or leave prices blank for later. Writing a quote into a project contract first shows the selected confirmed quote version and calculated amount; if the source quote changes, the preview refreshes and must be confirmed again.
- Older labor records whose unit cannot be determined are marked for confirmation instead of treating their values as hours or workdays automatically. They must be edited or batch-confirmed before quote generation; confirmation assigns the unit without converting the saved quantity or amount.

## Quick Start

1. Use Xcode 27.1 (the same version checked by CI and release preflight):

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

Ordinary Debug builds skip the full release boundary scans. To opt in, set
`SITEKEEPER_RUN_BUILD_GUARDS=1`; Release builds and release preflight enforce all guards. Search guards prefer
ripgrep and fall back to the system `grep -E` when it is unavailable. They do not depend on a
Codex application installation.

Release preflight:

```sh
scripts/release/preflight.sh
```

Install the same checksum-verified tool versions used by CI (XcodeGen 2.46.0, SwiftFormat 0.61.1, and SwiftLint 0.63.2), then run the Swift checks:

```sh
tools_dir="${TMPDIR:-/tmp}/sitekeeper-tools"
scripts/release/install_ci_tools.sh "$tools_dir"
export PATH="$tools_dir:$PATH"
scripts/dev/check_swift_format.sh
scripts/dev/check_swift_lint.sh
scripts/dev/format_swift.sh
```

Enable local pre-commit guards (one time):

```sh
scripts/dev/install_git_hooks.sh
```

## Project Layout

- `Sources/App`: app entry point and tab navigation.
- `Sources/Features`: English feature paths (`Calculators`, `Checklists`, `Dashboard`, `QuickNotes`, `Profile`, `Projects`), grouped further by business domain.
- `Sources/Shared/Models`: shared domain models.
- `Sources/Shared/Services`: persistence, backups, archiving, storage, reporting, search, and other focused services.
- `Sources/Shared/Helpers` and `Views`: helpers and reusable components.
- `Sources/Resources`: app resources, privacy manifest, and asset catalog.
- `Tests`: unit tests for conversion, quotes, backup compatibility, deletion, and engineering recommendations.

## Extending

- Add a calculator view under `Sources/Features/Calculators`, then add its metadata and destination to `CalculatorDestination.swift`. The toolbox uses this registry through `QuickToolViews.swift`; a separate top-level calculator tab is not needed.
- Add shared persisted data in `DataStore.swift` and include it in backup/export when needed.
- Add reusable engineering formulas in `EngineeringCalculations.swift` and cover them with tests.

See [source organization and extension rules](docs/architecture/source-organization.md) for domain boundaries, file splitting, and the ZIP adapter contract.
