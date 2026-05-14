#!/usr/bin/env python3
"""Validate the local DWG regression sample library.

The script keeps two contracts:
- inventory: manifest shape, local sample presence, DWG header, and status
- parser regression: ready samples are parsed through LibreDWGBridge's C bridge
  probe and compared with the expected thresholds in manifest.json
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any


VALID_STATUSES = {"needed", "ready", "blocked"}
DEFAULT_MANIFEST = Path("Regression/DWG/manifest.json")
DEFAULT_PROBE_BUILD_DIR = Path("Regression/DWG/reports/tools")
PROBE_SOURCE = Path("scripts/cad/dwg_probe.c")


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
    if isinstance(value, str):
        return value.strip()
    return ""


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
    }
    return report, findings


def build_probe(repo_root: Path, build_dir: Path) -> Path:
    source = repo_root / PROBE_SOURCE
    bridge_source = repo_root / "Packages/LibreDWGBridge/Sources/LibreDWGCBridge/LibreDWGCBridge.c"
    vendor_src = repo_root / "Packages/LibreDWGBridge/Vendor/LibreDWG/src"
    vendor_sources = sorted(vendor_src.glob("*.c"))
    output = build_dir / "dwg_probe"
    output.parent.mkdir(parents=True, exist_ok=True)

    command = [
        "clang",
        "-O0",
        "-g",
        "-DDISABLE_DXF=1",
        "-DDISABLE_JSON=1",
        "-DNDEBUG=1",
        "-I" + str(repo_root / "Packages/LibreDWGBridge/Sources/LibreDWGCBridge/include"),
        "-I" + str(repo_root / "Packages/LibreDWGBridge/Vendor/LibreDWG/include"),
        "-I" + str(vendor_src),
        str(source),
        str(bridge_source),
        *[str(path) for path in vendor_sources],
        "-liconv",
        "-lm",
        "-o",
        str(output),
    ]
    completed = subprocess.run(
        command,
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "failed to build DWG parser probe\n"
            + completed.stdout
            + completed.stderr
        )
    return output


def run_probe(probe: Path, sample_path: Path, timeout: int) -> dict[str, Any]:
    start = time.perf_counter()
    completed = subprocess.run(
        [str(probe), str(sample_path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        payload = {
            "ok": False,
            "errorMessage": f"parser probe returned invalid JSON: {exc}",
            "stdout": completed.stdout,
        }
    if not isinstance(payload, dict):
        payload = {"ok": False, "errorMessage": "parser probe JSON root is not an object"}
    payload["exitCode"] = completed.returncode
    payload["parseMilliseconds"] = max(1, elapsed_ms)
    if completed.stderr.strip():
        payload["stderr"] = completed.stderr.strip()
    return payload


def cleaned_cad_path(path: str) -> str:
    cleaned = path.strip().strip('"').replace("\\", "/")
    if cleaned.lower().startswith("file://"):
        cleaned = cleaned[7:]
    while cleaned.startswith("./"):
        cleaned = cleaned[2:]
    return cleaned


def is_windows_absolute(path: str) -> bool:
    return len(path) >= 2 and path[1] == ":" and path[0].isalpha()


def xref_leaf_candidates(saved_path: str, name: str) -> list[str]:
    candidates: list[str] = []
    seen: set[str] = set()

    def append(raw: str) -> None:
        cleaned = cleaned_cad_path(raw)
        if not cleaned:
            return
        leaf = cleaned.split("/")[-1]
        if not leaf:
            return
        key = leaf.lower()
        if key not in seen:
            candidates.append(leaf)
            seen.add(key)
        if not leaf.lower().endswith(".dwg"):
            dwg_leaf = f"{leaf}.dwg"
            if dwg_leaf.lower() not in seen:
                candidates.append(dwg_leaf)
                seen.add(dwg_leaf.lower())

    append(saved_path)
    append(name)
    return candidates


def existing_file_case_insensitive(path: Path) -> Path | None:
    if path.is_file():
        return path
    parent = path.parent
    if not parent.is_dir():
        return None
    target = path.name.lower()
    for child in parent.iterdir():
        if child.name.lower() == target and child.is_file():
            return child
    return None


def resolve_xref_local_path(sample_path: Path, saved_path: str, name: str) -> Path | None:
    source_dir = sample_path.parent
    candidates: list[Path] = []
    seen: set[str] = set()

    def append(path: Path) -> None:
        key = str(path)
        if key not in seen:
            candidates.append(path)
            seen.add(key)

    cleaned = cleaned_cad_path(saved_path)
    if cleaned:
        if cleaned.startswith("/"):
            append(Path(cleaned))
        elif not is_windows_absolute(cleaned) and not cleaned.startswith("//"):
            append(source_dir / cleaned)

    local_dirs = [
        source_dir,
        source_dir / "xref",
        source_dir / "xrefs",
        source_dir / "XREF",
        source_dir / "参照",
        source_dir / "外部参照",
        source_dir.parent,
    ]
    for directory in local_dirs:
        for leaf in xref_leaf_candidates(cleaned, name):
            append(directory / leaf)

    for candidate in candidates:
        existing = existing_file_case_insensitive(candidate)
        if existing:
            return existing
    return None


def attach_xref_resolution(parse_result: dict[str, Any], sample_path: Path) -> None:
    xrefs = parse_result.get("xrefs")
    if not isinstance(xrefs, list):
        parse_result["xrefLocalResolution"] = {
            "found": 0,
            "missing": 0,
            "pathEmpty": 0,
        }
        return

    found = 0
    missing = 0
    path_empty = 0
    for item in xrefs:
        if not isinstance(item, dict):
            continue
        saved_path = item.get("savedPath") if isinstance(item.get("savedPath"), str) else ""
        name = item.get("name") if isinstance(item.get("name"), str) else ""
        resolved = resolve_xref_local_path(sample_path, saved_path, name)
        if resolved:
            found += 1
            item["localStatus"] = "found"
            item["resolvedLocalPath"] = str(resolved)
        elif saved_path.strip():
            missing += 1
            item["localStatus"] = "missing"
        else:
            path_empty += 1
            item["localStatus"] = "pathEmpty"
    parse_result["xrefLocalResolution"] = {
        "found": found,
        "missing": missing,
        "pathEmpty": path_empty,
    }


def text_sample_string(sample: dict[str, Any], key: str) -> str:
    value = sample.get(key)
    return value if isinstance(value, str) else ""


def has_cjk(text: str) -> bool:
    return any(
        0x3400 <= ord(character) <= 0x9FFF
        or 0xF900 <= ord(character) <= 0xFAFF
        for character in text
    )


def latin1_supplement_count(text: str) -> int:
    return sum(1 for character in text if 0x00A0 <= ord(character) <= 0x00FF)


def halfwidth_katakana_count(text: str) -> int:
    return sum(1 for character in text if 0xFF61 <= ord(character) <= 0xFF9F)


def high_byte_count(raw_hex: str) -> int:
    count = 0
    for token in raw_hex.split():
        try:
            if int(token, 16) >= 0x80:
                count += 1
        except ValueError:
            continue
    return count


def control_character_count(text: str) -> int:
    return sum(
        1
        for character in text
        if ord(character) < 0x20 and character not in "\n\r\t"
    )


def box_drawing_count(text: str) -> int:
    return sum(1 for character in text if 0x2500 <= ord(character) <= 0x257F)


def classify_text_sample(sample: dict[str, Any]) -> list[str]:
    text = text_sample_string(sample, "text")
    raw_hex = text_sample_string(sample, "rawTextBytesHex")
    font_file = text_sample_string(sample, "fontFile").lower()
    big_font_file = text_sample_string(sample, "bigFontFile").lower()
    chosen_codepage = sample.get("chosenCodepage")
    cjk = has_cjk(text)
    latin1_count = latin1_supplement_count(text)
    halfwidth_count = halfwidth_katakana_count(text)
    high_bytes = high_byte_count(raw_hex)
    issues: list[str] = []

    if raw_hex and not text.strip():
        issues.append("empty-decoded-text")
    if "\ufffd" in text:
        issues.append("replacement-character")
    if "\\U+" in text or "\\M+" in text:
        issues.append("unexpanded-autocad-escape")
    if "\\P" in text or "\\A" in text or "\\C" in text:
        issues.append("unexpanded-mtext-control")
    if "%%" in text:
        issues.append("unexpanded-cad-control-code")
    if control_character_count(text) > 0:
        issues.append("control-character")
    if text.strip() and ("??" in text or text.count("?") >= max(2, len(text.strip()) // 2)):
        issues.append("question-mark-loss")
    if text.strip() and not cjk and latin1_count >= 2:
        issues.append("latin1-mojibake")
    if text.strip() and not cjk and halfwidth_count >= 2:
        issues.append("halfwidth-katakana-mojibake")
    if text.strip() and cjk and (halfwidth_count > 0 or box_drawing_count(text) > 0):
        issues.append("mixed-symbol-mojibake")
    if isinstance(chosen_codepage, int) and chosen_codepage in {932, 949, 950} and high_bytes >= 2:
        issues.append("non-gbk-fallback-decode")
    if big_font_file and not cjk and high_bytes >= 2 and not issues:
        issues.append("bigfont-needs-verification")
    if font_file.endswith(".shx") and not big_font_file and cjk:
        issues.append("shx-without-bigfont")

    return issues


def attach_text_diagnostics(parse_result: dict[str, Any]) -> None:
    raw_samples = parse_result.get("textSamples")
    samples = [item for item in raw_samples if isinstance(item, dict)] if isinstance(raw_samples, list) else []
    issue_counts: Counter[str] = Counter()
    codepage_counts: Counter[str] = Counter()
    style_counts: Counter[str] = Counter()
    issue_samples: list[dict[str, Any]] = []
    issue_sample_total = 0

    for sample in samples:
        issues = classify_text_sample(sample)
        sample["issues"] = issues
        for issue in issues:
            issue_counts[issue] += 1
        if issues:
            issue_sample_total += 1
            if len(issue_samples) < 20:
                issue_samples.append(sample)

        codepage = sample.get("chosenCodepage")
        if isinstance(codepage, int) and codepage > 0:
            codepage_counts[str(codepage)] += 1

        style_name = text_sample_string(sample, "textStyleName")
        font_file = text_sample_string(sample, "fontFile")
        big_font_file = text_sample_string(sample, "bigFontFile")
        if style_name:
            style_counts[f"style:{style_name}"] += 1
        if font_file:
            style_counts[f"font:{font_file}"] += 1
        if big_font_file:
            style_counts[f"bigfont:{big_font_file}"] += 1

    text_count = parse_result.get("textPrimitiveCount")
    total_text_count = int(text_count) if isinstance(text_count, int) else 0
    sample_count = len(samples)
    parse_result["textDiagnostics"] = {
        "sampleCount": sample_count,
        "totalTextCount": total_text_count,
        "sampleCoverageRatio": sample_count / max(total_text_count, 1),
        "issueSampleCount": issue_sample_total,
        "issueCounts": dict(sorted(issue_counts.items())),
        "codepageCounts": dict(sorted(codepage_counts.items())),
        "styleHintCounts": dict(style_counts.most_common(20)),
        "issueSamples": issue_samples,
    }


def compare_expected(
    sample: dict[str, Any],
    parse_result: dict[str, Any],
) -> list[Finding]:
    sample_id = str(sample.get("id", "<unknown>"))
    expected = sample.get("expected") if isinstance(sample.get("expected"), dict) else {}
    findings: list[Finding] = []

    def error(message: str) -> None:
        findings.append(Finding("error", sample_id, message))

    def warning(message: str) -> None:
        findings.append(Finding("warning", sample_id, message))

    def number(key: str) -> float:
        value = parse_result.get(key)
        return float(value) if isinstance(value, (int, float)) else 0.0

    if not parse_result.get("ok"):
        message = parse_result.get("errorMessage")
        error(str(message) if message else "parser probe failed")
        return findings

    if str(parse_result.get("dwgVersionCode", "")) != str(sample.get("expectedHeader", "")):
        error(
            "parser DWG version mismatch: "
            f"expected {sample.get('expectedHeader')}, got {parse_result.get('dwgVersionCode')}"
        )

    checks = [
        ("minPrimitiveCount", "primitiveCount", "primitive count is below expected minimum"),
        ("minTextCount", "textPrimitiveCount", "text count is below expected minimum"),
    ]
    for expected_key, actual_key, message in checks:
        if expected_key in expected and number(actual_key) < float(expected[expected_key]):
            error(f"{message}: expected >= {expected[expected_key]}, got {int(number(actual_key))}")

    max_checks = [
        ("maxUnsupportedEntityCount", "unsupportedEntityCount", "unsupported count exceeded"),
        ("maxUnresolvedBlockCount", "blockUnresolvedCount", "unresolved block count exceeded"),
        ("maxParseMilliseconds", "parseMilliseconds", "parse time exceeded"),
    ]
    for expected_key, actual_key, message in max_checks:
        if expected_key in expected and number(actual_key) > float(expected[expected_key]):
            error(f"{message}: expected <= {expected[expected_key]}, got {int(number(actual_key))}")

    if "maxEstimatedMemoryMB" in expected:
        estimated_mb = number("estimatedPrimitiveMemory") / 1_048_576.0
        if estimated_mb > float(expected["maxEstimatedMemoryMB"]):
            error(
                "estimated primitive memory exceeded: "
                f"expected <= {expected['maxEstimatedMemoryMB']} MB, got {estimated_mb:.2f} MB"
            )

    if expected.get("requiresText") and number("textPrimitiveCount") <= 0:
        error("expected text primitives but parser returned none")

    if expected.get("requiresStyleSummary") and not str(parse_result.get("styleTableSummary", "")).strip():
        error("expected STYLE table summary but parser returned none")

    if expected.get("requiresUnsupportedSummary") and not str(parse_result.get("unsupportedEntitySummary", "")).strip():
        error("expected unsupported summary but parser returned none")

    block_summary = str(parse_result.get("blockReferenceSummary", ""))
    required_block_tokens = expected.get("requiresBlockSummary")
    if isinstance(required_block_tokens, list):
        for token in required_block_tokens:
            if isinstance(token, str) and token not in block_summary:
                error(f"block summary missing token: {token}")

    if expected.get("requiresXrefSummary"):
        xref_summary = str(parse_result.get("xrefReferenceSummary", "")).strip()
        if number("xrefReferenceCount") <= 0 and not xref_summary:
            error("expected XREF summary but parser returned none")

    xref_resolution = parse_result.get("xrefLocalResolution")
    if not isinstance(xref_resolution, dict):
        xref_resolution = {}
    missing_xrefs = int(xref_resolution.get("missing", 0)) + int(xref_resolution.get("pathEmpty", 0))
    if expected.get("requiresLocalPathResolution") and int(xref_resolution.get("found", 0)) <= 0:
        error("expected at least one locally resolved XREF path")
    if "maxMissingXrefCount" in expected and missing_xrefs > int(expected["maxMissingXrefCount"]):
        error(f"missing XREF count exceeded: expected <= {expected['maxMissingXrefCount']}, got {missing_xrefs}")

    if "maxSuspiciousTextRatio" in expected:
        text_count = int(number("textPrimitiveCount"))
        suspicious_count = int(number("suspiciousTextCount"))
        ratio = suspicious_count / max(text_count, 1)
        if text_count <= 0:
            warning("cannot evaluate suspicious text ratio because text count is zero")
        elif ratio > float(expected["maxSuspiciousTextRatio"]):
            error(
                "suspicious text ratio exceeded: "
                f"expected <= {expected['maxSuspiciousTextRatio']}, got {ratio:.4f}"
            )

    text_diagnostics = parse_result.get("textDiagnostics")
    if isinstance(text_diagnostics, dict):
        diagnostic_sample_count = int(text_diagnostics.get("sampleCount", 0))
        issue_sample_count = int(text_diagnostics.get("issueSampleCount", 0))
        issue_counts = text_diagnostics.get("issueCounts")
        if expected.get("requiresText") and number("textPrimitiveCount") > 0 and diagnostic_sample_count <= 0:
            warning("text exists but parser probe returned no text diagnostic samples")
        if issue_sample_count > 0:
            warning(f"text diagnostics flagged {issue_sample_count} sampled text items: {issue_counts}")
        if "maxTextDiagnosticIssueRatio" in expected and diagnostic_sample_count > 0:
            issue_ratio = issue_sample_count / diagnostic_sample_count
            if issue_ratio > float(expected["maxTextDiagnosticIssueRatio"]):
                error(
                    "text diagnostic issue ratio exceeded: "
                    f"expected <= {expected['maxTextDiagnosticIssueRatio']}, got {issue_ratio:.4f}"
                )
    elif expected.get("requiresText") and number("textPrimitiveCount") > 0:
        warning("text exists but parser probe did not include text diagnostics")

    return findings


def run_parser_regression(
    report: dict[str, Any],
    probe: Path,
    timeout: int,
) -> list[Finding]:
    findings: list[Finding] = []
    parsed_count = 0
    failed_count = 0

    for sample in report["samples"]:
        if sample.get("status") != "ready" or not sample.get("exists"):
            continue
        path_text = sample.get("absolutePath")
        if not isinstance(path_text, str):
            continue
        sample_path = Path(path_text)
        try:
            parse_result = run_probe(probe, sample_path, timeout=timeout)
        except subprocess.TimeoutExpired:
            parse_result = {
                "ok": False,
                "errorMessage": f"parser probe timed out after {timeout}s",
                "parseMilliseconds": timeout * 1000,
            }
        attach_xref_resolution(parse_result, sample_path)
        attach_text_diagnostics(parse_result)
        sample["parser"] = parse_result
        parsed_count += 1
        if not parse_result.get("ok"):
            failed_count += 1
        findings.extend(compare_expected(sample, parse_result))

    report["parser"] = {
        "probe": str(probe),
        "readySamplesParsed": parsed_count,
        "failedSamples": failed_count,
    }
    return findings


def print_summary(report: dict[str, Any], findings: list[Finding]) -> None:
    status_counts = report["statusCounts"]
    print(f"DWG regression samples: {report['sampleCount']}")
    print(
        "Status: "
        + ", ".join(f"{key}={value}" for key, value in status_counts.items())
    )
    parser = report.get("parser")
    if isinstance(parser, dict):
        print(
            "Parser: "
            f"ready={parser.get('readySamplesParsed', 0)}, "
            f"failed={parser.get('failedSamples', 0)}"
        )
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
        help="Only validate inventory; do not build or run the parser probe.",
    )
    parser.add_argument(
        "--parser",
        type=Path,
        help="Existing dwg_probe executable. If omitted, the script builds one.",
    )
    parser.add_argument(
        "--parser-timeout",
        type=int,
        default=120,
        help="Seconds before a single ready sample parse is treated as failed.",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=DEFAULT_PROBE_BUILD_DIR,
        help="Directory for the generated parser probe executable.",
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
        if not args.skip_parser and report["statusCounts"].get("ready", 0) > 0:
            if args.parser:
                probe = args.parser if args.parser.is_absolute() else repo_root / args.parser
            else:
                build_dir = args.build_dir if args.build_dir.is_absolute() else repo_root / args.build_dir
                probe = build_probe(repo_root, build_dir)
            parser_findings = run_parser_regression(
                report,
                probe=probe,
                timeout=max(args.parser_timeout, 1),
            )
            findings.extend(parser_findings)
            report["findings"] = [finding.__dict__ for finding in findings]
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
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
