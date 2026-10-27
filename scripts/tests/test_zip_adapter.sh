#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sitekeeper-zip-tests.XXXXXX")"
trap 'rm -rf "$TASK_DIR"' EXIT
# Optional offline checkout must be the same fixed revision as Package.resolved.
if [[ -n "${SITEKEEPER_ZIPFOUNDATION_PATH:-}" ]]; then
  [[ "$(git -C "$SITEKEEPER_ZIPFOUNDATION_PATH" rev-parse HEAD)" == 22787ffb59de99e5dc1fbfe80b19c97a904ad48d ]]
  git -C "$SITEKEEPER_ZIPFOUNDATION_PATH" diff --quiet
fi
mkdir -p "$TASK_DIR/Sources/sitekeeper" "$TASK_DIR/Tests/ArchiveTests"
cp "$ROOT_DIR"/Sources/Shared/Services/Archiving/*.swift "$TASK_DIR/Sources/sitekeeper/"
cp "$ROOT_DIR/Sources/Shared/Services/Backups/BackupArchiveLimits.swift" "$TASK_DIR/Sources/sitekeeper/"
cp "$ROOT_DIR/Tests/ZipArchiveInteropTests.swift" "$TASK_DIR/Tests/ArchiveTests/"
cat > "$TASK_DIR/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import Foundation
import PackageDescription
let dependency: Package.Dependency
if let path = ProcessInfo.processInfo.environment["SITEKEEPER_ZIPFOUNDATION_PATH"] {
    dependency = .package(name: "ZIPFoundation", path: path)
} else {
    dependency = .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
}
let package = Package(
    name: "SitekeeperArchiveValidation", platforms: [.macOS(.v14)], dependencies: [dependency],
    targets: [
        .target(name: "sitekeeper", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ArchiveTests", dependencies: ["sitekeeper"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
SWIFT
# Host-only ports isolate archive code from app preferences and production storage.
# Backup limits, ZIP adapter sources and regression fixtures above are copied verbatim.
cat > "$TASK_DIR/Sources/sitekeeper/HostPorts.swift" <<'SWIFT'
import Foundation
enum AppLocalization { static func string(_ key: String) -> String { key } }
enum BackupArchiveService { static let metadataPath = "data/backup.json"; static let manifestPath = "manifest.json" }
enum TransferLimitPolicy { static let maxImportBytes = 64 * 1024 * 1024 }
enum FileOps {
    enum Category { case zipArchive }
    struct Context { init(event: String, category: Category, source: String) {} }
    static func removeIfExists(at url: URL, context: Context) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }
}
SWIFT
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_DIR/swift-cache"
swift test --package-path "$TASK_DIR" --scratch-path "$TASK_DIR/build" \
  --cache-path "$TASK_DIR/cache" --config-path "$TASK_DIR/config" --security-path "$TASK_DIR/security" --disable-sandbox
