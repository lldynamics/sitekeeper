#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[backup-contract-boundary] FAIL: $1" >&2
  exit 1
}

source "$ROOT_DIR/scripts/lib/policy_search.sh"

require_file() {
  local description="$1"
  local path="$2"

  [[ -f "$path" ]] || fail "$description is missing: $path"
}

reject_file() {
  local description="$1"
  local path="$2"

  [[ ! -e "$path" ]] || fail "$description must not be present: $path"
}

require_pattern() {
  local description="$1"
  local path="$2"
  local pattern="$3"

  require_file "$description" "$path"
  if ! policy_search -q --fixed-strings "$pattern" "$path"; then
    fail "$description is missing expected marker '$pattern' in $path"
  fi
}

reject_file "Sample data fixture in production resources" "Sources/Resources/Fixtures/SampleDataFixture.json"
require_file "Sample data test fixture" "Tests/Fixtures/SampleDataFixture.json"

require_pattern "BackupSnapshot schema version" "Sources/Shared/Services/Backups/BackupSnapshot.swift" "static let currentSchemaVersion = 3"
require_pattern "BackupSnapshot strict schema gate" "Sources/Shared/Services/Backups/BackupSnapshot.swift" "guard Self.supportedSchemaVersions.contains(schemaVersion)"
require_pattern "BackupSnapshot drawing metadata" "Sources/Shared/Services/Backups/BackupSnapshot.swift" "var projectDrawings: [ProjectDrawing]"
require_pattern "BackupSnapshot drawing file payload" "Sources/Shared/Services/Backups/BackupSnapshot.swift" "var drawingFiles: [DrawingBackupFile]"
require_pattern "BackupSnapshot drawing metadata decode" "Sources/Shared/Services/Backups/BackupSnapshot.swift" "projectDrawings = try container.decodeIfPresent([ProjectDrawing].self, forKey: .projectDrawings) ?? []"
require_pattern "BackupSnapshot drawing file decode" "Sources/Shared/Services/Backups/BackupSnapshot.swift" "drawingFiles = try container.decodeIfPresent([DrawingBackupFile].self, forKey: .drawingFiles) ?? []"

require_pattern "ProjectDrawing availability status field" "Sources/Shared/Models/Projects/ProjectDomainDrawingTypes.swift" "var fileAvailabilityStatus: ProjectDrawingFileAvailabilityStatus"
require_pattern "ProjectDrawing availability checked field" "Sources/Shared/Models/Projects/ProjectDomainDrawingTypes.swift" "var fileAvailabilityCheckedAt: BusinessDateValue"
require_pattern "ProjectDrawing external failure reason field" "Sources/Shared/Models/Projects/ProjectDomainDrawingTypes.swift" "var externalOpenFailureReason: String"
require_pattern "ProjectDrawing external failure time field" "Sources/Shared/Models/Projects/ProjectDomainDrawingTypes.swift" "var externalOpenFailedAt: BusinessDateValue"
require_pattern "ProjectDrawing availability default" "Sources/Shared/Models/Projects/ProjectDomainDrawingTypes.swift" "fileAvailabilityStatus: ProjectDrawingFileAvailabilityStatus = .unknown"
require_pattern "ProjectDrawing availability decode" "Sources/Shared/Models/Projects/ProjectDomainDrawingTypes.swift" "forKey: .fileAvailabilityStatus"
require_pattern "ProjectDrawing file availability enum" "Sources/Shared/Models/Projects/ProjectDomainDrawingTypes.swift" "enum ProjectDrawingFileAvailabilityStatus"

