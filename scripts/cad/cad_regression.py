#!/usr/bin/env python3
"""Batch CAD regression for local DWG/DXF samples with diagnostics and report."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cad_diagnose import (
    as_dict,
    as_int,
    as_list,
    build_diagnostics,
    write_text_trace_jsonl,
)
from dwg_regression import (
    DEFAULT_PROBE_BUILD_DIR,
    attach_text_diagnostics,
    attach_xref_resolution,
    build_probe,
    repo_root_from_script,
    run_probe,
)


SUPPORTED_EXTENSIONS = {".dwg", ".dxf", ".json"}
PROBE_EXTENSIONS = {".dwg"}
LAUNCH_SAMPLE_TARGET_COUNT = 30
LAUNCH_NORMAL_OPEN_TARGET_COUNT = 27
MOJIBAKE_RATIO_LIMIT = 0.01
UNSUPPORTED_RATIO_LIMIT = 0.10
QUALITY_SCORE_MINIMUM = 60
SECOND_OPEN_TARGET_MS = 3_000
SMALL_DWG_LIMIT_BYTES = 100 * 1024 * 1024
TIANZHENG_HINT_TOKENS = (
    "天正",
    "tianzheng",
    "tarch",
    "tch",
    "t20",
    "t3",
    "aic",
    "aec",
    "acdbproxyentity",
    "proxy",
)


@dataclass
class ArtifactResult:
    generated: bool
    path: str | None
    reason: str | None
    method: str | None
    milliseconds: int


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def discover_samples(sample_root: Path) -> list[Path]:
    files = [
        path
        for path in sample_root.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    ]
    files.sort(key=lambda path: str(path).lower())
    return files


def requires_probe(sample_files: list[Path]) -> bool:
    return any(path.suffix.lower() in PROBE_EXTENSIONS for path in sample_files)


def relative_artifact_path(output_root: Path, path: Path) -> str:
    return str(path.relative_to(output_root))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run_process(command: list[str], timeout_seconds: int) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=max(timeout_seconds, 1),
        check=False,
    )


def generate_quicklook_thumbnail(
    source_file: Path,
    output_file: Path,
    pixel_size: int,
) -> ArtifactResult:
    qlmanage = shutil.which("qlmanage")
    if qlmanage is None:
        return ArtifactResult(False, None, "qlmanage not found", None, 0)

    start = time.perf_counter()
    temp_dir = Path(tempfile.mkdtemp(prefix="cad-regression-thumb-"))
    try:
        try:
            completed = run_process(
                [
                    qlmanage,
                    "-t",
                    "-s",
                    str(max(pixel_size, 256)),
                    "-o",
                    str(temp_dir),
                    str(source_file),
                ],
                timeout_seconds=90,
            )
        except subprocess.TimeoutExpired:
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            return ArtifactResult(False, None, "quicklook thumbnail timeout", "quicklook-thumbnail", elapsed_ms)
        elapsed_ms = int((time.perf_counter() - start) * 1000)
        if completed.returncode != 0:
            stderr = completed.stderr.strip() or completed.stdout.strip() or "unknown quicklook error"
            return ArtifactResult(False, None, stderr, "quicklook-thumbnail", elapsed_ms)

        candidates = sorted(temp_dir.glob("*.png"), key=lambda path: path.stat().st_mtime, reverse=True)
        if not candidates:
            return ArtifactResult(False, None, "quicklook produced no thumbnail", "quicklook-thumbnail", elapsed_ms)

        output_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(candidates[0], output_file)
        return ArtifactResult(
            True,
            str(output_file),
            None,
            "quicklook-thumbnail",
            elapsed_ms,
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def generate_pdf_preview_from_thumbnail(
    thumbnail_file: Path,
    output_file: Path,
) -> ArtifactResult:
    if not thumbnail_file.exists():
        return ArtifactResult(False, None, "thumbnail not available", None, 0)

    sips = shutil.which("sips")
    if sips is None:
        return ArtifactResult(False, None, "sips not found", None, 0)

    start = time.perf_counter()
    try:
        completed = run_process(
            [sips, "-s", "format", "pdf", str(thumbnail_file), "--out", str(output_file)],
            timeout_seconds=45,
        )
    except subprocess.TimeoutExpired:
        elapsed_ms = int((time.perf_counter() - start) * 1000)
        return ArtifactResult(False, None, "preview pdf generation timeout", "thumbnail-to-pdf", elapsed_ms)
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    if completed.returncode != 0 or not output_file.exists():
        stderr = completed.stderr.strip() or completed.stdout.strip() or "failed to generate preview pdf"
        return ArtifactResult(False, None, stderr, "thumbnail-to-pdf", elapsed_ms)
    return ArtifactResult(True, str(output_file), None, "thumbnail-to-pdf", elapsed_ms)


def create_vector_snapshot_proxy(
    diagnostics: dict[str, Any],
    thumbnail_file: Path,
    output_file: Path,
) -> ArtifactResult:
    probe = as_dict(diagnostics.get("probe"))
    parse_ok = bool(probe.get("ok"))
    primitive_count = as_int(probe.get("primitiveCount"))
    viewer_mode = str(diagnostics.get("viewerMode") or "")
    can_vector = parse_ok and primitive_count > 0 and viewer_mode == "vector"
    if not can_vector:
        return ArtifactResult(False, None, "vector viewer not suggested for this sample", None, 0)
    if not thumbnail_file.exists():
        return ArtifactResult(False, None, "thumbnail not available for vector snapshot proxy", None, 0)

    start = time.perf_counter()
    output_file.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(thumbnail_file, output_file)
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    return ArtifactResult(
        True,
        str(output_file),
        None,
        "quicklook-thumbnail-proxy",
        elapsed_ms,
    )


def normalize_entity_kind(raw: Any, entity: dict[str, Any]) -> str:
    kind = str(raw or "").strip()
    if not kind:
        if entity.get("rawText") is not None or entity.get("displayText") is not None or entity.get("text") is not None:
            kind = "TEXT"
        elif entity.get("blockName") is not None:
            kind = "INSERT"
        elif entity.get("radius") is not None:
            kind = "CIRCLE"
        elif entity.get("points") is not None:
            kind = "LWPOLYLINE"
        elif entity.get("start") is not None and entity.get("end") is not None:
            kind = "LINE"
        else:
            kind = "UNSUPPORTED"
    normalized = kind.replace("-", "_").replace(" ", "_")
    mapping = {
        "line": "LINE",
        "polyline": "POLYLINE",
        "lwPolyline": "LWPOLYLINE",
        "lw_polyline": "LWPOLYLINE",
        "circle": "CIRCLE",
        "arc": "ARC",
        "ellipse": "ELLIPSE",
        "spline": "SPLINE",
        "text": "TEXT",
        "mtext": "MTEXT",
        "attrib": "ATTRIB",
        "attdef": "ATTDEF",
        "insert": "INSERT",
        "dimension": "DIMENSION",
        "hatch": "HATCH",
        "image": "IMAGE",
        "table": "TABLE",
        "xref": "XREF",
        "proxy": "PROXY",
        "unsupported": "UNSUPPORTED",
        "blockReference": "INSERT",
        "block_reference": "INSERT",
    }
    return mapping.get(kind, mapping.get(normalized, normalized.upper()))


def text_from_entity(entity: dict[str, Any]) -> str:
    text = entity.get("displayText")
    if text is None:
        text = entity.get("text")
    if text is None:
        text = entity.get("rawText")
    if isinstance(text, dict):
        text = text.get("displayText") or text.get("rawText") or ""
    return str(text or "")


def raw_text_from_entity(entity: dict[str, Any]) -> str:
    text = entity.get("rawText")
    if text is None and isinstance(entity.get("text"), dict):
        text = as_dict(entity.get("text")).get("rawText")
    if text is None:
        text = text_from_entity(entity)
    return str(text or "")


def read_point(entity: dict[str, Any], *keys: str) -> dict[str, float]:
    for key in keys:
        value = entity.get(key)
        if isinstance(value, dict):
            return {
                "x": as_float(value.get("x")),
                "y": as_float(value.get("y")),
            }
    return {"x": 0.0, "y": 0.0}


def parse_json_fixture(sample_path: Path) -> dict[str, Any]:
    start = time.perf_counter()
    try:
        data = json.loads(sample_path.read_text(encoding="utf-8"))
    except UnicodeDecodeError:
        data = json.loads(sample_path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError("JSON CAD fixture root must be an object")

    entities = as_list(data.get("entities"))
    layers = as_list(data.get("layers"))
    layouts = as_list(data.get("layouts"))
    blocks = as_list(data.get("blocks"))
    text_styles = as_list(data.get("textStyles"))
    xrefs = as_list(data.get("xrefs"))

    entity_counts: dict[str, int] = {}
    unsupported_counts: dict[str, int] = {}
    unsupported_entities: list[dict[str, Any]] = []
    text_samples: list[dict[str, Any]] = []
    text_trace: list[dict[str, Any]] = []
    primitive_count = 0

    for index, raw_entity in enumerate(entities):
        if not isinstance(raw_entity, dict):
            continue
        kind = normalize_entity_kind(raw_entity.get("type") or raw_entity.get("kind"), raw_entity)
        entity_counts[kind] = entity_counts.get(kind, 0) + 1
        entity_id = str(raw_entity.get("id") or raw_entity.get("handle") or raw_entity.get("sourceHandle") or f"json-{index + 1}")
        layer_id = str(raw_entity.get("layerID") or raw_entity.get("layerId") or raw_entity.get("layer") or "0")
        layout_id = str(raw_entity.get("layoutID") or raw_entity.get("layoutId") or "model")
        unsupported_reason = str(raw_entity.get("unsupportedReason") or raw_entity.get("reason") or "").strip()
        unsupported = kind in {"UNSUPPORTED", "PROXY", "XREF"} or bool(unsupported_reason)
        if unsupported:
            unsupported_counts[kind] = unsupported_counts.get(kind, 0) + 1
            unsupported_entities.append({
                "entityId": entity_id,
                "entityType": kind,
                "layerId": layer_id,
                "layoutId": layout_id,
                "sourceHandle": str(raw_entity.get("sourceHandle") or raw_entity.get("handle") or ""),
                "reason": unsupported_reason or f"{kind} is not supported by this fixture importer.",
            })
        else:
            primitive_count += 1

        if kind in {"TEXT", "MTEXT", "ATTRIB", "ATTDEF"} or raw_entity.get("rawText") is not None:
            text = as_dict(raw_entity.get("text")) if isinstance(raw_entity.get("text"), dict) else {}
            display_text = str(
                raw_entity.get("displayText")
                or text.get("displayText")
                or raw_entity.get("text")
                or text.get("rawText")
                or raw_entity.get("rawText")
                or ""
            )
            raw_text = raw_text_from_entity(raw_entity)
            point = read_point(raw_entity, "insertionPoint", "start", "point")
            style_name = str(raw_entity.get("textStyleName") or text.get("styleName") or raw_entity.get("textStyleId") or "Standard")
            font_file = str(raw_entity.get("fontFile") or text.get("fontFile") or "")
            big_font_file = str(raw_entity.get("bigFontFile") or text.get("bigFontFile") or "")
            warnings = raw_entity.get("warnings") or text.get("warnings") or []
            warnings = [str(item) for item in warnings] if isinstance(warnings, list) else []
            sample = {
                "kind": kind,
                "rawText": raw_text,
                "text": display_text,
                "decodedText": str(raw_entity.get("decodedText") or text.get("decodedText") or display_text),
                "displayText": display_text,
                "textStyleName": style_name,
                "fontFile": font_file,
                "bigFontFile": big_font_file,
                "normalizeWarnings": warnings,
                "insertionPoint": point,
            }
            text_samples.append(sample)
            text_trace.append({
                "entityId": entity_id,
                "entityType": kind.lower(),
                "rawText": raw_text,
                "decodedText": sample["decodedText"],
                "normalizedText": display_text,
                "displayText": display_text,
                "rawTextFromLibreDWG": raw_text,
                "jsonText": display_text,
                "finalDisplayText": display_text,
                "textStyleName": style_name,
                "fontFile": font_file,
                "bigFontFile": big_font_file,
                "selectedUIFontName": str(text.get("selectedFontName") or raw_entity.get("selectedFontName") or ""),
                "usedSHXGlyphFallback": False,
                "warnings": warnings,
            })

    elapsed_ms = max(int((time.perf_counter() - start) * 1000), 1)
    xref_entries = []
    for raw_xref in xrefs:
        if not isinstance(raw_xref, dict):
            continue
        xref_entries.append({
            "name": str(raw_xref.get("name") or raw_xref.get("id") or "xref"),
            "savedPath": str(raw_xref.get("path") or raw_xref.get("savedPath") or ""),
            "localStatus": str(raw_xref.get("localStatus") or ("resolved" if raw_xref.get("isResolved") else "missing")),
        })

    return {
        "ok": True,
        "fixtureFormat": "intermediate-json",
        "dwgVersionDescription": "intermediate-json",
        "effectiveCodepage": "utf-8",
        "layoutCount": len(layouts) or 1,
        "layerCount": len(layers) or 1,
        "blockCount": len(blocks),
        "textStyleCount": len(text_styles),
        "entityCountByType": entity_counts,
        "unsupportedEntityCountByType": unsupported_counts,
        "unsupportedEntities": unsupported_entities,
        "unsupportedEntitySummary": ", ".join(f"{key}:{value}" for key, value in sorted(unsupported_counts.items())),
        "unsupportedEntityCount": sum(unsupported_counts.values()),
        "totalObjectCount": len(entities),
        "primitiveCount": primitive_count,
        "estimatedPrimitiveMemory": primitive_count * 128,
        "parseMilliseconds": elapsed_ms,
        "textSamples": text_samples,
        "textTrace": text_trace,
        "textStyles": [
            {
                "styleName": str(style.get("name") or style.get("styleName") or style.get("id") or "Standard"),
                "fontFile": str(style.get("fontName") or style.get("fontFile") or ""),
                "bigFontFile": str(style.get("bigFontName") or style.get("bigFontFile") or ""),
                "usedByCount": as_int(style.get("usedByCount")),
            }
            for style in text_styles
            if isinstance(style, dict)
        ],
        "xrefs": xref_entries,
    }


def parse_dxf_fixture(sample_path: Path) -> dict[str, Any]:
    start = time.perf_counter()
    lines = sample_path.read_text(encoding="utf-8", errors="replace").splitlines()
    groups: list[tuple[str, str]] = []
    for index in range(0, len(lines) - 1, 2):
        groups.append((lines[index].strip(), lines[index + 1].rstrip("\n")))

    entity_counts: dict[str, int] = {}
    text_samples: list[dict[str, Any]] = []
    text_trace: list[dict[str, Any]] = []
    primitive_count = 0
    layers: set[str] = set()
    index = 0
    while index < len(groups):
        code, value = groups[index]
        if code != "0":
            index += 1
            continue
        kind = value.strip().upper()
        if kind not in {"LINE", "LWPOLYLINE", "POLYLINE", "CIRCLE", "ARC", "TEXT", "MTEXT", "INSERT", "HATCH", "DIMENSION"}:
            index += 1
            continue
        entity: dict[str, list[str]] = {}
        index += 1
        while index < len(groups) and groups[index][0] != "0":
            entity.setdefault(groups[index][0], []).append(groups[index][1])
            index += 1
        layer = (entity.get("8") or ["0"])[0]
        layers.add(layer)
        entity_counts[kind] = entity_counts.get(kind, 0) + 1
        primitive_count += 1
        if kind in {"TEXT", "MTEXT"}:
            text_value = " ".join(entity.get("1", []) + entity.get("3", [])).strip()
            style_name = (entity.get("7") or ["Standard"])[0]
            entity_id = f"dxf-text-{len(text_samples) + 1}"
            sample = {
                "kind": kind,
                "rawText": text_value,
                "text": text_value,
                "decodedText": text_value,
                "displayText": text_value,
                "textStyleName": style_name,
                "fontFile": "",
                "bigFontFile": "",
                "normalizeWarnings": [],
            }
            text_samples.append(sample)
            text_trace.append({
                "entityId": entity_id,
                "entityType": kind.lower(),
                "rawText": text_value,
                "decodedText": text_value,
                "normalizedText": text_value,
                "displayText": text_value,
                "rawTextFromLibreDWG": text_value,
                "jsonText": text_value,
                "finalDisplayText": text_value,
                "textStyleName": style_name,
                "fontFile": "",
                "bigFontFile": "",
                "selectedUIFontName": "",
                "usedSHXGlyphFallback": False,
                "warnings": [],
            })

    elapsed_ms = max(int((time.perf_counter() - start) * 1000), 1)
    return {
        "ok": True,
        "fixtureFormat": "simple-dxf",
        "dwgVersionDescription": "dxf",
        "effectiveCodepage": "utf-8",
        "layoutCount": 1,
        "layerCount": len(layers) or 1,
        "blockCount": 0,
        "textStyleCount": 0,
        "entityCountByType": entity_counts,
        "unsupportedEntityCountByType": {},
        "unsupportedEntities": [],
        "unsupportedEntitySummary": "",
        "unsupportedEntityCount": 0,
        "totalObjectCount": sum(entity_counts.values()),
        "primitiveCount": primitive_count,
        "estimatedPrimitiveMemory": primitive_count * 128,
        "parseMilliseconds": elapsed_ms,
        "textSamples": text_samples,
        "textTrace": text_trace,
        "textStyles": [],
        "xrefs": [],
    }


def bool_to_yes_no(value: bool) -> str:
    return "是" if value else "否"


def status_label(passed: bool | None) -> str:
    if passed is None:
        return "未测量"
    return "通过" if passed else "未通过"


def as_float(value: Any) -> float:
    if isinstance(value, bool):
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return 0.0


def has_mojibake(diagnostics: dict[str, Any]) -> bool:
    trace_summary = as_dict(diagnostics.get("textTraceSummary"))
    suspicious_samples = as_list(diagnostics.get("suspiciousMojibakeSamples"))
    return (
        len(suspicious_samples) > 0
        or as_int(trace_summary.get("mojibakeLikeCount")) > 0
        or as_int(trace_summary.get("replacementCharacterCount")) > 0
        or as_int(trace_summary.get("questionMarkOnlyCount")) > 0
    )


def text_issue_counts(diagnostics: dict[str, Any]) -> tuple[int, int]:
    trace_summary = as_dict(diagnostics.get("textTraceSummary"))
    total = as_int(trace_summary.get("totalTextCount"))
    issue_count = (
        as_int(trace_summary.get("mojibakeLikeCount"))
        + as_int(trace_summary.get("replacementCharacterCount"))
        + as_int(trace_summary.get("questionMarkOnlyCount"))
    )
    return issue_count, total


def text_issue_ratio(diagnostics: dict[str, Any]) -> float:
    issue_count, total = text_issue_counts(diagnostics)
    trace_ratio = safe_div(issue_count, total)
    summary_ratio = as_float(as_dict(diagnostics.get("summary")).get("mojibakeSampleRatio"))
    return max(trace_ratio, summary_ratio)


def has_missing_fonts(diagnostics: dict[str, Any]) -> bool:
    return bool(as_list(diagnostics.get("missingFonts")) or as_list(diagnostics.get("missingBigFonts")))


def has_missing_normal_fonts(diagnostics: dict[str, Any]) -> bool:
    return bool(as_list(diagnostics.get("missingFonts")))


def has_missing_big_fonts(diagnostics: dict[str, Any]) -> bool:
    return bool(as_list(diagnostics.get("missingBigFonts")))


def has_missing_xrefs(diagnostics: dict[str, Any]) -> bool:
    return bool(as_list(diagnostics.get("missingXrefs")))


def unsupported_ratio(diagnostics: dict[str, Any]) -> float:
    summary = as_dict(diagnostics.get("summary"))
    value = summary.get("unsupportedRatio")
    return float(value) if isinstance(value, (int, float)) else 0.0


def parse_ok(diagnostics: dict[str, Any]) -> bool:
    return bool(as_dict(diagnostics.get("probe")).get("ok"))


def can_enter_vector_viewer(diagnostics: dict[str, Any]) -> bool:
    probe = as_dict(diagnostics.get("probe"))
    return (
        bool(probe.get("ok"))
        and as_int(probe.get("primitiveCount")) > 0
        and str(diagnostics.get("viewerMode") or "") == "vector"
    )


def has_tianzheng_risk(diagnostics: dict[str, Any]) -> bool:
    probe = as_dict(diagnostics.get("probe"))
    pieces: list[str] = [
        str(diagnostics.get("fileName") or ""),
        str(diagnostics.get("dwgVersion") or ""),
        str(probe.get("unsupportedEntitySummary") or ""),
        str(probe.get("blockReferenceSummary") or ""),
    ]
    pieces.extend(str(item) for item in as_list(diagnostics.get("warnings")))
    pieces.extend(str(key) for key in as_dict(diagnostics.get("entityCountByType")).keys())
    pieces.extend(str(key) for key in as_dict(diagnostics.get("unsupportedEntityCountByType")).keys())
    for xref in as_list(diagnostics.get("xrefs")):
        if isinstance(xref, dict):
            pieces.append(str(xref.get("name") or ""))
            pieces.append(str(xref.get("savedPath") or ""))
    blob = " ".join(pieces).lower()
    return any(token.lower() in blob for token in TIANZHENG_HINT_TOKENS)


def content_risk_reasons(diagnostics: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    summary = as_dict(diagnostics.get("summary"))
    probe = as_dict(diagnostics.get("probe"))
    primitive_count = as_int(summary.get("drawablePrimitiveTotal")) or as_int(probe.get("primitiveCount"))
    if primitive_count <= 0:
        reasons.append("无可绘制图元，主要内容不可确认")
    ratio = unsupported_ratio(diagnostics)
    if ratio > UNSUPPORTED_RATIO_LIMIT:
        reasons.append(f"未支持图元比例 {ratio:.2%} 超过 {UNSUPPORTED_RATIO_LIMIT:.0%}")
    unsupported_counts = as_dict(diagnostics.get("unsupportedEntityCountByType"))
    if as_int(unsupported_counts.get("INSERT")) > 0 or as_int(unsupported_counts.get("DIMENSION")) > 0:
        reasons.append("块引用或标注存在未支持风险")
    return reasons


def tianzheng_handling(diagnostics: dict[str, Any]) -> str:
    if not has_tianzheng_risk(diagnostics):
        return "未检测到明显天正/Proxy 风险"
    if can_enter_vector_viewer(diagnostics) and unsupported_ratio(diagnostics) <= UNSUPPORTED_RATIO_LIMIT:
        return "疑似天正/Proxy：当前可进 vector，但仍需人工抽查主要内容"
    return "疑似天正/Proxy：需明确直接支持、转 T3 或接入支持天正的 SDK；当前不计达标"


def evaluate_launch_readiness(
    diagnostics: dict[str, Any],
    first_conversion_ms: int,
    render_ms: int,
) -> dict[str, Any]:
    mode = str(diagnostics.get("viewerMode") or "")
    quality_score = as_int(diagnostics.get("qualityScore"))
    file_size = as_int(diagnostics.get("fileSize"))
    vector_ready = can_enter_vector_viewer(diagnostics)
    content_reasons = content_risk_reasons(diagnostics)
    normal_reasons: list[str] = []

    if not parse_ok(diagnostics):
        normal_reasons.append("DWG 解码失败")
    if mode == "fallback":
        normal_reasons.append("进入异常保护预览，不计入正常打开")
    elif mode != "vector":
        normal_reasons.append(f"viewerMode={mode or 'unknown'}，未进入 vector 主路径")
    if not vector_ready:
        normal_reasons.append("不能进入 vector viewer")
    if quality_score < QUALITY_SCORE_MINIMUM:
        normal_reasons.append(f"qualityScore {quality_score} 低于 {QUALITY_SCORE_MINIMUM}")
    normal_reasons.extend(content_reasons)

    blocking_reasons = list(dict.fromkeys(normal_reasons))
    ratio = text_issue_ratio(diagnostics)
    if ratio >= MOJIBAKE_RATIO_LIMIT:
        blocking_reasons.append(f"中文乱码疑似比例 {ratio:.2%} 不低于 {MOJIBAKE_RATIO_LIMIT:.0%}")
    if has_missing_fonts(diagnostics):
        blocking_reasons.append("仍存在缺失字体/BigFont，用户需要理解字体问题")
    if has_missing_xrefs(diagnostics):
        blocking_reasons.append("存在缺失外部参照")
    if has_tianzheng_risk(diagnostics) and "需明确" in tianzheng_handling(diagnostics):
        blocking_reasons.append("疑似天正/Proxy 图纸未形成直接支持、转 T3 或 SDK 方案")
    second_open_measured = False
    second_open_ms: int | None = None
    if 0 < file_size <= SMALL_DWG_LIMIT_BYTES:
        blocking_reasons.append("100MB 以下二次打开 3 秒指标未接入回归测量")
    pan_zoom_measured = False
    blocking_reasons.append("平移缩放真实帧率未接入回归测量")

    normal_open = len(normal_reasons) == 0
    return {
        "normalOpen": normal_open,
        "normalOpenReasons": normal_reasons,
        "launchReady": len(blocking_reasons) == 0,
        "blockingReasons": blocking_reasons,
        "exceptionProtection": mode == "fallback",
        "mojibakeRatio": ratio,
        "majorContentRisk": bool(content_reasons),
        "majorContentRiskReasons": content_reasons,
        "tianzhengRisk": has_tianzheng_risk(diagnostics),
        "tianzhengHandling": tianzheng_handling(diagnostics),
        "secondOpenMeasured": second_open_measured,
        "secondOpenMilliseconds": second_open_ms,
        "secondOpenTargetMilliseconds": SECOND_OPEN_TARGET_MS,
        "panZoomMeasured": pan_zoom_measured,
        "firstConversionMilliseconds": first_conversion_ms,
        "renderMilliseconds": render_ms,
    }


def is_blank_drawing(diagnostics: dict[str, Any]) -> bool:
    summary = as_dict(diagnostics.get("summary"))
    trace_summary = as_dict(diagnostics.get("textTraceSummary"))
    drawable_count = as_int(summary.get("drawablePrimitiveTotal")) or as_int(as_dict(diagnostics.get("probe")).get("primitiveCount"))
    text_count = as_int(trace_summary.get("totalTextCount"))
    return (not parse_ok(diagnostics)) or (drawable_count + text_count <= 0)


def chinese_readability_status(diagnostics: dict[str, Any]) -> str:
    trace_summary = as_dict(diagnostics.get("textTraceSummary"))
    total_text = as_int(trace_summary.get("totalTextCount"))
    if total_text <= 0:
        return "未测量"
    return "是" if not has_mojibake(diagnostics) else "否"


def build_performance_trace(
    diagnostics: dict[str, Any],
    first_frame_ms: int,
    render_ms: int,
) -> dict[str, Any]:
    summary = as_dict(diagnostics.get("summary"))
    probe = as_dict(diagnostics.get("probe"))
    entity_count = as_int(summary.get("entityTotal")) or as_int(probe.get("totalObjectCount"))
    visible_count = as_int(summary.get("drawablePrimitiveTotal")) or as_int(probe.get("primitiveCount"))
    estimated_memory = as_int(summary.get("estimatedPrimitiveMemory"))
    return {
        "schema": "CADPerformanceTrace/v1",
        "fileSizeBytes": as_int(diagnostics.get("fileSize")),
        "entityCount": entity_count,
        "visibleEntityCount": visible_count,
        "renderCommandCount": visible_count,
        "spatialIndexBuildMs": 0,
        "resolveMs": 0,
        "renderMs": render_ms,
        "firstFrameMs": first_frame_ms,
        "peakMemoryMB": round(estimated_memory / (1024 * 1024), 2),
        "skippedEntityCount": as_int(probe.get("unsupportedEntityCount")) or sum(as_int(value) for value in as_dict(diagnostics.get("unsupportedEntityCountByType")).values()),
        "warnings": [str(item) for item in as_list(diagnostics.get("warnings"))],
    }


def build_unsupported_entities_report(diagnostics: dict[str, Any]) -> dict[str, Any]:
    probe = as_dict(diagnostics.get("probe"))
    raw_entities = as_list(probe.get("unsupportedEntities"))
    entities = [item for item in raw_entities if isinstance(item, dict)]
    counts = as_dict(diagnostics.get("unsupportedEntityCountByType"))
    if not entities and counts:
        entities = [
            {
                "entityType": str(kind),
                "count": as_int(count),
                "reason": "Only aggregate unsupported counts are available for this importer.",
            }
            for kind, count in sorted(counts.items())
        ]
    return {
        "schema": "CADUnsupportedEntities/v1",
        "fileName": str(diagnostics.get("fileName") or ""),
        "unsupportedEntityRatio": unsupported_ratio(diagnostics),
        "unsupportedEntityCountByType": counts,
        "entities": entities,
    }


def build_font_diagnostics_report(diagnostics: dict[str, Any]) -> dict[str, Any]:
    trace_entries = [
        item for item in as_list(diagnostics.get("textTrace"))
        if isinstance(item, dict)
    ]

    def warning_values(entry: dict[str, Any], prefix: str) -> list[str]:
        values: list[str] = []
        seen: set[str] = set()
        for warning in as_list(entry.get("warnings")):
            if not isinstance(warning, str) or not warning.startswith(prefix):
                continue
            value = warning[len(prefix):].strip()
            if value and value not in seen:
                seen.add(value)
                values.append(value)
        return values

    diagnostics_entries: list[dict[str, Any]] = []
    for trace in trace_entries:
        requested = str(trace.get("fontFile") or "").strip() or None
        resolved = str(trace.get("selectedFontName") or "").strip() or "System"
        fallback_reason = str(trace.get("fallbackReason") or "").strip() or None
        font_was_available = bool(trace.get("fontWasAvailable", True))
        missing_fonts = warning_values(trace, "CAD_TEXT_FONT_UNAVAILABLE:")
        missing_big_fonts = warning_values(trace, "CAD_TEXT_BIGFONT_UNAVAILABLE:")
        fallback_used = bool(fallback_reason)
        if not fallback_used and requested:
            fallback_used = requested.casefold() != resolved.casefold()

        diagnostics_entries.append({
            "requestedFont": requested,
            "resolvedFont": resolved,
            "missingFonts": missing_fonts,
            "missingBigFonts": missing_big_fonts,
            "fallbackUsed": fallback_used,
            "fontWasAvailable": font_was_available,
            "fallbackReason": fallback_reason,
        })

    return {
        "schema": "CADFontDiagnostics/v1",
        "fileName": str(diagnostics.get("fileName") or ""),
        "entryCount": len(diagnostics_entries),
        "entries": diagnostics_entries,
    }


def suggest_handling(diagnostics: dict[str, Any]) -> str:
    viewer_mode = str(diagnostics.get("viewerMode") or "")
    quality_score = as_int(diagnostics.get("qualityScore"))
    ratio = unsupported_ratio(diagnostics)
    mojibake = has_mojibake(diagnostics)
    missing_font = has_missing_fonts(diagnostics)
    missing_xref = has_missing_xrefs(diagnostics)
    parse_ok = bool(as_dict(diagnostics.get("probe")).get("ok"))

    if not parse_ok:
        return "解码失败：异常保护预览只能避免白屏；该样本仍需定位解析失败"
    if viewer_mode == "fallback":
        return "已进入异常保护预览：不计入正常打开；需补齐关键图元与文本链路"
    if mojibake and missing_font:
        return "先补项目字体映射与 BigFont，再复测 text trace"
    if mojibake:
        return "先查 codepage 与 MTEXT 控制码归一化链路"
    if missing_xref:
        return "补齐 XREF 本地路径并重跑回归"
    if ratio > 0.30:
        return "未支持图元偏高，优先增强图元覆盖；异常保护只保底不计达标"
    if quality_score < 60:
        return "质量分偏低，先修主路径解析、内容完整性和性能指标"
    return "可继续走 vector 主路径，重点做性能与稳定性优化"


def safe_div(numerator: int, denominator: int) -> float:
    if denominator <= 0:
        return 0.0
    return numerator / denominator


def markdown_escape(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def write_summary_markdown(
    output_path: Path,
    source_file: Path,
    diagnostics: dict[str, Any],
    launch_readiness: dict[str, Any],
    first_conversion_ms: int,
    render_ms: int,
    vector_ready: bool,
    thumbnail: ArtifactResult,
    preview: ArtifactResult,
    render_snapshot: ArtifactResult,
) -> None:
    missing_fonts = as_list(diagnostics.get("missingFonts")) + as_list(diagnostics.get("missingBigFonts"))
    missing_xrefs = as_list(diagnostics.get("missingXrefs"))
    blocking_lines = [
        f"- {reason}"
        for reason in as_list(launch_readiness.get("blockingReasons"))
    ] or ["- 无"]
    lines = [
        f"# CAD Regression Summary - {source_file.name}",
        "",
        f"- viewerMode: `{diagnostics.get('viewerMode')}`",
        f"- qualityScore: `{diagnostics.get('qualityScore')}`",
        f"- 是否乱码: `{bool_to_yes_no(has_mojibake(diagnostics))}`",
        f"- 是否缺字体: `{bool_to_yes_no(bool(missing_fonts))}`",
        f"- 是否缺外部参照: `{bool_to_yes_no(bool(missing_xrefs))}`",
        f"- 未支持图元比例: `{unsupported_ratio(diagnostics):.2%}`",
        f"- 首次转换耗时: `{first_conversion_ms} ms`",
        f"- 渲染耗时: `{render_ms} ms`",
        f"- 是否可进入 vector viewer: `{bool_to_yes_no(vector_ready)}`",
        f"- 正常打开达标: `{bool_to_yes_no(bool(launch_readiness.get('normalOpen')))}`",
        f"- 上线就绪: `{bool_to_yes_no(bool(launch_readiness.get('launchReady')))}`",
        f"- 异常保护: `{bool_to_yes_no(bool(launch_readiness.get('exceptionProtection')))}`",
        f"- 天正/Proxy 处理: {launch_readiness.get('tianzhengHandling')}",
        f"- 建议处理方式: {suggest_handling(diagnostics)}",
        "",
        "## Blocking Reasons",
        "",
        *blocking_lines,
        "",
        "## Artifacts",
        "",
        f"- diagnostics.json: `diagnostics.json`",
        f"- performance_trace.json: `performance_trace.json`",
        f"- text_trace.jsonl: `text_trace.jsonl`",
        f"- font_diagnostics.json: `font_diagnostics.json`",
        f"- unsupported_entities.json: `unsupported_entities.json`",
        f"- thumbnail.png: `{('generated via ' + str(thumbnail.method)) if thumbnail.generated else ('not generated: ' + str(thumbnail.reason))}`",
        f"- preview: `{('generated via ' + str(preview.method)) if preview.generated else ('not generated: ' + str(preview.reason))}`",
        f"- render_snapshot.png: `{('generated via ' + str(render_snapshot.method)) if render_snapshot.generated else ('not generated: ' + str(render_snapshot.reason))}`",
    ]
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_sample(
    sample_path: Path,
    probe: Path | None,
    parser_timeout: int,
) -> dict[str, Any]:
    suffix = sample_path.suffix.lower()
    if suffix == ".json":
        return parse_json_fixture(sample_path)
    if suffix == ".dxf":
        return parse_dxf_fixture(sample_path)

    if probe is None:
        return {
            "ok": False,
            "errorMessage": "DWG parser/import engine is not installed for regression.",
            "parseMilliseconds": 0,
            "unsupportedEntities": [],
        }

    start = time.perf_counter()
    try:
        parse_result = run_probe(probe, sample_path, timeout=max(parser_timeout, 1))
    except subprocess.TimeoutExpired:
        parse_result = {
            "ok": False,
            "errorMessage": f"parser probe timed out after {max(parser_timeout, 1)}s",
            "parseMilliseconds": max(parser_timeout, 1) * 1000,
        }
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    if not isinstance(parse_result, dict):
        parse_result = {"ok": False, "errorMessage": "probe returned invalid payload"}
    parse_result["probeWallMilliseconds"] = max(elapsed_ms, 1)
    return parse_result


def process_one_sample(
    sample_root: Path,
    sample_path: Path,
    output_root: Path,
    probe: Path | None,
    parser_timeout: int,
    font_dirs: list[Path],
    thumbnail_size: int,
) -> dict[str, Any]:
    relative_path = sample_path.relative_to(sample_root)
    sample_output_dir = output_root / "files" / relative_path
    sample_output_dir.mkdir(parents=True, exist_ok=True)

    parse_result = parse_sample(sample_path, probe, parser_timeout)
    attach_xref_resolution(parse_result, sample_path)
    attach_text_diagnostics(parse_result)
    diagnostics = build_diagnostics(sample_path, parse_result, font_dirs)

    diagnostics_path = sample_output_dir / "diagnostics.json"
    write_json(diagnostics_path, diagnostics)

    text_trace_entries = [item for item in as_list(diagnostics.get("textTrace")) if isinstance(item, dict)]
    text_trace_path = sample_output_dir / "text_trace.jsonl"
    write_text_trace_jsonl(text_trace_entries, text_trace_path)
    font_diagnostics_path = sample_output_dir / "font_diagnostics.json"
    write_json(font_diagnostics_path, build_font_diagnostics_report(diagnostics))

    thumbnail_path = sample_output_dir / "thumbnail.png"
    thumbnail = generate_quicklook_thumbnail(sample_path, thumbnail_path, thumbnail_size)
    if not thumbnail.generated and thumbnail_path.exists():
        thumbnail_path.unlink(missing_ok=True)

    preview_pdf_path = sample_output_dir / "preview.pdf"
    preview = generate_pdf_preview_from_thumbnail(thumbnail_path, preview_pdf_path)
    if not preview.generated and preview_pdf_path.exists():
        preview_pdf_path.unlink(missing_ok=True)

    render_snapshot_path = sample_output_dir / "render_snapshot.png"
    render_snapshot = create_vector_snapshot_proxy(diagnostics, thumbnail_path, render_snapshot_path)
    if not render_snapshot.generated and render_snapshot_path.exists():
        render_snapshot_path.unlink(missing_ok=True)

    parse_ms = as_int(as_dict(diagnostics.get("summary")).get("parseMilliseconds"))
    first_conversion_ms = parse_ms if parse_ms > 0 else as_int(parse_result.get("probeWallMilliseconds"))
    render_ms = max(render_snapshot.milliseconds, 0)
    first_frame_ms = max(first_conversion_ms + render_ms, first_conversion_ms)
    vector_ready = can_enter_vector_viewer(diagnostics)
    launch_readiness = evaluate_launch_readiness(diagnostics, first_conversion_ms, render_ms)

    performance_trace_path = sample_output_dir / "performance_trace.json"
    write_json(performance_trace_path, build_performance_trace(diagnostics, first_frame_ms, render_ms))

    unsupported_entities_path = sample_output_dir / "unsupported_entities.json"
    write_json(unsupported_entities_path, build_unsupported_entities_report(diagnostics))

    summary_path = sample_output_dir / "summary.md"
    write_summary_markdown(
        summary_path,
        sample_path,
        diagnostics,
        launch_readiness,
        first_conversion_ms,
        render_ms,
        vector_ready,
        thumbnail,
        preview,
        render_snapshot,
    )

    item_manifest = {
        "schema": "CADRegressionItemManifest/v1",
        "generatedAt": utc_now_iso(),
        "source": {
            "relativePath": str(relative_path),
            "absolutePath": str(sample_path),
            "fileName": sample_path.name,
            "extension": sample_path.suffix.lower(),
            "fileSize": sample_path.stat().st_size,
        },
        "timings": {
            "firstConversionMilliseconds": first_conversion_ms,
            "firstFrameMilliseconds": first_frame_ms,
            "renderMilliseconds": render_ms,
            "probeWallMilliseconds": as_int(parse_result.get("probeWallMilliseconds")),
        },
        "quality": {
            "viewerMode": str(diagnostics.get("viewerMode") or ""),
            "qualityScore": as_int(diagnostics.get("qualityScore")),
            "hasMojibake": has_mojibake(diagnostics),
            "hasMissingFonts": has_missing_fonts(diagnostics),
            "hasMissingXrefs": has_missing_xrefs(diagnostics),
            "unsupportedEntityRatio": unsupported_ratio(diagnostics),
            "canEnterVectorViewer": vector_ready,
            "suggestedHandling": suggest_handling(diagnostics),
        },
        "launchReadiness": launch_readiness,
        "outputs": {
            "diagnostics": "diagnostics.json",
            "manifest": "manifest.json",
            "performanceTrace": "performance_trace.json",
            "textTrace": "text_trace.jsonl",
            "fontDiagnostics": "font_diagnostics.json",
            "unsupportedEntities": "unsupported_entities.json",
            "summary": "summary.md",
            "thumbnail": {
                "generated": thumbnail.generated,
                "path": "thumbnail.png" if thumbnail.generated else None,
                "reason": thumbnail.reason,
                "method": thumbnail.method,
                "milliseconds": thumbnail.milliseconds,
            },
            "preview": {
                "generated": preview.generated,
                "path": "preview.pdf" if preview.generated else None,
                "format": "pdf" if preview.generated else None,
                "reason": preview.reason,
                "method": preview.method,
                "milliseconds": preview.milliseconds,
            },
            "renderSnapshot": {
                "generated": render_snapshot.generated,
                "path": "render_snapshot.png" if render_snapshot.generated else None,
                "reason": render_snapshot.reason,
                "method": render_snapshot.method,
                "milliseconds": render_snapshot.milliseconds,
            },
        },
    }

    item_manifest_path = sample_output_dir / "manifest.json"
    write_json(item_manifest_path, item_manifest)

    return {
        "sourcePath": sample_path,
        "relativePath": str(relative_path),
        "outputDir": sample_output_dir,
        "manifestPath": item_manifest_path,
        "diagnosticsPath": diagnostics_path,
        "summaryPath": summary_path,
        "performanceTracePath": performance_trace_path,
        "fontDiagnosticsPath": font_diagnostics_path,
        "unsupportedEntitiesPath": unsupported_entities_path,
        "itemManifest": item_manifest,
        "diagnostics": diagnostics,
        "firstConversionMilliseconds": first_conversion_ms,
        "firstFrameMilliseconds": first_frame_ms,
        "renderMilliseconds": render_ms,
        "vectorReady": vector_ready,
    }


def process_failed_sample(
    sample_root: Path,
    sample_path: Path,
    output_root: Path,
    error_message: str,
) -> dict[str, Any]:
    relative_path = sample_path.relative_to(sample_root)
    sample_output_dir = output_root / "files" / relative_path
    sample_output_dir.mkdir(parents=True, exist_ok=True)

    diagnostics = {
        "schema": "CADDrawingDiagnostics/v1",
        "generatedAt": utc_now_iso(),
        "fileName": sample_path.name,
        "fileSize": sample_path.stat().st_size if sample_path.exists() else 0,
        "dwgVersion": "",
        "dwgCodePage": "",
        "layoutCount": 0,
        "layerCount": 0,
        "blockCount": 0,
        "entityCountByType": {},
        "unsupportedEntityCountByType": {},
        "textEntityCount": 0,
        "mtextEntityCount": 0,
        "attribEntityCount": 0,
        "dimensionEntityCount": 0,
        "textStyleCount": 0,
        "textStyles": [],
        "missingFonts": [],
        "missingBigFonts": [],
        "suspiciousMojibakeSamples": [],
        "unicodeEscapeSamples": [],
        "autocadControlCodeSamples": [],
        "unresolvedTextSamples": [],
        "xrefCount": 0,
        "missingXrefs": [],
        "warnings": [f"regression-processing-failed: {error_message}"],
        "qualityScore": 0,
        "viewerMode": "fallback",
        "summary": {
            "entityTotal": 0,
            "drawablePrimitiveTotal": 0,
            "unsupportedRatio": 1.0,
            "mojibakeSampleRatio": 0.0,
            "parseMilliseconds": 0,
            "estimatedPrimitiveMemory": 0,
        },
        "textTraceSummary": {
            "totalTextCount": 0,
            "normalChineseCount": 0,
            "mojibakeLikeCount": 0,
            "replacementCharacterCount": 0,
            "questionMarkOnlyCount": 0,
            "unicodeEscapeCount": 0,
            "shxFallbackUsedCount": 0,
            "ordinaryChineseIncorrectlySentToSHXCount": 0,
        },
        "textSamples": [],
        "textTrace": [],
        "xrefs": [],
        "probe": {
            "ok": False,
            "errorMessage": error_message,
        },
    }

    diagnostics_path = sample_output_dir / "diagnostics.json"
    write_json(diagnostics_path, diagnostics)
    text_trace_path = sample_output_dir / "text_trace.jsonl"
    write_text_trace_jsonl([], text_trace_path)
    font_diagnostics_path = sample_output_dir / "font_diagnostics.json"
    write_json(font_diagnostics_path, build_font_diagnostics_report(diagnostics))

    performance_trace_path = sample_output_dir / "performance_trace.json"
    write_json(performance_trace_path, build_performance_trace(diagnostics, 0, 0))

    unsupported_entities_path = sample_output_dir / "unsupported_entities.json"
    write_json(unsupported_entities_path, build_unsupported_entities_report(diagnostics))

    thumbnail = ArtifactResult(False, None, "sample processing failed", None, 0)
    preview = ArtifactResult(False, None, "sample processing failed", None, 0)
    render_snapshot = ArtifactResult(False, None, "sample processing failed", None, 0)
    launch_readiness = evaluate_launch_readiness(diagnostics, 0, 0)
    summary_path = sample_output_dir / "summary.md"
    write_summary_markdown(
        summary_path,
        sample_path,
        diagnostics,
        launch_readiness,
        0,
        0,
        False,
        thumbnail,
        preview,
        render_snapshot,
    )

    item_manifest = {
        "schema": "CADRegressionItemManifest/v1",
        "generatedAt": utc_now_iso(),
        "source": {
            "relativePath": str(relative_path),
            "absolutePath": str(sample_path),
            "fileName": sample_path.name,
            "extension": sample_path.suffix.lower(),
            "fileSize": sample_path.stat().st_size if sample_path.exists() else 0,
        },
        "timings": {
            "firstConversionMilliseconds": 0,
            "firstFrameMilliseconds": 0,
            "renderMilliseconds": 0,
            "probeWallMilliseconds": 0,
        },
        "quality": {
            "viewerMode": "fallback",
            "qualityScore": 0,
            "hasMojibake": False,
            "hasMissingFonts": False,
            "hasMissingXrefs": False,
            "unsupportedEntityRatio": 1.0,
            "canEnterVectorViewer": False,
            "suggestedHandling": "处理失败：异常保护不能算修复，先查看 diagnostics.json 的错误信息",
        },
        "launchReadiness": launch_readiness,
        "outputs": {
            "diagnostics": "diagnostics.json",
            "manifest": "manifest.json",
            "performanceTrace": "performance_trace.json",
            "textTrace": "text_trace.jsonl",
            "fontDiagnostics": "font_diagnostics.json",
            "unsupportedEntities": "unsupported_entities.json",
            "summary": "summary.md",
            "thumbnail": {"generated": False, "path": None, "reason": "sample processing failed"},
            "preview": {"generated": False, "path": None, "reason": "sample processing failed"},
            "renderSnapshot": {"generated": False, "path": None, "reason": "sample processing failed"},
        },
        "error": error_message,
    }
    item_manifest_path = sample_output_dir / "manifest.json"
    write_json(item_manifest_path, item_manifest)

    return {
        "sourcePath": sample_path,
        "relativePath": str(relative_path),
        "outputDir": sample_output_dir,
        "manifestPath": item_manifest_path,
        "diagnosticsPath": diagnostics_path,
        "summaryPath": summary_path,
        "performanceTracePath": performance_trace_path,
        "fontDiagnosticsPath": font_diagnostics_path,
        "unsupportedEntitiesPath": unsupported_entities_path,
        "itemManifest": item_manifest,
        "diagnostics": diagnostics,
        "firstConversionMilliseconds": 0,
        "firstFrameMilliseconds": 0,
        "renderMilliseconds": 0,
        "vectorReady": False,
    }


def launch_readiness_for_item(item: dict[str, Any]) -> dict[str, Any]:
    manifest = as_dict(item.get("itemManifest"))
    readiness = as_dict(manifest.get("launchReadiness"))
    if readiness:
        return readiness
    return evaluate_launch_readiness(
        as_dict(item.get("diagnostics")),
        as_int(item.get("firstConversionMilliseconds")),
        as_int(item.get("renderMilliseconds")),
    )


def build_launch_gate(run_items: list[dict[str, Any]]) -> dict[str, Any]:
    total_count = len(run_items)
    readiness_items = [launch_readiness_for_item(item) for item in run_items]
    normal_open_count = sum(1 for readiness in readiness_items if bool(readiness.get("normalOpen")))
    exception_count = sum(1 for readiness in readiness_items if bool(readiness.get("exceptionProtection")))
    content_risk_count = sum(1 for readiness in readiness_items if bool(readiness.get("majorContentRisk")))
    tianzheng_risk_count = sum(1 for readiness in readiness_items if bool(readiness.get("tianzhengRisk")))
    tianzheng_needs_strategy_count = sum(
        1
        for readiness in readiness_items
        if bool(readiness.get("tianzhengRisk")) and "需明确" in str(readiness.get("tianzhengHandling") or "")
    )

    text_issue_total = 0
    text_total = 0
    missing_font_count = 0
    missing_xref_count = 0
    xref_total = 0
    small_file_count = 0
    second_open_unmeasured_count = 0
    pan_zoom_unmeasured_count = 0
    max_sample_mojibake_ratio = 0.0

    for item, readiness in zip(run_items, readiness_items):
        diagnostics = as_dict(item.get("diagnostics"))
        issue_count, total = text_issue_counts(diagnostics)
        text_issue_total += issue_count
        text_total += total
        max_sample_mojibake_ratio = max(max_sample_mojibake_ratio, as_float(readiness.get("mojibakeRatio")))
        if has_missing_fonts(diagnostics):
            missing_font_count += 1
        if has_missing_xrefs(diagnostics):
            missing_xref_count += 1
        xref_total += as_int(diagnostics.get("xrefCount"))
        file_size = as_int(diagnostics.get("fileSize"))
        if 0 < file_size <= SMALL_DWG_LIMIT_BYTES:
            small_file_count += 1
            if not bool(readiness.get("secondOpenMeasured")):
                second_open_unmeasured_count += 1
        if not bool(readiness.get("panZoomMeasured")):
            pan_zoom_unmeasured_count += 1

    corpus_mojibake_ratio = safe_div(text_issue_total, text_total)
    if text_total <= 0:
        corpus_mojibake_ratio = max_sample_mojibake_ratio

    normal_open_pass: bool | None = None
    if total_count >= LAUNCH_SAMPLE_TARGET_COUNT:
        normal_open_pass = normal_open_count >= LAUNCH_NORMAL_OPEN_TARGET_COUNT
    mojibake_pass: bool | None = None
    if text_total > 0 or max_sample_mojibake_ratio > 0:
        mojibake_pass = corpus_mojibake_ratio < MOJIBAKE_RATIO_LIMIT
    content_pass: bool | None = content_risk_count == 0 if total_count > 0 else None
    tianzheng_pass: bool | None
    if tianzheng_risk_count == 0:
        tianzheng_pass = None
    else:
        tianzheng_pass = tianzheng_needs_strategy_count == 0
    xref_pass: bool | None
    if xref_total == 0:
        xref_pass = None
    else:
        xref_pass = missing_xref_count == 0
    second_open_pass: bool | None
    if small_file_count == 0:
        second_open_pass = None
    else:
        second_open_pass = second_open_unmeasured_count == 0
    if total_count == 0:
        pan_zoom_pass = None
    elif pan_zoom_unmeasured_count > 0:
        pan_zoom_pass = None
    else:
        pan_zoom_pass = True
    user_hidden_text_pass: bool | None
    if text_total == 0 and missing_font_count == 0:
        user_hidden_text_pass = None
    else:
        user_hidden_text_pass = missing_font_count == 0 and corpus_mojibake_ratio < MOJIBAKE_RATIO_LIMIT

    gate_values = [
        normal_open_pass,
        mojibake_pass,
        content_pass,
        tianzheng_pass,
        xref_pass,
        second_open_pass,
        pan_zoom_pass,
        user_hidden_text_pass,
    ]
    launch_ready = total_count >= LAUNCH_SAMPLE_TARGET_COUNT and all(value is True for value in gate_values)

    return {
        "sampleCount": total_count,
        "normalOpenCount": normal_open_count,
        "exceptionProtectionCount": exception_count,
        "textIssueTotal": text_issue_total,
        "textTotal": text_total,
        "corpusMojibakeRatio": corpus_mojibake_ratio,
        "missingFontCount": missing_font_count,
        "contentRiskCount": content_risk_count,
        "xrefTotal": xref_total,
        "missingXrefCount": missing_xref_count,
        "tianzhengRiskCount": tianzheng_risk_count,
        "tianzhengNeedsStrategyCount": tianzheng_needs_strategy_count,
        "smallFileCount": small_file_count,
        "secondOpenUnmeasuredCount": second_open_unmeasured_count,
        "panZoomUnmeasuredCount": pan_zoom_unmeasured_count,
        "normalOpenPass": normal_open_pass,
        "mojibakePass": mojibake_pass,
        "contentPass": content_pass,
        "tianzhengPass": tianzheng_pass,
        "xrefPass": xref_pass,
        "secondOpenPass": second_open_pass,
        "panZoomPass": pan_zoom_pass,
        "userHiddenTextPass": user_hidden_text_pass,
        "launchReady": launch_ready,
    }


def build_report_markdown(run_items: list[dict[str, Any]]) -> str:
    launch_gate = build_launch_gate(run_items)
    header = [
        "# CAD Regression Report",
        "",
        "## 上线门槛",
        "",
        "说明：fallback / 兼容预览只记录为异常保护，不计入正常打开，也不作为上线通过结论。",
        "",
        "| 标准 | 当前结果 | 判定 |",
        "| --- | --- | --- |",
        (
            f"| 30 张真实中文施工图中至少 27 张正常打开 | "
            f"样本 {launch_gate['sampleCount']} 张，正常打开 {launch_gate['normalOpenCount']} 张，"
            f"异常保护 {launch_gate['exceptionProtectionCount']} 张 | "
            f"{status_label(launch_gate['normalOpenPass'])} |"
        ),
        (
            f"| 中文乱码比例低于 1% | "
            f"{launch_gate['textIssueTotal']}/{launch_gate['textTotal']}，"
            f"{as_float(launch_gate['corpusMojibakeRatio']):.2%} | "
            f"{status_label(launch_gate['mojibakePass'])} |"
        ),
        (
            f"| 图纸主要内容不得缺失 | "
            f"主要内容风险样本 {launch_gate['contentRiskCount']} 张 | "
            f"{status_label(launch_gate['contentPass'])} |"
        ),
        (
            f"| 天正图纸必须有可用方案 | "
            f"疑似天正/Proxy {launch_gate['tianzhengRiskCount']} 张，"
            f"仍需方案 {launch_gate['tianzhengNeedsStrategyCount']} 张 | "
            f"{status_label(launch_gate['tianzhengPass'])} |"
        ),
        (
            f"| 外部参照必须能管理 | "
            f"XREF {launch_gate['xrefTotal']} 个，缺失样本 {launch_gate['missingXrefCount']} 张 | "
            f"{status_label(launch_gate['xrefPass'])} |"
        ),
        (
            f"| 100MB 以下图纸二次打开约 3 秒 | "
            f"100MB 以下样本 {launch_gate['smallFileCount']} 张，未测量 {launch_gate['secondOpenUnmeasuredCount']} 张 | "
            f"{status_label(launch_gate['secondOpenPass'])} |"
        ),
        (
            f"| 平移缩放不能明显卡顿 | "
            f"未接入真实手势帧率样本 {launch_gate['panZoomUnmeasuredCount']} 张 | "
            f"{status_label(launch_gate['panZoomPass'])} |"
        ),
        (
            f"| 用户不需要理解字体、SHX、编码问题 | "
            f"缺字体样本 {launch_gate['missingFontCount']} 张，乱码比例 "
            f"{as_float(launch_gate['corpusMojibakeRatio']):.2%} | "
            f"{status_label(launch_gate['userHiddenTextPass'])} |"
        ),
        "",
        f"当前上线状态：`{'READY' if launch_gate['launchReady'] else 'NOT READY'}`",
        "",
        "## Files",
        "",
        "| 文件名 | 是否打开成功 | 是否白屏 | 中文是否可读 | 缺失字体 | 缺失 BigFont | 缺失 XREF | unsupported entity ratio | firstFrameMs | renderMs | qualityScore | 是否达到上线标准 | 建议处理方式 |",
        "| --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |",
    ]

    rows: list[str] = []
    for item in run_items:
        diagnostics = as_dict(item.get("diagnostics"))
        readiness = launch_readiness_for_item(item)
        source_path = Path(str(item.get("sourcePath")))
        first_frame_ms = as_int(item.get("firstFrameMilliseconds"))
        if first_frame_ms <= 0:
            first_frame_ms = as_int(item.get("firstConversionMilliseconds")) + as_int(item.get("renderMilliseconds"))
        row = [
            markdown_escape(source_path.name),
            bool_to_yes_no(parse_ok(diagnostics)),
            bool_to_yes_no(is_blank_drawing(diagnostics)),
            chinese_readability_status(diagnostics),
            bool_to_yes_no(has_missing_normal_fonts(diagnostics)),
            bool_to_yes_no(has_missing_big_fonts(diagnostics)),
            bool_to_yes_no(has_missing_xrefs(diagnostics)),
            f"{unsupported_ratio(diagnostics):.2%}",
            f"{first_frame_ms} ms",
            f"{as_int(item.get('renderMilliseconds'))} ms",
            str(as_int(diagnostics.get("qualityScore"))),
            bool_to_yes_no(bool(readiness.get("launchReady"))),
            markdown_escape(suggest_handling(diagnostics)),
        ]
        rows.append("| " + " | ".join(row) + " |")

    total_count = len(run_items)
    vector_count = sum(1 for item in run_items if bool(item.get("vectorReady")))
    mojibake_count = sum(1 for item in run_items if has_mojibake(as_dict(item.get("diagnostics"))))
    missing_font_count = sum(1 for item in run_items if has_missing_fonts(as_dict(item.get("diagnostics"))))
    missing_xref_count = sum(1 for item in run_items if has_missing_xrefs(as_dict(item.get("diagnostics"))))
    avg_quality = safe_div(
        sum(as_int(as_dict(item.get("diagnostics")).get("qualityScore")) for item in run_items),
        total_count,
    )
    footer = [
        "",
        "## Summary",
        "",
        f"- 样本总数: {total_count}",
        f"- 可进入 vector viewer: {vector_count}",
        f"- 乱码疑似: {mojibake_count}",
        f"- 缺字体: {missing_font_count}",
        f"- 缺外部参照: {missing_xref_count}",
        f"- 平均 qualityScore: {avg_quality:.1f}",
    ]
    return "\n".join(header + rows + footer) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="cad-regression",
        description="Batch CAD sample diagnostics/regression for local DWG/DXF corpus.",
    )
    parser.add_argument("samples_dir", type=Path, help="Sample directory (e.g. samples/cad).")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/cad-regression"),
        help="Output directory for per-file artifacts and aggregate report.",
    )
    parser.add_argument(
        "--parser",
        type=Path,
        help="Existing dwg_probe executable. If omitted, probe is built automatically.",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=DEFAULT_PROBE_BUILD_DIR,
        help="Directory for generated dwg_probe executable.",
    )
    parser.add_argument(
        "--parser-timeout",
        type=int,
        default=180,
        help="Timeout in seconds for each sample parse.",
    )
    parser.add_argument(
        "--font-dir",
        type=Path,
        action="append",
        default=[],
        help="Additional local font/SHX directory to check for missing fonts.",
    )
    parser.add_argument(
        "--thumbnail-size",
        type=int,
        default=1536,
        help="Target pixel size for generated thumbnail via QuickLook.",
    )
    args = parser.parse_args()

    repo_root = repo_root_from_script()
    sample_root = args.samples_dir if args.samples_dir.is_absolute() else (Path.cwd() / args.samples_dir)
    sample_root = sample_root.resolve()
    output_root = args.output if args.output.is_absolute() else (Path.cwd() / args.output)
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    if not sample_root.exists() or not sample_root.is_dir():
        print(f"ERROR sample directory not found: {sample_root}")
        return 2

    sample_files = discover_samples(sample_root)
    font_dirs = [path.resolve() for path in args.font_dir]
    run_items: list[dict[str, Any]] = []

    print(f"cad-regression: sampleRoot={sample_root}")
    print(f"cad-regression: output={output_root}")
    print(f"cad-regression: files={len(sample_files)}")

    probe: Path | None
    if requires_probe(sample_files):
        if args.parser:
            probe = args.parser if args.parser.is_absolute() else (repo_root / args.parser)
        else:
            build_dir = args.build_dir if args.build_dir.is_absolute() else (repo_root / args.build_dir)
            probe = build_probe(repo_root, build_dir)
        print(f"cad-regression: probe={probe}")
    elif sample_files:
        probe = None
        print("cad-regression: no DWG files found; using fixture importers only")
    else:
        probe = None
        print("cad-regression: no DWG/DXF/JSON files found, generating empty report only")

    for index, sample_path in enumerate(sample_files, start=1):
        print(f"[{index}/{len(sample_files)}] {sample_path.name}")
        try:
            item = process_one_sample(
                sample_root=sample_root,
                sample_path=sample_path,
                output_root=output_root,
                probe=probe,
                parser_timeout=max(args.parser_timeout, 1),
                font_dirs=font_dirs,
                thumbnail_size=max(args.thumbnail_size, 256),
            )
        except Exception as exc:  # noqa: BLE001 - keep regression run alive for other files.
            print(f"WARN sample failed: {sample_path.name} -> {exc}")
            item = process_failed_sample(
                sample_root=sample_root,
                sample_path=sample_path,
                output_root=output_root,
                error_message=str(exc),
            )
        run_items.append(item)

    report_markdown = build_report_markdown(run_items)
    report_path = output_root / "cad_regression_report.md"
    report_path.write_text(report_markdown, encoding="utf-8")
    legacy_report_path = output_root / "cad-regression-report.md"
    legacy_report_path.write_text(report_markdown, encoding="utf-8")

    run_manifest = {
        "schema": "CADRegressionRun/v1",
        "generatedAt": utc_now_iso(),
        "sampleRoot": str(sample_root),
        "outputRoot": str(output_root),
        "probe": str(probe) if probe is not None else None,
        "sampleCount": len(sample_files),
        "processedCount": len(run_items),
        "report": str(report_path),
        "legacyReport": str(legacy_report_path),
        "files": [
            {
                "relativePath": item["relativePath"],
                "outputDir": relative_artifact_path(output_root, Path(item["outputDir"])),
                "manifest": relative_artifact_path(output_root, Path(item["manifestPath"])),
                "diagnostics": relative_artifact_path(output_root, Path(item["diagnosticsPath"])),
                "performanceTrace": relative_artifact_path(output_root, Path(item["performanceTracePath"])),
                "fontDiagnostics": relative_artifact_path(output_root, Path(item["fontDiagnosticsPath"])),
                "unsupportedEntities": relative_artifact_path(output_root, Path(item["unsupportedEntitiesPath"])),
                "summary": relative_artifact_path(output_root, Path(item["summaryPath"])),
                "viewerMode": str(as_dict(item["diagnostics"]).get("viewerMode") or ""),
                "qualityScore": as_int(as_dict(item["diagnostics"]).get("qualityScore")),
            }
            for item in run_items
        ],
    }
    write_json(output_root / "manifest.json", run_manifest)

    print(f"cad-regression report: {report_path}")
    print(f"cad-regression manifest: {output_root / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
