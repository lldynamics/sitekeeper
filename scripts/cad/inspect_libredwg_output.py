#!/usr/bin/env python3
"""Inspect raw LibreDWG JSON/DXF outputs and report whether geometry exists."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


DRAWABLE_ENTITY_TYPES = {
    "LINE",
    "LWPOLYLINE",
    "POLYLINE",
    "VERTEX",
    "SEQEND",
    "CIRCLE",
    "ARC",
    "ELLIPSE",
    "SPLINE",
    "TEXT",
    "MTEXT",
    "INSERT",
    "ATTRIB",
    "ATTDEF",
    "DIMENSION",
    "HATCH",
    "IMAGE",
    "UNDERLAY",
}

REQUIRED_ENTITY_TYPES = [
    "LINE",
    "LWPOLYLINE",
    "POLYLINE",
    "CIRCLE",
    "ARC",
    "TEXT",
    "MTEXT",
    "INSERT",
    "HATCH",
    "DIMENSION",
]


def file_size(path: Path) -> int:
    return path.stat().st_size if path.exists() else 0


def read_text(path: Path, limit: int = 16_384) -> str:
    if not path.exists():
        return ""
    data = path.read_bytes()[:limit]
    return data.decode("utf-8", errors="replace")


def stderr_summary(path: Path, max_lines: int = 40) -> str:
    text = read_text(path, limit=64 * 1024)
    lines = [line.rstrip() for line in text.splitlines() if line.strip()]
    if len(lines) <= max_lines:
        return "\n".join(lines)
    head_count = max_lines // 2
    tail_count = max_lines - head_count
    return "\n".join(lines[:head_count] + ["..."] + lines[-tail_count:])


def normalize_type(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip().upper().replace("-", "_")
    if not text:
        return None
    prefixes = [
        "DWG_ENTITY_",
        "DWG_OBJECT_",
        "ACDB",
    ]
    for prefix in prefixes:
        if text.startswith(prefix):
            text = text[len(prefix):]
    if text.startswith("ENT_"):
        text = text[4:]
    return text


def json_entity_type(item: dict[str, Any]) -> str | None:
    for key in ("entity", "entityType", "object", "type", "name", "class"):
        candidate = normalize_type(item.get(key))
        if candidate in DRAWABLE_ENTITY_TYPES:
            return candidate
    return None


def scan_json_entities(value: Any, counts: Counter[str]) -> None:
    if isinstance(value, dict):
        entity_type = json_entity_type(value)
        if entity_type is not None:
            counts[entity_type] += 1
        for child in value.values():
            scan_json_entities(child, counts)
    elif isinstance(value, list):
        for child in value:
            scan_json_entities(child, counts)


def inspect_json(path: Path) -> tuple[int, dict[str, int], str | None]:
    if not path.exists() or path.stat().st_size == 0:
        return 0, {}, None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as error:  # noqa: BLE001 - probe records parse failure.
        return 0, {}, f"{type(error).__name__}: {error}"
    counts: Counter[str] = Counter()
    scan_json_entities(payload, counts)
    return sum(counts.values()), dict(sorted(counts.items())), None


def dxf_pairs(path: Path) -> list[tuple[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    pairs: list[tuple[str, str]] = []
    index = 0
    while index + 1 < len(lines):
        code = lines[index].strip()
        value = lines[index + 1].strip()
        pairs.append((code, value))
        index += 2
    return pairs


def inspect_dxf(path: Path) -> tuple[int, dict[str, int]]:
    pairs = dxf_pairs(path)
    counts: Counter[str] = Counter()
    in_entities = False
    pending_section = False
    for code, value in pairs:
        normalized = normalize_type(value) or ""
        if code == "0" and normalized == "SECTION":
            pending_section = True
            in_entities = False
            continue
        if pending_section and code == "2":
            in_entities = normalized == "ENTITIES"
            pending_section = False
            continue
        if code == "0" and normalized == "ENDSEC":
            in_entities = False
            pending_section = False
            continue
        if in_entities and code == "0":
            if normalized in {"EOF", "SECTION", "ENDSEC"}:
                continue
            counts[normalized] += 1
    return sum(counts.values()), dict(sorted(counts.items()))


def merge_counts(*items: dict[str, int]) -> dict[str, int]:
    counter: Counter[str] = Counter()
    for item in items:
        counter.update(item)
    return dict(sorted(counter.items()))


def parse_exit_code(value: str | None) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except ValueError:
        return None


def verdict_for(
    libre_dwg_available: bool,
    exit_codes: list[int | None],
    raw_counts: list[int],
) -> str:
    if not libre_dwg_available:
        return "LIBREDWG_FAILED"
    if any((code == 0) for code in exit_codes) and any(count > 0 for count in raw_counts):
        return "LIBREDWG_HAS_GEOMETRY"
    if any((code == 0) for code in exit_codes):
        return "NO_GEOMETRY_FROM_LIBREDWG"
    return "LIBREDWG_FAILED"


def report_markdown(result: dict[str, Any], stderr_sections: dict[str, str]) -> str:
    lines = [
        "# LibreDWG Probe Report",
        "",
        f"- File: `{result.get('fileName', '-')}`",
        f"- File size: `{result.get('fileSize', 0)}` bytes",
        f"- Verdict: `{result['verdict']}`",
        f"- LibreDWG available: `{str(result['libreDwgAvailable']).lower()}`",
        "",
    ]
    if result["verdict"] != "LIBREDWG_HAS_GEOMETRY":
        lines.extend([
            "**LibreDWG did not provide drawable geometry.**",
            "",
        ])

    lines.extend([
        "## Commands",
        "",
        "| Command | Exit | Output size | Raw entities |",
        "| --- | ---: | ---: | ---: |",
        f"| dwgread JSON | {result.get('dwgreadJsonExitCode')} | {result.get('jsonFileSize', 0)} | {result.get('jsonRawEntityCount', 0)} |",
        f"| dwgread DXF | {result.get('dwgreadDxfExitCode')} | {result.get('dxfFileSize', 0)} | {result.get('dxfRawEntityCount', 0)} |",
        f"| dwg2dxf | {result.get('dwg2dxfExitCode')} | {result.get('dxf2FileSize', 0)} | {result.get('dxf2RawEntityCount', 0)} |",
        "",
        "## Entity Types",
        "",
    ])

    raw_types = result.get("rawEntityTypes", {})
    if raw_types:
        lines.extend([
            "| Type | Count |",
            "| --- | ---: |",
        ])
        for entity_type, count in raw_types.items():
            lines.append(f"| {entity_type} | {count} |")
    else:
        lines.append("No raw drawable entity types were detected.")

    lines.extend([
        "",
        "## Required Type Presence",
        "",
        "| Type | Present |",
        "| --- | --- |",
    ])
    contains = result.get("contains", {})
    for entity_type in REQUIRED_ENTITY_TYPES:
        lines.append(f"| {entity_type} | {'yes' if contains.get(entity_type) else 'no'} |")

    lines.extend(["", "## stderr Summary", ""])
    for title, text in stderr_sections.items():
        lines.extend([f"### {title}", "", "```text", text or "(empty)", "```", ""])
    return "\n".join(lines).rstrip() + "\n"


def pipeline_trace(result: dict[str, Any]) -> dict[str, Any]:
    raw_count = max(
        int(result.get("jsonRawEntityCount", 0)),
        int(result.get("dxfRawEntityCount", 0)),
        int(result.get("dxf2RawEntityCount", 0)),
    )
    if result["verdict"] == "LIBREDWG_HAS_GEOMETRY":
        failure_stage = "app_import_not_evaluated"
    elif result["verdict"] == "NO_GEOMETRY_FROM_LIBREDWG":
        failure_stage = "libredwg_no_geometry"
    else:
        failure_stage = "libredwg_failed"
    return {
        "fileName": result.get("fileName"),
        "fileSize": result.get("fileSize"),
        "dwgVersion": result.get("dwgVersion"),
        "libreDwgAvailable": result.get("libreDwgAvailable"),
        "dwgreadJsonExitCode": result.get("dwgreadJsonExitCode"),
        "dwgreadDxfExitCode": result.get("dwgreadDxfExitCode"),
        "dwg2dxfExitCode": result.get("dwg2dxfExitCode"),
        "jsonRawEntityCount": result.get("jsonRawEntityCount", 0),
        "dxfRawEntityCount": result.get("dxfRawEntityCount", 0),
        "adapterEntityCount": 0,
        "databaseEntityCount": 0,
        "drawableEntityCount": 0,
        "renderCommandCount": 0,
        "extents": None,
        "currentLayout": None,
        "visibleLayerCount": 0,
        "viewport": None,
        "openState": "diagnosticOnly" if raw_count == 0 else "unknown",
        "failureStage": failure_stage,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect LibreDWG probe artifacts.")
    parser.add_argument("--dwg", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, default=Path("build/cad-probe"))
    parser.add_argument("--dwgread-json-exit-code")
    parser.add_argument("--dwgread-dxf-exit-code")
    parser.add_argument("--dwg2dxf-exit-code")
    parser.add_argument("--dwgread-available", action="store_true")
    parser.add_argument("--dwg2dxf-available", action="store_true")
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    json_path = args.out_dir / "out.json"
    dxf_path = args.out_dir / "out.dxf"
    dxf2_path = args.out_dir / "out2.dxf"

    json_count, json_types, json_error = inspect_json(json_path)
    dxf_count, dxf_types = inspect_dxf(dxf_path)
    dxf2_count, dxf2_types = inspect_dxf(dxf2_path)
    raw_types = merge_counts(json_types, dxf_types, dxf2_types)

    dwg_header = args.dwg.read_bytes()[:6].decode("ascii", errors="ignore") if args.dwg.exists() else ""
    dwg_version = dwg_header if dwg_header.startswith("AC") else None
    libre_dwg_available = args.dwgread_available or args.dwg2dxf_available
    exit_codes = [
        parse_exit_code(args.dwgread_json_exit_code),
        parse_exit_code(args.dwgread_dxf_exit_code),
        parse_exit_code(args.dwg2dxf_exit_code),
    ]
    raw_counts = [json_count, dxf_count, dxf2_count]
    result = {
        "libreDwgAvailable": libre_dwg_available,
        "dwgreadAvailable": args.dwgread_available,
        "dwg2dxfAvailable": args.dwg2dxf_available,
        "dwgreadJsonExitCode": exit_codes[0],
        "dwgreadDxfExitCode": exit_codes[1],
        "dwg2dxfExitCode": exit_codes[2],
        "jsonFileSize": file_size(json_path),
        "dxfFileSize": file_size(dxf_path),
        "dxf2FileSize": file_size(dxf2_path),
        "jsonRawEntityCount": json_count,
        "dxfRawEntityCount": dxf_count,
        "dxf2RawEntityCount": dxf2_count,
        "rawEntityTypes": raw_types,
        "jsonEntityTypes": json_types,
        "dxfEntityTypes": dxf_types,
        "dxf2EntityTypes": dxf2_types,
        "contains": {entity_type: raw_types.get(entity_type, 0) > 0 for entity_type in REQUIRED_ENTITY_TYPES},
        "jsonParseError": json_error,
        "fileName": args.dwg.name,
        "fileSize": file_size(args.dwg),
        "dwgVersion": dwg_version,
        "verdict": "",
    }
    result["verdict"] = verdict_for(libre_dwg_available, exit_codes, raw_counts)

    stderr_sections = {
        "dwgread JSON": stderr_summary(args.out_dir / "dwgread_json.log"),
        "dwgread DXF": stderr_summary(args.out_dir / "dwgread_dxf.log"),
        "dwg2dxf": stderr_summary(args.out_dir / "dwg2dxf.log"),
    }
    result["stderrSummary"] = stderr_sections

    (args.out_dir / "probe_result.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (args.out_dir / "probe_report.md").write_text(
        report_markdown(result, stderr_sections),
        encoding="utf-8",
    )
    (args.out_dir / "pipeline_trace.json").write_text(
        json.dumps(pipeline_trace(result), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(args.out_dir / "probe_report.md")
    print(args.out_dir / "probe_result.json")
    print(args.out_dir / "pipeline_trace.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