require_pattern "CSV export drawing status key" "Sources/Shared/Services/Reporting/ReportBuilder+CSVSections.swift" "file_availability_status_key"
require_pattern "CSV export external failure" "Sources/Shared/Services/Reporting/ReportBuilder+CSVSections.swift" "external_open_failure_reason"
require_pattern "Project package drawing register" "Sources/Shared/Services/Reporting/ReportBuilder+ProjectDeliverySupport.swift" "projectCurrentDrawingRegisterTSVText"
require_pattern "Project package missing drawing check" "Sources/Shared/Services/Reporting/ReportBuilder+ProjectDeliverySupport.swift" "projectDrawingMissingCheckTSVText"
require_pattern "Project package drawing status" "Sources/Shared/Services/Reporting/ReportBuilder+ProjectDeliverySupport.swift" "file_availability_status"
require_pattern "Project package external failure" "Sources/Shared/Services/Reporting/ReportBuilder+ProjectDeliverySupport.swift" "external_open_failure_reason"

require_pattern "Backup contract rejects schema-less legacy backup" "Tests/BackupContractCompatibilityTests.swift" "legacyBackupWithoutSchemaVersionIsRejected"
require_pattern "Backup manifest and metadata schema alignment test" "Tests/BackupContractCompatibilityTests.swift" "backupManifestAndMetadataRoundTripShareCurrentSchema"
require_pattern "Backup manifest metadata path contract test" "Tests/BackupContractCompatibilityTests.swift" "backupManifestRejectsUnexpectedMetadataPath"
require_pattern "Backup contract ignores unknown future fields" "Tests/BackupContractCompatibilityTests.swift" "backupImportIgnoresFutureFieldsAndPreservesKnownDrawingFields"
require_pattern "Backup contract preserves drawing availability defaults" "Tests/BackupContractCompatibilityTests.swift" "fileAvailabilityStatus == .unknown"
require_pattern "Backup metadata persistence fault injection test" "Tests/BackupErrorRecoveryTests.swift" "backupImportTransactionRollsBackFilesWhenMetadataPersistFails"
require_pattern "Backup export clear restore rehearsal" "Tests/BackupRecoveryRehearsalTests.swift" "backupExportClearRestoreRehearsalPersistsMetadataAndFiles"
require_pattern "Backup ZIP path traversal test" "Tests/BackupErrorRecoveryTests.swift" "backupPrepareRestoreRejectsZipSlipEntryAndCleansTempStage"
require_pattern "Backup ZIP duplicate entry test" "Tests/BackupErrorRecoveryTests.swift" "backupPrepareRestoreRejectsDuplicateEntryAndCleansTempStage"
require_pattern "Backup ZIP checksum test" "Tests/BackupErrorRecoveryTests.swift" "backupPrepareRestoreRejectsCorruptedEntryChecksumAndCleansTempStage"
require_pattern "Backup ZIP uncompressed size limit test" "Tests/BackupErrorRecoveryTests.swift" "backupPrepareRestoreRejectsForgedOversizedUncompressedEntry"
require_pattern "Drawing availability default test" "Tests/DrawingFileAvailabilityTests.swift" "projectDrawingDecodesLegacyAvailabilityDefaults"
require_pattern "ReportBuilder drawing status export test" "Tests/ReportBuilderTests.swift" "file_availability_status_key"

require_pattern "Android backup contract sync rule" "docs/android-port-roadmap.md" 'When `BackupSnapshot.currentSchemaVersion`, manifest rules, or backup paths change'
require_pattern "Android drawing metadata collection" "docs/android-port-roadmap.md" '| `projectDrawings` | `ProjectDrawing` | Room table + file storage |'
require_pattern "Android drawing file collection" "docs/android-port-roadmap.md" '| `drawingFiles` | `DrawingBackupFile` | backup package only |'
require_pattern "Android ProjectDrawing availability field" "docs/android-port-roadmap.md" '`fileAvailabilityStatus`'
require_pattern "Android ProjectDrawing external failure field" "docs/android-port-roadmap.md" '`externalOpenFailureReason`'

echo "[backup-contract-boundary] PASS: backup schema, drawing file contract, exports, tests, and Android sync notes remain aligned."
