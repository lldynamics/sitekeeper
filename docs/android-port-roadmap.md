# Android Port Roadmap

This document defines the first practical Android route for the current iOS-first Sitekeeper app. The goal is to ship a useful Android client without destabilizing the existing SwiftUI app.

## Decision

- Build a separate native Android client under `android/`.
- Use Kotlin, Jetpack Compose, Material 3, Room, DataStore, WorkManager, CameraX, and Android's file picker/storage APIs.
- Reuse product concepts, workflows, model names, and backup/import formats. Do not attempt SwiftUI source-level reuse.
- Treat the existing iOS `BackupSnapshot` JSON shape as the v1 data contract until Android import/export is proven.
- Keep CAD viewing out of the Android MVP. Store and preview supported files first; evaluate DWG rendering separately.

Reference docs:
- Jetpack Compose: https://developer.android.com/compose
- Android architecture: https://developer.android.com/topic/architecture
- Room: https://developer.android.com/training/data-storage/room
- Android data and file storage: https://developer.android.com/training/data-storage
- WorkManager: https://developer.android.com/reference/androidx/work/WorkManager.html
- CameraX: https://developer.android.com/media/camera/camerax

## Current iOS Anchors

- `project.yml` defines only iOS targets: `sitekeeper-iOS`, widget extension, unit tests, and UI tests.
- `Sources/App/RootView.swift` defines the main product modules: dashboard, records, checklist, quick note, profile.
- `Sources/Shared/Services/BackupSnapshot.swift` is the best cross-platform exchange root.
- `Sources/Shared/Services/DataStore.swift` persists `sitekeeper.json` and still migrates the legacy `construction_toolbox.json`.
- `Sources/Shared/Services/ProjectModels.swift`, `ProjectDomainTypes.swift`, and `FinanceModels.swift` hold most portable domain models.
- `SiteKeeperCADKernel/` and `Sources/Shared/CADKernel/` are high-risk for Android and should not block the first Android release.

## MVP Scope

### P0: First Android Release

The first release should support the jobsite workflows that matter even without advanced platform extras.

- Local project list and project detail.
- Project create, edit, archive, and status tracking.
- Daily logs, photos metadata, safety/material/tomorrow-plan fields.
- Site todos with priority, issue type, due date, before/after photo references, and completion state.
- Progress tasks with start date, due date, completion, and note.
- Contacts linked to one or more projects.
- Materials, quotes, labor records, and project financial records.
- Project documents as metadata plus imported local files.
- Project drawings as metadata plus imported local files; PDF/image preview only in MVP.
- Quick notes with text and basic attachments.
- Local backup import/export compatible with the iOS v1 JSON shape.
- Settings needed for language, appearance, local backup, and data import.

### P1: Field Productivity

- CameraX-based watermark camera.
- Photo/video import for daily logs, material sheets, warehouse movements, and quick notes.
- Audio recording and playback for quick notes.
- Material price database, suppliers, user materials, and construction methods.
- Warehouse inbound/outbound movements.
- Document scan/OCR evaluation using ML Kit or a native scanner library.
- Android tablet/foldable adaptive layouts.

### P2: Advanced/Separate Track

- Android widgets.
- Cloud backup and sync policy parity.
- DWG/DXF rendering and CAD measurement parity.
- Cross-platform shared domain library with Kotlin Multiplatform.
- Deep app-to-app shortcuts and Android-specific integrations.

## Non-Goals For MVP

- No direct SwiftUI conversion.
- No wrapped `payload` backup format that iOS cannot read.
- No production DWG rendering promise until the Android CAD engine is selected and validated.
- No all-files storage permission unless a Play Store policy review proves it is unavoidable.
- No attempt to clone every iPad detail before phone workflows are useful.

## Android Architecture

Recommended module shape:

```text
android/
  app/
  core/
    model/
    database/
    datastore/
    file/
    backup/
    common-ui/
  feature/
    dashboard/
    projects/
    records/
    checklist/
    quicknote/
    profile/
```

Layering:

- UI: Compose screens and stateless components.
- Presentation: ViewModels expose immutable UI state and one-shot events.
- Domain: use cases for import/export, totals, overdue risk, finance metrics, and filtering.
- Data: Room DAOs, file storage, backup JSON codecs, DataStore preferences.

The Android app should use unidirectional data flow:

