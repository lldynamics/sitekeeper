#!/usr/bin/env python3
"""Run bounded Foundation-only synthetic cases. Never opens an app or business store."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path)
parser.add_argument("--no-nested-sandbox", action="store_true",
                    help="For managed environments that already sandbox the process and reject sandbox-exec nesting")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
dest = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="sitekeeper-practical-"))
if args.output:
    dest.mkdir(parents=True, exist_ok=False)
src = dest / "Sources/sitekeeper"
tests = dest / "Tests/CoreTests"
src.mkdir(parents=True)
tests.mkdir(parents=True)
manifest = {}

def save_source(path, data=None, extracted=False):
    original = path.read_bytes()
    data = original if data is None else data
    name = f"{len(manifest):03}_{path.name}"
    (src / name).write_bytes(data)
    manifest[str(path.relative_to(root))] = {
        "source_sha256": hashlib.sha256(original).hexdigest(),
        "compiled_sha256": hashlib.sha256(data).hexdigest(), "extracted": extracted,
    }

for path in sorted((root / "Sources/Shared/Models").rglob("*.swift")):
    data = path.read_bytes()
    if path.name == "CommonMaterial.swift":
        data = data[:data.index(b"enum MaterialLibrary {")]
    save_source(path, data, data != path.read_bytes())
for name in ["DecimalFieldStorage.swift", "DecimalValueObjects.swift", "ExactDecimalCoefficient.swift",
             "NumericInputSupport.swift", "DataValueParser.swift", "CodableEnumFallbacks.swift",
             "BusinessDateValue.swift", "Formatters.swift", "AppPolicyAndBrand.swift"]:
    path = root / "Sources/Shared/Helpers" / name
    data = path.read_bytes()
    if name == "AppPolicyAndBrand.swift":
        data = data[:data.index(b"\nenum AppPolicy")]
    save_source(path, data, data != path.read_bytes())
for relative in [
    "Sources/Shared/Services/Finances/BusinessWorkflowStore.swift",
    "Sources/Shared/Services/Finances/ProjectFinancialMetrics.swift",
    "Sources/Shared/Services/Finances/ProjectPaidAmountExplanation.swift",
    "Sources/Shared/Services/Finances/BusinessWorkflowError.swift",
    "Sources/Shared/Services/Projects/ProjectChangeOrderService.swift",
    "Sources/Shared/Services/Projects/MaterialFollowUpSummary.swift",
    "Sources/Shared/Services/Reporting/ProjectFieldReport.swift",
    "Sources/Shared/Services/Reporting/ReportBuilder+ChangeOrder.swift",
    "Sources/Shared/Services/Backups/BackupSnapshot.swift",
    "Sources/Shared/Services/Backups/Cloud/CloudBackupPolicy.swift",
    "Sources/Features/Projects/Drafts/SiteTodoFormDraft.swift",
]:
    path = root / relative
    if path.name == "CloudBackupPolicy.swift":
        data = path.read_bytes().split(b"\nenum CloudBackupAutoInterval", 1)[0]
        save_source(path, data, True)
    else:
        save_source(path)

# Exclude only the DataStore entry point, retaining the exact value-copy policy.
cloud_path = root / "Sources/Shared/Services/Backups/Cloud/CloudBackupSnapshot.swift"
cloud_text = cloud_path.read_text()
save_source(cloud_path, ("import Foundation\n" + cloud_text[cloud_text.index("extension BackupSnapshot {"):]).encode(), True)

blocks = []
for name, token in [("Photos/PhotoStorage.swift", "struct PhotoBackupFile:"),
                    ("Drawings/DrawingStorage.swift", "struct DrawingBackupFile:"),
                    ("Documents/ProjectDocumentStorage.swift", "struct ProjectDocumentBackupFile:"),
                    ("QuickNotes/QuickNoteAttachmentStorage.swift", "struct QuickNoteAttachmentBackupFile:")]:
    path = root / "Sources/Shared/Services/Storage" / name
    text = path.read_text()
    start = text.index(token)
    blocks.append(text[start:text.index("\n}", start) + 2])
    manifest[str(path.relative_to(root))] = {"source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "extracted": True}

def function(text, token):
    start = text.index(token)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{": depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0: return text[start:index + 1]
    raise ValueError(token)

photo_path = root / "Sources/Shared/Services/Storage/Photos/PhotoStorage.swift"
save_source(photo_path, ("import Foundation\n" + function(photo_path.read_text(), "extension DailyLog {") + "\n").encode(), True)
subtitle_path = root / "Sources/Features/Dashboard/DashboardCardViews.swift"
save_source(subtitle_path, ("import Foundation\n" + function(subtitle_path.read_text(), "enum DashboardSubtitleBuilder {") + "\n").encode(), True)

report_path = root / "Sources/Shared/Services/Reporting/ReportBuilder+FieldReports.swift"
report = report_path.read_text()
pure_functions = [function(report, token) for token in [
    "static func fieldReportLines(", "static func customerStatementLines(",
    "static func fieldReportMoney(", "static func fieldReportDate(", "private static func appendFieldText("]]
save_source(report_path, ("import Foundation\nextension ReportBuilder {\n" + "\n".join(pure_functions) + "\n}\n").encode(), True)
draft_path = root / "Sources/Shared/Services/Drafts/BusinessDraftStore.swift"
fingerprint = function(draft_path.read_text(), "static func fingerprint<")
save_source(draft_path, ("import Foundation\nenum BusinessDraftStore {\n" + fingerprint + "\n}\n").encode(), True)

(src / "PortableBoundary.swift").write_text("import Foundation\n" + "\n".join(blocks) + '''
// Only localization and amount-display adapters replace iOS dependencies.
enum AppLocalization {
    static func string(_ key: String.LocalizationValue) -> String {
        let raw = String(localized: key)
        return Bundle.module.localizedString(forKey: raw, value: raw, table: nil)
    }
}
enum ReportBuilder {
    static var locNotFilled: String { loc("未填写") }
    static func money(_ value: MoneyValue) -> String { value.wireText }
    static func loc(_ key: String) -> String { AppLocalization.string(String.LocalizationValue(key)) }
    static func locFormat(_ key: String, _ args: CVarArg...) -> String { String(format: loc(key), arguments: args) }
}
''')
resources = src / "Resources/en.lproj"
resources.mkdir(parents=True)
shutil.copyfile(root / "Sources/Resources/en.lproj/Localizable.strings", resources / "Localizable.strings")
for name in ["PracticalFinanceMaterialTests.swift", "PracticalChangeReviewTests.swift", "PracticalIntegrationTests.swift"]:
    shutil.copyfile(root / "Tests" / name, tests / name)

# Four exact core cases from the iOS report suite. PDFKit/UIKit rendering cases
# remain in the native test target and are explicitly excluded from this run.
path = root / "Tests/PracticalProjectReportTests.swift"
text = path.read_text()
names = ["civilDayRangeUsesLocalBoundariesAndRejectsUnknownDates", "fieldReportScopesLogsPhotosAndExplicitCompletionsInsideCore",
         "historicalManualPaidNeverBecomesPeriodIncomeAndOnlyIncomePlansAreExported", "legacySinglePhotoSelectionKeepsStableIdentity"]
prefix = text[text.index("    private let zone"):text.index("    private func pdfText")]
cases = ["    @Test " + function(text, "func " + name + "(") for name in names]
(tests / "PracticalPortableReportTests.swift").write_text("import Foundation\nimport Testing\n@testable import sitekeeper\n@MainActor struct PracticalPortableReportTests {\n" + prefix + "\n".join(cases) + "\n}\n")
manifest[str(path.relative_to(root))] = {"source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "selected_core_cases": names,
    "excluded": ["PDF rendering and PDF text extraction; photo file I/O"]}
(dest / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PracticalWorkflowValidation", defaultLocalization: "en", platforms: [.macOS(.v14)], targets: [
    .target(name: "sitekeeper", resources: [.process("Resources")]),
    .testTarget(name: "CoreTests", dependencies: ["sitekeeper"])
], swiftLanguageModes: [.v5])
''')
(dest / "source-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
expected = sum(len(re.findall(r"@Test\s+func\s+", p.read_text())) for p in tests.glob("*.swift"))
with (dest / "test.log").open("w") as out:
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(dest / "module-cache")
    environment["SWIFT_MODULECACHE_PATH"] = str(dest / "module-cache")
    command = ["swift", "test", "--package-path", str(dest), "--cache-path", str(dest / "cache"),
               "--config-path", str(dest / "config"), "--security-path", str(dest / "security")]
    if args.no_nested_sandbox:
        command.append("--disable-sandbox")
    result = subprocess.run(command,
                            cwd=dest, env=environment, stdout=out, stderr=subprocess.STDOUT)
log = (dest / "test.log").read_text()
match = re.search(r"Test run with (\d+) tests? in .* passed", log)
passed = int(match.group(1)) if match else 0
summary = {"expected": expected, "passed": passed, "exit_code": result.returncode,
    "success": result.returncode == 0 and passed == expected and expected > 0,
    "scope": "Synthetic Foundation models, core report text, backup Codable and injected in-memory store; no device, live data, UIKit or PDF rendering."}
(dest / "summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary))
print("Evidence:", dest)
if result.returncode:
    print(log[-14000:])
sys.exit(0 if summary["success"] else 1)
