#!/usr/bin/env python3
"""Freeze an isolated before/after Xcode test candidate and its provenance.

This prepares source only: it never installs, builds, or launches an application.
Requires Python 3.9+ and the explicitly supplied XcodeGen executable.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from datetime import datetime, timezone

EXCLUDED_PARTS = {".git", "build", ".build", "DerivedData"}
IDENTITY = "com.chengjinfang.sitekeeper"
PROPERTIES = (
    "activeProjects", "activeProjectIDs", "projectNameByID", "todayLogs", "openTodos",
    "todayTodos", "overdueTasks", "overdueTodos", "activeFinancialRecords",
    "dashboardBusinessSummary", "warehouseMovementsForActiveProjects", "warehouseStockLines",
    "warehouseTodayMovementCount", "warehouseNegativeCount", "recentWarehouseMovements",
    "projectsWithoutTodayLogCount", "unattachedReceiptCount", "unsettledFinancialCount",
    "materialPriceSpikeCount",
)
PROVIDER = Path("Sources/Features/Dashboard/DashboardDataProvider.swift")
ROUTING = Path("Sources/Features/Dashboard/DashboardView+SupportRouting.swift")
BENCHMARK = Path("Tests/Phase1PerformanceBenchmarkTests.swift")
ADAPTER = Path("Tests/Support/Phase1LegacyDashboard.swift")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fingerprint(path: Path) -> dict:
    if path.is_symlink():
        target = os.readlink(path)
        return {"kind": "symlink", "sha256": sha(os.fsencode(target)), "target": target}
    data = path.read_bytes()
    return {"kind": "file", "sha256": sha(data), "bytes": len(data)}


def is_excluded(path: Path) -> bool:
    return any(part in EXCLUDED_PARTS for part in path.parts)


def source_files(source: Path) -> tuple[list[Path], str]:
    result = subprocess.run(
        ["git", "-C", str(source), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode == 0 and Path(result.stdout.strip()).resolve() == source:
        listing = subprocess.run(
            ["git", "-C", str(source), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            capture_output=True, check=True,
        )
        names = {Path(os.fsdecode(name)) for name in listing.stdout.split(b"\0") if name}
        return sorted((p for p in names if not is_excluded(p)), key=str), "git ls-files --cached --others --exclude-standard"
    names = []
    for folder, directories, files in os.walk(source, followlinks=False):
        relative = Path(folder).relative_to(source)
        directories[:] = sorted(name for name in directories if not is_excluded(relative / name))
        for name in directories[:]:
            path = relative / name
            if (source / path).is_symlink():
                names.append(path)
                directories.remove(name)
        names.extend(relative / name for name in files if not is_excluded(relative / name))
    return sorted(names, key=str), "filesystem traversal (source is not a Git root)"


def ensure_owned(output: Path, relative: Path) -> Path:
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"Invalid candidate path: {relative}")
    target = output / relative
    # Never follow a copied symlink back into the source or another directory.
    for ancestor in [target, *target.parents]:
        if ancestor == output:
            break
        if ancestor.is_symlink():
            raise ValueError(f"Refusing to modify a symlink in candidate: {relative}")
    return target


def transform(output: Path, relative: Path, data: bytes, reason: str, manifest: dict) -> None:
    target = ensure_owned(output, relative)
    before = fingerprint(target) if target.exists() else None
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    manifest["transformations"].append({
        "path": str(relative), "reason": reason, "before": before, "after": fingerprint(target),
    })


def extract_member(source: str, kind: str, name: str) -> tuple[str, dict]:
    """Extract exactly the member's original source, preserving its indentation.

    Swift's nested bodies in these reference files use deeper indentation, so the
    next closing brace at the declaration's indentation is its exact boundary.
    Inline properties are supported separately. Fail closed on ambiguous matches.
    """
    pattern = rf"(?m)^    {kind} {re.escape(name)}(?:\b|\()[^\n]*"
    matches = list(re.finditer(pattern, source))
    if len(matches) != 1:
        raise ValueError(f"Expected one {kind} {name}, found {len(matches)}")
    start = matches[0].start()
    declaration = matches[0].group()
    if "{" not in declaration:
        raise ValueError(f"Member body is not on its declaration line: {name}")
    if declaration.rstrip().endswith("}"):
        end = matches[0].end()
    else:
        close = re.search(r"(?m)^    }[ \t]*(?=\n|$)", source[matches[0].end():])
        if close is None:
            raise ValueError(f"Missing closing boundary for {name}")
        end = matches[0].end() + close.end()
    snippet = source[start:end]
    return snippet, {
        "name": name, "kind": kind, "start_line": source.count("\n", 0, start) + 1,
        "end_line": source.count("\n", 0, end) + 1, "sha256": sha(snippet.encode()),
    }


DIGEST_SOURCE = r'''
struct Phase1BusinessDigest: Equatable {
    let amounts: [MoneyValue]
    let receivableAgeDays: Int?
    let recentCollectionDate: BusinessDateValue?
    let recentCollectionAmount: MoneyValue?
    let recentCollectionProject: String?
    let pendingMaterialCount: Int
    let unpricedQuoteCount: Int

    init(_ value: ProjectBusinessSummary) {
        amounts = [value.quoteTotal, value.contractAmount, value.paidAmount,
                   value.receivableAmount, value.materialCost, value.laborCostAmount,
                   value.estimatedProfit, value.unpaidAmount]
        receivableAgeDays = value.receivableAgeDays
        recentCollectionDate = value.recentCollection?.date
        recentCollectionAmount = value.recentCollection?.amount
        recentCollectionProject = value.recentCollection?.projectName
        pendingMaterialCount = value.pendingMaterialCount
        unpricedQuoteCount = value.unpricedQuoteCount
    }
}

struct Phase1WarehouseDigest: Equatable {
    let id: String
    let materialName: String
    let specification: String
    let unit: String
    let quantity: QuantityValue

    init(_ line: WarehouseStockLine) {
        id = line.id
        materialName = line.materialName
        specification = line.specification
        unit = line.unit
        quantity = line.quantity
    }
}

struct Phase1SummaryDigest: Equatable {
    let activeProjectCount: Int
    let activeProjectIDs: Set<UUID>
    let projectNameByID: [UUID: String]
    let todayLogCount: Int
    let openTodoCount: Int
    let todayTodoCount: Int
    let overdueTaskCount: Int
    let overdueTodoCount: Int
    let activeFinancialRecordCount: Int
    let business: Phase1BusinessDigest
    let warehouseMovementCount: Int
    let warehouseStock: [Phase1WarehouseDigest]
    let warehouseTodayMovementCount: Int
    let warehouseNegativeCount: Int
    let recentWarehouseMovementIDs: [UUID]
    let projectsWithoutTodayLogCount: Int
    let unattachedReceiptCount: Int
    let unsettledFinancialCount: Int
    let materialPriceSpikeCount: Int
}

#if !SITEKEEPER_PHASE1_BASELINE
extension Phase1SummaryDigest {
    init(summary: DashboardSummaryModel) {
        self.init(
            activeProjectCount: summary.activeProjects.count,
            activeProjectIDs: summary.activeProjectIDs,
            projectNameByID: summary.projectNameByID,
            todayLogCount: summary.todayLogs.count,
            openTodoCount: summary.openTodos.count,
            todayTodoCount: summary.todayTodos.count,
            overdueTaskCount: summary.overdueTasks.count,
            overdueTodoCount: summary.overdueTodos.count,
            activeFinancialRecordCount: summary.activeFinancialRecords.count,
            business: Phase1BusinessDigest(summary.businessSummary),
            warehouseMovementCount: summary.warehouseMovements.count,
            warehouseStock: summary.warehouseStockLines.map(Phase1WarehouseDigest.init),
            warehouseTodayMovementCount: summary.warehouseTodayMovementCount,
            warehouseNegativeCount: summary.warehouseNegativeCount,
            recentWarehouseMovementIDs: summary.recentWarehouseMovements.map(\.id),
            projectsWithoutTodayLogCount: summary.projectsWithoutTodayLogCount,
            unattachedReceiptCount: summary.unattachedReceiptCount,
            unsettledFinancialCount: summary.unsettledFinancialCount,
            materialPriceSpikeCount: summary.materialPriceSpikeCount
        )
    }
}
#endif
'''

READ_SOURCE = r'''
    func read() -> Phase1SummaryDigest {
        Phase1SummaryDigest(
            activeProjectCount: activeProjects.count,
            activeProjectIDs: activeProjectIDs,
            projectNameByID: projectNameByID,
            todayLogCount: todayLogs.count,
            openTodoCount: openTodos.count,
            todayTodoCount: todayTodos.count,
            overdueTaskCount: overdueTasks.count,
            overdueTodoCount: overdueTodos.count,
            activeFinancialRecordCount: activeFinancialRecords.count,
            business: Phase1BusinessDigest(dashboardBusinessSummary),
            warehouseMovementCount: warehouseMovementsForActiveProjects.count,
            warehouseStock: warehouseStockLines.map(Phase1WarehouseDigest.init),
            warehouseTodayMovementCount: warehouseTodayMovementCount,
            warehouseNegativeCount: warehouseNegativeCount,
            recentWarehouseMovementIDs: recentWarehouseMovements.map(\.id),
            projectsWithoutTodayLogCount: projectsWithoutTodayLogCount,
            unattachedReceiptCount: unattachedReceiptCount,
            unsettledFinancialCount: unsettledFinancialCount,
            materialPriceSpikeCount: materialPriceSpikeCount
        )
    }
'''


def build_adapter(reference: Path) -> tuple[bytes, list[dict]]:
    provider = (reference / PROVIDER).read_text()
    routing = (reference / ROUTING).read_text()
    blocks, provenance = [], []
    for path, text, kind, names in [
        (PROVIDER, provider, "var", ("todayDay", *PROPERTIES)),
        (ROUTING, routing, "func", ("projectName", "dashboardReceivableAgeDays")),
    ]:
        for name in names:
            snippet, metadata = extract_member(text, kind, name)
            metadata.update({"source": str(reference / path), "source_sha256": sha(text.encode())})
            blocks.append(snippet)
            provenance.append(metadata)
    result = (
        "// Generated only inside an isolated Phase 1 validation copy.\n"
        "// Legacy computed members below are copied verbatim from the frozen reference.\n"
        "import Foundation\n@testable import sitekeeper\n\n"
        "#if SITEKEEPER_PHASE1_REFERENCE\n"
        "@MainActor\nstruct Phase1LegacyDashboard {\n"
        "    let projectStore: ProjectStore\n    let financeStore: FinanceStore\n\n"
        + "\n\n".join(blocks) + "\n" + READ_SOURCE + "}\n"
        + DIGEST_SOURCE + "\n#endif\n"
    )
    return result.encode(), provenance


def isolate_candidate(output: Path, phase: str, manifest: dict) -> None:
    identities = [
        Path("project.yml"), Path("Sources/Resources/sitekeeper.entitlements"),
        Path("Widget/WidgetExtension.entitlements"),
        Path("Sources/Shared/Services/Widgets/WidgetSharedModels.swift"),
        Path("Sources/Shared/Services/Backups/Cloud/CloudBackupService.swift"),
    ]
    isolated = f"{IDENTITY}.phase1.{phase}"
    for relative in identities:
        target = ensure_owned(output, relative)
        text = target.read_text()
        count = text.count(IDENTITY)
        if count == 0:
            raise ValueError(f"Expected production identity in {relative}")
        transform(output, relative, text.replace(IDENTITY, isolated).encode(),
                  f"test-only identity isolation ({count} replacements): {IDENTITY} -> {isolated}", manifest)

    relative = Path("project.yml")
    text = ensure_owned(output, relative).read_text()
    flags = "$(inherited) -DSITEKEEPER_PHASE1_REFERENCE"
    if phase == "before":
        flags += " -DSITEKEEPER_PHASE1_BASELINE"
    if len(re.findall(r"(?m)^settings:\s*$", text)) != 1:
        raise ValueError("Expected one global settings block in project.yml")
    if any(key + ":" in text for key in ("OTHER_SWIFT_FLAGS", "ENABLE_TESTABILITY", "SWIFT_OPTIMIZATION_LEVEL", "SWIFT_COMPILATION_MODE")):
        raise ValueError("Explicit compilation conditions/testability already exist; review the spec before overriding")
    text = re.sub(r"(?m)^settings:\s*$", "settings:\n  ENABLE_TESTABILITY: YES\n"
                  '  SWIFT_OPTIMIZATION_LEVEL: "-O"\n  SWIFT_COMPILATION_MODE: wholemodule\n'
                  f'  OTHER_SWIFT_FLAGS: "{flags}"', text, count=1)
    lines = text.splitlines(keepends=True)
    in_test = False
    test_indent = 0
    debug_count = 0
    for index, line in enumerate(lines):
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if in_test and stripped and indent <= test_indent:
            in_test = False
        if stripped == "test:":
            in_test = True
            test_indent = indent
        elif in_test and stripped.startswith("config:"):
            if stripped not in {"config: Debug", "config: Release"}:
                raise ValueError(f"Unexpected test configuration: {stripped}")
            lines[index] = " " * indent + "config: Debug\n"
            debug_count += 1
    if debug_count < 1:
        raise ValueError("No test scheme configuration found")
    transform(output, relative, "".join(lines).encode(),
              f"test-only optimized Debug: {debug_count} test schemes use Debug; DEBUG preserved; "
              f"SWIFT_OPTIMIZATION_LEVEL=-O; SWIFT_COMPILATION_MODE=wholemodule; "
              f"ENABLE_TESTABILITY=YES; OTHER_SWIFT_FLAGS={flags}; existing boundary guards retained", manifest)
    manifest["isolated_identities"] = {
        "application": isolated, "widget": isolated + ".widget", "tests": isolated + ".tests",
        "uitests": isolated + ".uitests", "app_group": "group." + isolated,
        "icloud_container": "iCloud." + isolated,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="New directory; must not already exist")
    parser.add_argument("--phase", choices=("before", "after"), required=True)
    parser.add_argument("--xcodegen", type=Path, required=True)
    args = parser.parse_args()
    source, reference = args.source.resolve(), args.reference.resolve()
    output = args.output.absolute()
    if output.exists() or output.is_symlink():
        parser.error("--output must be a new directory")
    # Resolve existing ancestors before checking so aliases cannot redirect writes.
    output = output.resolve()
    if not source.is_dir() or not reference.is_dir():
        parser.error("--source and --reference must be existing directories")
    if output == source or output == reference or output in source.parents or output in reference.parents:
        parser.error("--output cannot replace or contain either input")
    xcodegen = args.xcodegen.resolve()
    if not xcodegen.is_file() or not os.access(xcodegen, os.X_OK):
        parser.error("--xcodegen must name an executable file")
    root = Path(__file__).resolve().parents[2]
    benchmark_source = root / BENCHMARK
    benchmark_data = benchmark_source.read_bytes()
    adapter_data, reference_members = build_adapter(reference)
    files, selection = source_files(source)
    # A candidate under source must be beneath an excluded directory, or a future
    # traversal could recursively ingest its own output.
    if source in output.parents and not is_excluded(output.relative_to(source)):
        parser.error("An output inside --source must be beneath build, .build, or DerivedData")
    output.mkdir(parents=True, exist_ok=False)
    manifest = {
        "schema": 1, "created_at": datetime.now(timezone.utc).isoformat(), "phase": args.phase,
        "source": str(source), "reference": str(reference), "output": str(output),
        "selection": selection, "excluded_path_components": sorted(EXCLUDED_PARTS),
        "copied_files": {}, "missing_tracked_files": [], "transformations": [],
        "reference_members": reference_members, "legacy_read_properties": list(PROPERTIES),
        "scope": "Frozen source preparation only; no build, installation, simulator, or production data access.",
        "validation_configuration": {
            "name": "optimized Debug (not Release acceptance)",
            "config": "Debug", "optimization": "-O", "compilation_mode": "wholemodule",
            "enable_testability": True, "preserve_debug_condition": True,
            "sdk": "pending: record the fixed SDK at execution",
            "device": "pending: record the identical isolated test device at execution",
            "boundary_guards": "Retained unchanged; existing Debug skip policy applies. Record the independent eight-guard report.",
        },
    }
    manifest_path = output / "phase1-validation-manifest.json"
    try:
        for relative in files:
            original, target = source / relative, ensure_owned(output, relative)
            if not original.exists() and not original.is_symlink():
                manifest["missing_tracked_files"].append(str(relative))
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            mode = original.lstat().st_mode
            if stat.S_ISLNK(mode):
                os.symlink(os.readlink(original), target)
            elif stat.S_ISREG(mode):
                data = original.read_bytes()
                target.write_bytes(data)
                target.chmod(stat.S_IMODE(mode))
            else:
                raise ValueError(f"Unsupported source entry: {original}")
            copied = fingerprint(target)
            manifest["copied_files"][str(relative)] = {"source": str(original), "source_sha256": copied["sha256"], "copied": copied}
        isolate_candidate(output, args.phase, manifest)
        transform(output, BENCHMARK, benchmark_data, "Inject identical current benchmark in both candidates", manifest)
        manifest["benchmark_source"] = {"path": str(benchmark_source), "sha256": sha(benchmark_data)}
        transform(output, ADAPTER, adapter_data, "Generated exact frozen-reference expressions and shared comparison digest", manifest)
        command = [str(xcodegen), "generate", "--spec", str(output / "project.yml")]
        manifest["xcodegen"] = {"command": command, "binary_sha256": sha(xcodegen.read_bytes())}
        with (output / "phase1-xcodegen.log").open("w") as log:
            result = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT, check=False)
        manifest["xcodegen"]["returncode"] = result.returncode
        if result.returncode:
            raise RuntimeError(f"XcodeGen failed ({result.returncode}); see {output / 'phase1-xcodegen.log'}")
        for relative, metadata in manifest["copied_files"].items():
            candidate = output / relative
            metadata["final"] = fingerprint(candidate) if candidate.exists() or candidate.is_symlink() else None
        all_output, _ = source_files(output)
        manifest["generated_files"] = {
            str(p): fingerprint(output / p) for p in all_output
            if str(p) not in manifest["copied_files"] and (output / p).is_file()
        }
        manifest["success"] = True
    except Exception as error:
        manifest["success"] = False
        manifest["error"] = str(error)
        raise
    finally:
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(output), "phase": args.phase,
                      "copied_files": len(manifest["copied_files"]), "manifest": str(manifest_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