```text
Room/DataStore/FileStorage -> Repository -> UseCase -> ViewModel -> Compose UI
Compose events -> ViewModel -> UseCase -> Repository
```

## Data Contract V1

### Compatibility Rules

- Keep the backup JSON root flat, matching `BackupSnapshot`.
- Android must accept missing arrays as empty.
- Android must ignore unknown keys.
- Android must preserve UUID strings exactly.
- Android must preserve enum raw values exactly, including Chinese raw strings such as `进行中`, `高`, `收入`.
- Android must preserve money and quantity fields as strings, because iOS uses `NonNegativeNumberText`.
- Dates stay as strings in the current iOS formats: `yyyy-MM-dd` and `yyyy-MM-dd HH:mm`.
- Attachment fields keep file-name references; actual file bytes are handled by backup file arrays or external package contents.
- New metadata must be optional top-level fields, never a wrapper that hides the existing keys from iOS.

Proposed additive metadata fields for a later iOS patch:

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-05-16 10:30",
  "exportPlatform": "android",
  "projects": []
}
```

Current iOS decoders ignore unknown fields, so Android can write these only after verifying iOS import still succeeds. Android must also read backups without them.

### Root Collections

| JSON key | iOS source model | Android storage |
| --- | --- | --- |
| `projects` | `Project` | Room table |
| `dailyLogs` | `DailyLog` | Room table |
| `siteTodos` | `SiteTodo` | Room table |
| `progressTasks` | `ProgressTask` | Room table |
| `projectContacts` | `ProjectContact` | Room table |
| `projectDrawings` | `ProjectDrawing` | Room table + file storage |
| `projectDocuments` | `ProjectDocument` | Room table + file storage |
| `projectFinancialRecords` | `ProjectFinancialRecord` | Room table |
| `projectWarehouseMovements` | `ProjectWarehouseMovement` | Room table |
| `materialItems` | `MaterialItem` | Room table |
| `quoteItems` | `QuoteItem` | Room table |
| `laborRecords` | `LaborRecord` | Room table |
| `quickNotes` | `QuickNote` | Room table + attachment table |
| `templates` | `ProjectTemplate` | Room table |
| `materialPriceEntries` | `MaterialPriceEntry` | Room table |
| `materialSheetDrafts` | `MaterialSheetDraft` | Room table + child item table |
| `supplierProfiles` | `SupplierProfile` | Room table |
| `constructionMethods` | `ConstructionMethod` | Room table + child list tables or JSON columns |
| `userMaterials` | `UserMaterial` | Room table |
| `deletedUserMaterials` | `UserMaterial` | Room table or tombstone table |
| `favoriteMaterialKeys` | `[String]` | DataStore or Room table |
| `recentMaterialKeys` | `[String]` | DataStore or Room table |
| `hiddenPresetKeys` | `Set<String>` | DataStore or Room table |
| `photoFiles` | `PhotoBackupFile` | backup package only |
| `drawingFiles` | `DrawingBackupFile` | backup package only |
| `documentFiles` | `ProjectDocumentBackupFile` | backup package only |
| `quickNoteAttachmentFiles` | `QuickNoteAttachmentBackupFile` | backup package only |
| `paymentRecords` | legacy decode-only | import migration only |

### Core Entity Priorities

P0 entities:
- `Project`
- `DailyLog`
- `SiteTodo`
- `ProgressTask`
- `ProjectContact`
- `ProjectDocument`
- `ProjectDrawing`
- `ProjectFinancialRecord`
- `MaterialItem`
- `QuoteItem`
- `LaborRecord`
- `QuickNote`

P1 entities:
- `ProjectWarehouseMovement`
- `MaterialPriceEntry`
- `MaterialSheetDraft`
- `SupplierProfile`
- `ConstructionMethod`
- `UserMaterial`
- preference arrays and hidden preset keys

Import-only compatibility:
- `paymentRecords` maps to `ProjectFinancialRecord` when possible.

### Enum Strategy

Keep raw values stable in v1. Android may expose localized UI labels separately, but the stored/exported value must match iOS raw values.

Examples:

| Enum | Values |
| --- | --- |
| `ProjectStatus` | `进行中`, `暂停`, `已完成`, `已结算`, `已归档` |
| `PaymentStatus` | `未收款`, `部分收款`, `已收款` |
| `TodoPriority` | `高`, `中`, `低` |
| `TodoIssueType` | `安全`, `质量`, `材料`, `进度`, `其他` |
| `ProjectFinancialDirection` | `收入`, `支出` |
| `ProjectFinancialStatus` | `正式`, `草稿`, `已归档` |
| `ProjectDocumentCategory` | `请款资料`, `施工资料`, `发票`, `收据`, `合同`, `验收资料`, `其他资料` |
| `PhotoTag` | `现场`, `整改前`, `整改后`, `隐蔽工程`, `材料进场`, `完工验收` |

### File Storage Rules

- Store app-owned imported files in app-specific storage.
- Use Android's Storage Access Framework for user-selected import/export destinations.
- Store Room records with file-name references, not absolute paths.
- Maintain separate directories for photos, drawings, documents, and quick-note attachments.
- Export should package JSON plus referenced file bytes.
- Import should copy files into Android app storage and rewrite only local storage locations, not logical `fileName` identifiers.

## Migration Milestones

### M0: Contract Freeze

Deliverables:
- Android data contract tests against sample iOS backup JSON.
- Kotlin data classes for P0 root collections.
- JSON decoder that accepts missing arrays and unknown keys.
- Compatibility fixture committed under Android tests.

Done when:
- A sample iOS `sitekeeper.json` can decode in Android tests.
- Android can re-encode P0 data without losing ids, dates, enum raw strings, or numeric strings.

### M1: Android Skeleton

Deliverables:
- New `android/` Gradle project.
- Compose Material 3 theme.
- Navigation shell matching main modules.
- Room database and repositories for P0 entities.
- DataStore settings for language, appearance, and import state.

Done when:
- App launches on emulator.
- Project list reads from Room.
- Unit tests cover JSON -> Room import for projects.

### M2: Project Workflow MVP

Deliverables:
- Project list, filters, create/edit, status changes.
- Project detail with logs, todos, progress, contacts, finance summary.
- Basic empty states and form validation.

Done when:
- A user can create a project and add a daily log, todo, progress task, contact, and finance record.
- Data persists after app restart.

### M3: Backup Interop

Deliverables:
- Import iOS backup JSON.
- Export Android backup JSON in the same flat root shape.
- Attachment import/export for P0 file categories.

Done when:
- Android imports an iOS backup fixture.
- Android exports a backup that iOS can import in a local verification run.

### M4: Field Media

Deliverables:
- CameraX photo capture.
- Media import from system picker.
- Quick-note audio recording/playback.
- Document/file preview for common Android-supported formats.

Done when:
- Daily logs and todos can attach photos.
- Quick notes can attach audio/photo/file.
- Export includes referenced attachments.

### M5: Store Readiness

Deliverables:
- Privacy/Data Safety wording.
- Play Store icon, screenshots, app name, package id.
- Crash logging decision.
- Release signing and internal testing track.

Done when:
- Internal testing build installs cleanly.
- Data safety answers match actual local/offline behavior.

## Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| CAD rendering is not portable | Can delay release indefinitely | Keep CAD out of MVP; store files and preview supported formats first |
| iOS and Android backup formats drift | Import/export breaks | Treat `BackupSnapshot` v1 as contract; add compatibility fixtures |
| Enum raw values are Chinese strings | Future localization can break data | Store raw values exactly; localize only display labels |
| Numeric strings become numeric types | Precision/empty-field semantics change | Keep money, quantity, hours, and rates as strings in v1 |
| Android scoped storage surprises | File import/export bugs | Use app-specific storage plus SAF; avoid broad storage permission |
| Room schema over-normalization slows MVP | More migrations before product value | Normalize P0 relations; allow JSON columns for low-query nested lists |
| Cloud backup before local parity | Debug surface grows too early | Finish local backup interop first |

## Recommended Next Coding Step

Start with M0 and M1, not UI parity:

1. Create `android/` with a minimal Compose app.
2. Add Kotlin serialization data classes for `BackupSnapshot` P0 fields.
3. Add one iOS-generated backup fixture.
4. Add import tests for `projects`, `dailyLogs`, `siteTodos`, `materialItems`, `quoteItems`, `laborRecords`, and `projectFinancialRecords`.
5. Only then build the project list UI.

This keeps the Android port anchored to real existing data instead of becoming a disconnected prototype.
