# Sitekeeper Android

This is the native Android port workspace for Sitekeeper.

## Current Scope

- `:app`: minimal Jetpack Compose shell for the Android client.
- `:core:model`: Kotlin data contract for the first `BackupSnapshot` interop pass.
- `:core:database`: Room database slice for project, progress, drawing, quote, labor, warehouse, daily log, site todo, finance, material, contact, document, and quick note data.
- `:core:model` tests: decode and re-encode a P0 iOS-style backup fixture.
- `:app` JVM tests: cover backup package preflight rules for document attachment mismatches.
- Home tab: shows a risk summary, risk project list, and recent project shortcuts.
- Project tab: reads seeded project records from Room through the P0 backup JSON decoder.
- Project tab: supports local project creation backed by Room.
- Project tab: filters projects by active, archived, or all; active projects are shown by default.
- Project tab: searches by project name, location, or manager and sorts by latest activity, name, or expected finish date.
- Project tab: shows risk hints for overdue todos, due income, and unarrived materials.
- Calculator tab: supports concrete volume/material estimate, wall area, floor tile quantity, current, voltage drop, and unit conversion with tested formula helpers.
- Material library tab: supports material price entries, reference price status, categories, supplier profiles, preset seed data, edit/delete actions, and backup import/export for iOS `materialPriceEntries` and `supplierProfiles`.
- Method library tab: supports construction methods with trade/status filters, tutorial body, procedure steps, quality checklist, safety checklist, preset seed data, edit/delete actions, and backup import/export for iOS `constructionMethods`.
- Project detail: opens from the project list, shows linked daily logs plus open site todos, and supports adding logs and todos locally.
- Project detail: daily logs, site todos, and project documents can link to construction methods; linked method IDs round-trip through backup JSON.
- Project detail: shows a generated project timeline that combines logs, todos, progress, finance, materials, documents, drawings, quotes, labor, and warehouse movements.
- Project detail: exports a project delivery ZIP package through Android document picker with a Markdown report, file manifest, archived project documents, drawing files, and site photos; before export it shows a delivery preflight with actual packaged file counts and missing-file details.
- Project detail: supports progress tasks with start date, due date, completion, edit, delete, and done/reopen actions.
- Project detail: supports project contacts with add, edit, delete, phone/company/note fields, and backup import/export.
- Project detail: supports project document metadata with add, edit, delete, category/file/page/amount/note fields, private local file archive/pick/open/delete, archive status checks, missing-file warnings, and backup package import/export.
- Project detail: supports project drawing metadata and local drawing archives with add, edit, delete, pick, open, file name/type, version, related date, issue status, issue note, backup package export, and backup package restore.
- Project detail: supports quote items and labor records with add, edit, delete, quote status, confirmation date, team/work type, and labor settlement actions.
- Project detail: supports warehouse movements with inbound/outbound type, material/spec/unit/quantity, counterparty, handler, stock summary, negative-stock count, and backup import/export.
- Finance and material slices: project detail shows income/expense totals, financial records, and material procurement status.
- Project detail: supports editing existing projects, progress tasks, logs, todos, quote items, labor records, warehouse movements, financial records, and material items while preserving hidden backup fields.
- Project detail: supports local photo archive links for daily logs and todo before/after rectification photos, including pick, open, remove, backup package export, and backup package restore.
- Project detail: supports archiving/restoring projects and confirmed deletion for logs, todos, financial records, and material items.
- Checklist tab: aggregates todos across projects with overdue/status, priority, owner, project, and text filtering; rows support open project, edit, delete, and done/reopen.
- Notes tab: supports local quick notes with project links, search, edit, delete, local attachment pick/open/remove, and backup import/export for quick note metadata plus attachment files.
- Profile tab: previews backup record counts, supports merge import and replace import, keeps legacy JSON import compatibility, exports ZIP backup packages with `backup.json`, `data/backup.json`, archived project document files, archived photo files, archived drawing files, and archived quick note attachment files; preflights attachment/document/photo/drawing/quick-note attachment mismatches before import, and can run local data health checks for missing/orphaned documents, photos, drawings, and quick note attachments, including missing-item detail rows, project jump links, and project整改待办 generation for missing originals.

## Build

This workspace expects JDK 17. Use the checked-in Gradle wrapper from this directory.

```sh
cd android
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:model:test
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug
```

Current local verification:

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :core:model:test :app:testDebugUnitTest :app:assembleDebug --no-daemon
```

This passed after installing Homebrew `openjdk@17`, `gradle`, `android-commandlinetools`, `platforms;android-36`, `build-tools;36.0.0`, and `platform-tools`.

To install and launch the debug APK on a connected device:

```sh
./scripts/check_debug_install.sh
```

Manual release checks are tracked in `QA_CHECKLIST.md`.
