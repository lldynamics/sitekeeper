#!/usr/bin/env python3
"""Validate the local DWG regression manifest without the removed legacy parser.

This compatibility entrypoint intentionally no longer builds or runs the old C
probe. Use scripts/cad/cad_regression.py for SiteKeeperCADKernel diagnostics and
render regression output.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


VALID_STATUSES = {"needed", "ready", "blocked"}
DEFAULT_MANIFEST = Path("Regression/DWG/manifest.json")


@dataclass
class Finding:
    level: str
    sample_id: str
    message: str


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[2]


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("manifest root must be a JSON object")
    return data


def safe_join(root: Path, relative_path: str) -> Path:
    candidate = (root / relative_path).resolve()
    root_resolved = root.resolve()
    try:
        candidate.relative_to(root_resolved)
    except ValueError as exc:
        raise ValueError(f"path escapes sample root: {relative_path}") from exc
    return candidate


def read_dwg_header(path: Path) -> str | None:
    try:
        with path.open("rb") as handle:
            raw = handle.read(6)
    except OSError:
        return None
    if len(raw) != 6:
        return None
    try:
        return raw.decode("ascii")
    except UnicodeDecodeError:
        return None


def string_field(sample: dict[str, Any], field: str) -> str:
    value = sample.get(field)
    return value.strip() if isinstance(value, str) else ""


def list_field(sample: dict[str, Any], field: str) -> list[str]:
    value = sample.get(field)
    if not isinstance(value, list):
        return []
    return [item.strip() for item in value if isinstance(item, str) and item.strip()]


def expected_field(sample: dict[str, Any]) -> dict[str, Any]:
    expected = sample.get("expected")
    return expected if isinstance(expected, dict) else {}


def validate_sample(
    sample: dict[str, Any],
    sample_root: Path,
    seen_ids: set[str],
    strict: bool,
) -> tuple[dict[str, Any], list[Finding]]:
    findings: list[Finding] = []
    sample_id = string_field(sample, "id") or "<missing-id>"
    status = string_field(sample, "status")
    relative_path = string_field(sample, "path")
    expected_header = string_field(sample, "dwgHeader")
    coverage = list_field(sample, "coverage")

    def error(message: str) -> None:
        findings.append(Finding("error", sample_id, message))

    def warning(message: str) -> None:
        findings.append(Finding("warning", sample_id, message))

    if sample_id == "<missing-id>":
        error("missing id")
    elif sample_id in seen_ids:
        error("duplicate id")
    else:
        seen_ids.add(sample_id)

    if status not in VALID_STATUSES:
        error(f"invalid status: {status or '<empty>'}")

    sample_path: Path | None
    if not relative_path:
        error("missing path")
        sample_path = None
    else:
        if not relative_path.lower().endswith(".dwg"):
            error("path must end with .dwg")
        try:
            sample_path = safe_join(sample_root, relative_path)
        except ValueError as exc:
            error(str(exc))
            sample_path = None

    if not expected_header.startswith("AC") or len(expected_header) != 6:
        error(f"invalid dwgHeader: {expected_header or '<empty>'}")

    if not coverage:
        warning("coverage tags are empty")

    exists = bool(sample_path and sample_path.exists())
    actual_header = read_dwg_header(sample_path) if sample_path and exists else None
    if status == "ready" and not exists:
        error("status is ready but sample file is missing")
    if strict and status == "needed":
        error("strict mode requires replacing needed with ready or blocked")
    if exists and status != "ready":
        warning("sample file exists but status is not ready")
    if exists and actual_header != expected_header:
        error(
            "DWG header mismatch: "
            f"expected {expected_header}, got {actual_header or '<unreadable>'}"
        )

    file_size = sample_path.stat().st_size if sample_path and exists else None
    result = {
        "id": sample_id,
        "status": status,
        "path": relative_path,
        "absolutePath": str(sample_path) if sample_path else None,
        "exists": exists,
        "fileSizeBytes": file_size,
        "expectedHeader": expected_header,
        "actualHeader": actual_header,
        "coverage": coverage,
        "expected": expected_field(sample),
    }
    return result, findings


def validate_manifest(manifest_path: Path, strict: bool) -> tuple[dict[str, Any], list[Finding]]:
    manifest = load_json(manifest_path)
    repo_root = repo_root_from_script()
    sample_root_text = manifest.get("sampleRoot")
    if not isinstance(sample_root_text, str) or not sample_root_text.strip():
        raise ValueError("manifest sampleRoot is required")
    sample_root = (repo_root / sample_root_text).resolve()

    samples = manifest.get("samples")
    if not isinstance(samples, list):
        raise ValueError("manifest samples must be an array")

    seen_ids: set[str] = set()
    findings: list[Finding] = []
    sample_results: list[dict[str, Any]] = []
    for raw_sample in samples:
        if not isinstance(raw_sample, dict):
            findings.append(Finding("error", "<invalid>", "sample entry must be an object"))
            continue
        result, sample_findings = validate_sample(raw_sample, sample_root, seen_ids, strict)
        sample_results.append(result)
        findings.extend(sample_findings)

    status_counts: dict[str, int] = {status: 0 for status in sorted(VALID_STATUSES)}
    for result in sample_results:
        status = result.get("status")
        if isinstance(status, str) and status in status_counts:
            status_counts[status] += 1

    coverage_counts: dict[str, int] = {}
    for result in sample_results:
        for tag in result.get("coverage", []):
            coverage_counts[tag] = coverage_counts.get(tag, 0) + 1

    report = {
        "manifest": str(manifest_path),
        "sampleRoot": str(sample_root),
        "sampleCount": len(sample_results),
        "statusCounts": status_counts,
        "coverageCounts": dict(sorted(coverage_counts.items())),
        "samples": sample_results,
        "findings": [finding.__dict__ for finding in findings],
        "parser": {
            "status": "removed",
            "message": "Legacy parser probe has been removed. Run scripts/cad/cad_regression.py instead.",
        },
    }
    return report, findings


def print_summary(report: dict[str, Any], findings: list[Finding]) -> None:
    status_counts = report["statusCounts"]
    print(f"DWG regression samples: {report['sampleCount']}")
    print(
        "Status: "
        + ", ".join(f"{key}={value}" for key, value in status_counts.items())
    )
    print("Parser: removed; use scripts/cad/cad_regression.py")
    errors = [finding for finding in findings if finding.level == "error"]
    warnings = [finding for finding in findings if finding.level == "warning"]
    print(f"Findings: errors={len(errors)}, warnings={len(warnings)}")
    for finding in findings:
        print(f"{finding.level.upper()} [{finding.sample_id}] {finding.message}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Path to DWG regression manifest.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail while planned samples are still marked needed.",
    )
    parser.add_argument(
        "--skip-parser",
        action="store_true",
        help="Compatibility flag; parser execution has been removed.",
    )
    parser.add_argument(
        "--parser",
        type=Path,
        help="Compatibility flag; ignored because parser execution has been removed.",
    )
    parser.add_argument(
        "--parser-timeout",
        type=int,
        default=120,
        help="Compatibility flag; ignored because parser execution has been removed.",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        help="Compatibility flag; ignored because parser execution has been removed.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional JSON report output path.",
    )
    args = parser.parse_args()

    repo_root = repo_root_from_script()
    manifest_path = args.manifest
    if not manifest_path.is_absolute():
        manifest_path = repo_root / manifest_path

    try:
        report, findings = validate_manifest(manifest_path, strict=args.strict)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR manifest failed: {exc}", file=sys.stderr)
        return 2

    if args.report:
        report_path = args.report
        if not report_path.is_absolute():
            report_path = repo_root / report_path
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    print_summary(report, findings)
    return 1 if any(finding.level == "error" for finding in findings) else 0


if __name__ == "__main__":
    raise SystemExit(main())
