# 工地掌柜 (iOS / iPadOS)

A SwiftUI toolbox for construction-site calculation, project records, quoting, daily logs, progress tracking, backup, and export.

Requires iOS 17.0+ / iPadOS 17.0+.

English | [简体中文](README.zh-CN.md)

This repository is available for source inspection with rights reserved; it is
not offered under an open-source license. See [COPYRIGHT.md](COPYRIGHT.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Download

Install **工地掌柜** for iPhone or iPad from the [App Store (United States)](https://apps.apple.com/us/app/%E5%B7%A5%E5%9C%B0%E6%8E%8C%E6%9F%9C/id6766023111?uo=4) or the [Hong Kong storefront](https://apps.apple.com/hk/app/%E5%B7%A5%E5%9C%B0%E6%8E%8C%E6%9F%9C/id6766023111?uo=4). Requires iOS 17.0 or iPadOS 17.0 or later. No app account or registration is required.

**Regional availability — 30 October 2026:** version 1.0.4 is listed in the US and Hong Kong storefronts. It is currently unavailable in the mainland China App Store while the required ICP filing information is incomplete. Availability depends on your Apple Account's storefront; check its App Store listing before downloading.

## Get started in 3 steps

1. **Create a project.** Open **Projects → New Project**, enter the project name, add other details as needed, and select **Create**.
2. **Save your first record.** Open the project and choose **Add Record → New Transaction** to record income or an expense. Use **New Material** or **Write Daily Log** for materials and site notes.
3. **Preview and share.** Open **More Actions → Site reports and checks → Daily and weekly site reports → Preview text PDF**. Review the project, dates and content, then choose whether to share.

**Keep a backup:** open **My Profile → Data Management → Backup & Restore** and choose **Export Full Backup ZIP** under **Local Backup**. On iPad, a **Create Local Backup ZIP** shortcut is also available. Records are stored locally by default. Optional iCloud backup and restore is for your own Apple ID; it is not real-time team collaboration.

## What's improved in 1.0.4

- Clearer project income, expenses, outstanding payments, and material and labor cost figures, with calculation notes and review prompts.
- Refined quotation filters, totals, and amount explanations in exported PDFs.
- Improved field navigation and cancellation with the iPad floating keyboard.
- Better filtering and position retention in to-do and progress lists on iPhone and iPad.
- Selecting **Cost** again now returns to that section after manually scrolling an iPad project detail page.

See the [App Store version history](https://apps.apple.com/us/app/%E5%B7%A5%E5%9C%B0%E6%8E%8C%E6%9F%9C/id6766023111?uo=4) for the published release notes. The source-build instructions below are for developers.

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

## Build from source (developers)

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

## Validation records and repository history

Private validation reports, screenshots, backups, and offline data deliveries
are retained separately and excluded from the public repository. Their absence
does not mean a test passed; use the verification commands above for the source
version you are reviewing.

Repository history was sanitized before publication to remove legacy LibreDWG
vendor files and private validation records. Older commits may no longer be
buildable after this removal. Re-clone after the history rewrite; merging or
pushing an old clone can restore removed history. Original history and evidence
are retained privately by the maintainer.
