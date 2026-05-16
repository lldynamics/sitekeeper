#!/usr/bin/env python3
"""Create a quantifiable CAD drawing diagnostics JSON for a DWG file."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dwg_regression import (
    DEFAULT_PROBE_BUILD_DIR,
    attach_text_diagnostics,
    attach_xref_resolution,
    build_probe,
    repo_root_from_script,
    run_probe,
)


FONT_SEARCH_DIR_NAMES = (
    "",
    "fonts",
    "Fonts",
    "font",
    "Font",
    "shx",
    "SHX",
    "字体",
    "CAD字体",
)

MOJIBAKE_CHARS = {"Ê", "©", "¹", "¤", "Í", "¼", "½", "¨", "Ö", "þ"}
UNICODE_ESCAPE_RE = re.compile(r"\\U\+[0-9A-Fa-f]{4}")


def as_int(value: Any, default: int = 0) -> int:
    return value if isinstance(value, int) else default


def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def text_value(sample: dict[str, Any]) -> str:
    for key in ("displayText", "decodedText", "text", "rawText"):
        value = sample.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def contains_cjk(text: str) -> bool:
    for character in text:
        code = ord(character)
        if 0x3400 <= code <= 0x4DBF or 0x4E00 <= code <= 0x9FFF or 0xF900 <= code <= 0xFAFF:
            return True
    return False


def contains_replacement_character(text: str) -> bool:
    return "\ufffd" in text


def contains_question_mark(text: str) -> bool:
    return "?" in text


def is_question_mark_only(text: str) -> bool:
    trimmed = text.strip()
    return bool(trimmed) and all(character == "?" for character in trimmed)


def contains_unicode_escape(text: str) -> bool:
    return UNICODE_ESCAPE_RE.search(text) is not None


def contains_autocad_control_code(text: str) -> bool:
    lowered = text.lower()
    return "%%d" in lowered or "%%p" in lowered or "%%c" in lowered


def contains_mojibake_char(text: str) -> bool:
    return any(character in MOJIBAKE_CHARS for character in text)


def compact_samples(samples: list[dict[str, Any]], limit: int = 20) -> list[str]:
    seen: set[str] = set()
    values: list[str] = []
    for sample in samples:
        value = text_value(sample)
        if not value:
            value = str(sample.get("rawTextBytesHex", "")).strip()
        if not value or value in seen:
            continue
        seen.add(value)
        values.append(value[:160])
        if len(values) >= limit:
            break
    return values


def warning_text(value: Any) -> str:
    if isinstance(value, list):
        return ",".join(str(item) for item in value)
    return str(value or "")


def count_dimension_entities(entity_counts: dict[str, Any]) -> int:
    total = 0
    for key, value in entity_counts.items():
        if isinstance(value, int) and key.startswith("DIMENSION"):
            total += value
    return total


def normalize_font_name(value: str) -> str:
    cleaned = value.strip().strip('"').replace("\\", "/")
    if "/" in cleaned:
        cleaned = cleaned.rsplit("/", 1)[-1]
    return cleaned


def font_exists(dwg_path: Path, font_name: str, extra_dirs: list[Path]) -> bool:
    leaf = normalize_font_name(font_name)
    if not leaf:
        return True
    candidates: list[Path] = []
    source_dir = dwg_path.parent
    for directory_name in FONT_SEARCH_DIR_NAMES:
        base = source_dir / directory_name if directory_name else source_dir
        candidates.append(base / leaf)
    for directory in extra_dirs:
        candidates.append(directory / leaf)

    lower_leaf = leaf.lower()
    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            return True
        parent = candidate.parent
        if parent.exists() and parent.is_dir():
            try:
                if any(child.name.lower() == lower_leaf for child in parent.iterdir()):
                    return True
            except OSError:
                continue
    return False


def collect_font_gaps(
    dwg_path: Path,
    text_styles: list[dict[str, Any]],
    text_samples: list[dict[str, Any]],
    extra_font_dirs: list[Path],
) -> tuple[list[str], list[str]]:
    fonts: set[str] = set()
    big_fonts: set[str] = set()
    missing_fonts: set[str] = set()
    missing_big_fonts: set[str] = set()

    for style in text_styles:
        font = normalize_font_name(str(style.get("fontFile", "")))
        big_font = normalize_font_name(str(style.get("bigFontFile", "")))
        if font:
            fonts.add(font)
        if big_font:
            big_fonts.add(big_font)

    for sample in text_samples:
        font = normalize_font_name(str(sample.get("fontFile", "")))
        big_font = normalize_font_name(str(sample.get("bigFontFile", "")))
        if font:
            fonts.add(font)
        if big_font:
            big_fonts.add(big_font)
        warnings = warning_text(sample.get("normalizeWarnings"))
        if "shx-without-bigfont" in warnings:
            style_name = str(sample.get("textStyleName", "")).strip() or "未命名样式"
            missing_big_fonts.add(f"{style_name}（未声明 BigFont）")

    for font in fonts:
        if not font_exists(dwg_path, font, extra_font_dirs):
            missing_fonts.add(font)
    for big_font in big_fonts:
        if not font_exists(dwg_path, big_font, extra_font_dirs):
            missing_big_fonts.add(big_font)
    return sorted(missing_fonts), sorted(missing_big_fonts)


def text_trace_entries(parse_result: dict[str, Any]) -> list[dict[str, Any]]:
    raw_trace = parse_result.get("textTrace")
    if isinstance(raw_trace, list):
        entries = [item for item in raw_trace if isinstance(item, dict)]
        if entries:
            return entries

    entries: list[dict[str, Any]] = []
    for sample in as_list(parse_result.get("textSamples")):
        if not isinstance(sample, dict):
            continue
        trace = sample.get("trace")
        if isinstance(trace, dict):
            entries.append(trace)
            continue
        entries.append({
            "entityId": str(sample.get("kind", "text")).lower(),
            "entityType": str(sample.get("kind", "text")),
            "rawBytesHex": sample.get("rawTextBytesHex"),
            "rawTextFromLibreDWG": sample.get("rawText"),
            "jsonText": sample.get("text"),
            "decodedText": sample.get("decodedText"),
            "normalizedText": sample.get("displayText") or sample.get("text") or "",
            "finalDisplayText": sample.get("displayText") or sample.get("text") or "",
            "textStyleName": sample.get("textStyleName"),
            "fontFile": sample.get("fontFile"),
            "bigFontFile": sample.get("bigFontFile"),
            "selectedUIFontName": "",
            "usedSHXGlyphFallback": False,
            "warnings": sample.get("normalizeWarnings") if isinstance(sample.get("normalizeWarnings"), list) else [],
        })
    return entries


def trace_warning_tags(trace: dict[str, Any]) -> list[str]:
    texts = [
        str(trace.get("rawTextFromLibreDWG") or ""),
        str(trace.get("jsonText") or ""),
        str(trace.get("decodedText") or ""),
        str(trace.get("normalizedText") or ""),
        str(trace.get("finalDisplayText") or ""),
    ]
    tags: set[str] = set()
    if any(contains_cjk(text) for text in texts):
        tags.add("contains-cjk")
    if any(contains_replacement_character(text) for text in texts):
        tags.add("contains-replacement-char")
    if any(contains_question_mark(text) for text in texts):
        tags.add("contains-question-mark")
    if any(contains_unicode_escape(text) for text in texts):
        tags.add("contains-unicode-escape")
    if any(contains_autocad_control_code(text) for text in texts):
        tags.add("contains-autocad-control-code")
    if any(contains_mojibake_char(text) for text in texts):
        tags.add("contains-mojibake-token")

    used_shx_fallback = bool(trace.get("usedSHXGlyphFallback"))
    final_display = str(trace.get("finalDisplayText") or "")
    if used_shx_fallback:
        tags.add("used-shx-fallback")
    if is_question_mark_only(final_display):
        tags.add("question-mark-only")
    if used_shx_fallback and contains_cjk(final_display):
        raw_text = str(trace.get("rawTextFromLibreDWG") or "")
        if (
            not contains_unicode_escape(final_display)
            and not contains_autocad_control_code(final_display)
            and not contains_unicode_escape(raw_text)
            and not contains_autocad_control_code(raw_text)
            and not contains_replacement_character(final_display)
            and not contains_mojibake_char(final_display)
        ):
            tags.add("ordinary-chinese-sent-to-shx")
    return sorted(tags)


def text_trace_summary(entries: list[dict[str, Any]]) -> dict[str, int]:
    total = len(entries)
    normal_chinese = 0
    mojibake_like = 0
    replacement = 0
    question_only = 0
    unicode_escape = 0
    shx_fallback = 0
    ordinary_chinese_to_shx = 0

    for trace in entries:
        warnings = set(trace_warning_tags(trace))
        final_display = str(trace.get("finalDisplayText") or "")
        has_chinese = contains_cjk(final_display)
        if has_chinese and "contains-replacement-char" not in warnings and "question-mark-only" not in warnings and "contains-mojibake-token" not in warnings:
            normal_chinese += 1
        if "contains-mojibake-token" in warnings:
            mojibake_like += 1
        if "contains-replacement-char" in warnings:
            replacement += 1
        if "question-mark-only" in warnings:
            question_only += 1
        if "contains-unicode-escape" in warnings:
            unicode_escape += 1
        if "used-shx-fallback" in warnings:
            shx_fallback += 1
        if "ordinary-chinese-sent-to-shx" in warnings:
            ordinary_chinese_to_shx += 1

    return {
        "totalTextCount": total,
        "normalChineseCount": normal_chinese,
        "mojibakeLikeCount": mojibake_like,
        "replacementCharacterCount": replacement,
        "questionMarkOnlyCount": question_only,
        "unicodeEscapeCount": unicode_escape,
        "shxFallbackUsedCount": shx_fallback,
        "ordinaryChineseIncorrectlySentToSHXCount": ordinary_chinese_to_shx,
    }


def text_issue_samples(parse_result: dict[str, Any], issue_names: set[str]) -> list[dict[str, Any]]:
    diagnostics = as_dict(parse_result.get("textDiagnostics"))
    samples = as_list(diagnostics.get("issueSamples"))
    matched: list[dict[str, Any]] = []
    for item in samples:
        if not isinstance(item, dict):
            continue
        issues = {issue for issue in as_list(item.get("issues")) if isinstance(issue, str)}
        warnings = warning_text(item.get("normalizeWarnings"))
        if issues.intersection(issue_names) or any(issue in warnings for issue in issue_names):
            matched.append(item)
    return matched


def build_warnings(
    parse_result: dict[str, Any],
    unsupported_ratio: float,
    mojibake_ratio: float,
    missing_fonts: list[str],
    missing_big_fonts: list[str],
    missing_xrefs: list[str],
    unicode_samples: list[str],
    control_samples: list[str],
) -> list[str]:
    warnings: list[str] = []
    if not parse_result.get("ok"):
        warnings.append(f"DWG 解码失败：{parse_result.get('errorMessage') or '未知错误'}")
    if unsupported_ratio > 0:
        warnings.append(f"存在未支持图元，比例约 {unsupported_ratio:.1%}")
    if mojibake_ratio > 0:
        warnings.append(f"存在疑似乱码文字，采样比例约 {mojibake_ratio:.1%}")
    if missing_fonts:
        warnings.append(f"缺失字体：{', '.join(missing_fonts[:8])}")
    if missing_big_fonts:
        warnings.append(f"缺失 BigFont：{', '.join(missing_big_fonts[:8])}")
    if missing_xrefs:
        warnings.append(f"缺失外部参照：{', '.join(missing_xrefs[:8])}")
    if unicode_samples:
        warnings.append("存在未展开 Unicode 转义或 \\U+/\\M+ 控制片段")
    if control_samples:
        warnings.append("存在 MTEXT/AutoCAD 控制码残留")
    if as_int(parse_result.get("parseMilliseconds")) >= 15_000:
        warnings.append(f"解析耗时较长：{parse_result.get('parseMilliseconds')} ms")
    if as_int(parse_result.get("estimatedPrimitiveMemory")) >= 96 * 1024 * 1024:
        warnings.append("Canvas 几何内存估计偏高，可能需要 tile/分块渲染")
    return warnings


def quality_score(
    parse_result: dict[str, Any],
    unsupported_ratio: float,
    mojibake_ratio: float,
    missing_fonts: list[str],
    missing_big_fonts: list[str],
    missing_xrefs: list[str],
    control_sample_count: int,
) -> int:
    score = 100
    if not parse_result.get("ok"):
        score -= 45
    if as_int(parse_result.get("primitiveCount")) <= 0:
        score -= 30
    score -= min(35, round(unsupported_ratio * 100))
    score -= min(30, round(mojibake_ratio * 60))
    if missing_fonts:
        score -= min(12, 4 + len(missing_fonts))
    if missing_big_fonts:
        score -= min(16, 6 + len(missing_big_fonts))
    if missing_xrefs:
        score -= min(20, 8 + len(missing_xrefs) * 3)
    if control_sample_count:
        score -= min(10, 4 + control_sample_count)
    if as_int(parse_result.get("parseMilliseconds")) >= 15_000:
        score -= 10
    if as_int(parse_result.get("estimatedPrimitiveMemory")) >= 96 * 1024 * 1024:
        score -= 10
    return max(0, min(100, score))


def suggested_viewer_mode(parse_result: dict[str, Any], score: int) -> str:
    if not parse_result.get("ok") or as_int(parse_result.get("primitiveCount")) <= 0 or score < 45:
        return "fallback"
    if (
        as_int(parse_result.get("primitiveCount")) > 120_000
        or as_int(parse_result.get("estimatedPrimitiveMemory")) >= 96 * 1024 * 1024
        or as_int(parse_result.get("parseMilliseconds")) >= 15_000
    ):
        return "tile"
    return "vector"


def build_diagnostics(
    dwg_path: Path,
    parse_result: dict[str, Any],
    extra_font_dirs: list[Path],
) -> dict[str, Any]:
    attach_xref_resolution(parse_result, dwg_path)
    attach_text_diagnostics(parse_result)

    entity_counts = as_dict(parse_result.get("entityCountByType"))
    unsupported_counts = as_dict(parse_result.get("unsupportedEntityCountByType"))
    text_samples = [item for item in as_list(parse_result.get("textSamples")) if isinstance(item, dict)]
    trace_entries = text_trace_entries(parse_result)
    for trace in trace_entries:
        base_warnings = trace.get("warnings")
        existing = [str(item) for item in base_warnings] if isinstance(base_warnings, list) else []
        merged = sorted(set(existing + trace_warning_tags(trace)))
        trace["warnings"] = merged
    trace_summary = text_trace_summary(trace_entries)
    text_styles = [item for item in as_list(parse_result.get("textStyles")) if isinstance(item, dict)]
    missing_fonts, missing_big_fonts = collect_font_gaps(
        dwg_path,
        text_styles,
        text_samples,
        extra_font_dirs,
    )

    xrefs = [
        item
        for item in as_list(parse_result.get("xrefs"))
        if isinstance(item, dict) and str(item.get("savedPath") or "").strip()
    ]
    missing_xrefs = sorted({
        str(item.get("savedPath") or item.get("name") or "未命名 XREF")
        for item in xrefs
        if item.get("localStatus") == "missing"
    })

    suspicious_samples = compact_samples(
        text_issue_samples(
            parse_result,
            {
                "latin1-mojibake",
                "halfwidth-katakana-mojibake",
                "mixed-symbol-mojibake",
                "non-gbk-fallback-decode",
                "question-mark-loss",
                "replacement-character",
                "suspicious-text",
            },
        )
    )
    unicode_samples = compact_samples(
        text_issue_samples(parse_result, {"unexpanded-autocad-escape", "unicode-escape"})
    )
    control_samples = compact_samples(
        text_issue_samples(
            parse_result,
            {
                "unexpanded-mtext-control",
                "unexpanded-cad-control-code",
                "autocad-mtext-control",
                "autocad-control-code",
            },
        )
    )
    unresolved_samples = compact_samples(as_dict(parse_result.get("textDiagnostics")).get("issueSamples", []))

    total_objects = max(as_int(parse_result.get("totalObjectCount")), 1)
    unsupported_ratio = as_int(parse_result.get("unsupportedEntityCount")) / total_objects
    text_diagnostics = as_dict(parse_result.get("textDiagnostics"))
    sample_count = max(as_int(text_diagnostics.get("sampleCount")), 1)
    mojibake_ratio = as_int(text_diagnostics.get("issueSampleCount")) / sample_count

    warnings = build_warnings(
        parse_result,
        unsupported_ratio,
        mojibake_ratio,
        missing_fonts,
        missing_big_fonts,
        missing_xrefs,
        unicode_samples,
        control_samples,
    )
    if trace_summary["ordinaryChineseIncorrectlySentToSHXCount"] > 0:
        warnings.append(
            "严重：ordinaryChineseIncorrectlySentToSHXCount > 0，普通中文被错误送入 SHX 回退。"
        )
    score = quality_score(
        parse_result,
        unsupported_ratio,
        mojibake_ratio,
        missing_fonts,
        missing_big_fonts,
        missing_xrefs,
        len(control_samples),
    )
    viewer_mode = suggested_viewer_mode(parse_result, score)

    file_size = dwg_path.stat().st_size if dwg_path.exists() else 0
    diagnostics = {
        "schema": "CADDrawingDiagnostics/v1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "fileName": dwg_path.name,
        "fileSize": file_size,
        "dwgVersion": str(parse_result.get("dwgVersionCode") or parse_result.get("dwgVersionDescription") or ""),
        "dwgCodePage": str(parse_result.get("effectiveCodepage") or parse_result.get("headerCodepage") or ""),
        "layoutCount": as_int(parse_result.get("layoutCount")),
        "layerCount": as_int(parse_result.get("layerCount")),
        "blockCount": as_int(parse_result.get("blockCount")),
        "entityCountByType": entity_counts,
        "unsupportedEntityCountByType": unsupported_counts,
        "textEntityCount": as_int(entity_counts.get("TEXT")),
        "mtextEntityCount": as_int(entity_counts.get("MTEXT")),
        "attribEntityCount": as_int(entity_counts.get("ATTRIB")) + as_int(entity_counts.get("ATTDEF")),
        "dimensionEntityCount": count_dimension_entities(entity_counts),
        "textStyleCount": as_int(parse_result.get("textStyleCount")),
        "textStyles": [
            {
                "styleName": str(style.get("styleName", "")),
                "fontFile": str(style.get("fontFile", "")),
                "bigFontFile": str(style.get("bigFontFile", "")),
                "usedByCount": as_int(style.get("usedByCount")),
            }
            for style in text_styles
        ],
        "missingFonts": missing_fonts,
        "missingBigFonts": missing_big_fonts,
        "suspiciousMojibakeSamples": suspicious_samples,
        "unicodeEscapeSamples": unicode_samples,
        "autocadControlCodeSamples": control_samples,
        "unresolvedTextSamples": unresolved_samples,
        "xrefCount": len(xrefs),
        "missingXrefs": missing_xrefs,
        "warnings": warnings,
        "qualityScore": score,
        "viewerMode": viewer_mode,
        "summary": {
            "entityTotal": as_int(parse_result.get("totalObjectCount")),
            "drawablePrimitiveTotal": as_int(parse_result.get("primitiveCount")),
            "unsupportedRatio": unsupported_ratio,
            "mojibakeSampleRatio": mojibake_ratio,
            "parseMilliseconds": as_int(parse_result.get("parseMilliseconds")),
            "estimatedPrimitiveMemory": as_int(parse_result.get("estimatedPrimitiveMemory")),
        },
        "textTraceSummary": trace_summary,
        "textSamples": text_samples,
        "textTrace": trace_entries,
        "xrefs": xrefs,
        "probe": parse_result,
    }
    return diagnostics


def print_summary(diagnostics: dict[str, Any], output_path: Path) -> None:
    summary = as_dict(diagnostics.get("summary"))
    print(f"diagnostics: {output_path}")
    print(f"总图元数: {summary.get('entityTotal', 0)}")
    print(f"未支持图元比例: {float(summary.get('unsupportedRatio', 0.0)):.1%}")
    print(f"乱码疑似比例: {float(summary.get('mojibakeSampleRatio', 0.0)):.1%}")
    print(f"缺失字体: {', '.join(diagnostics.get('missingFonts') or []) or '无'}")
    print(f"缺失 BigFont: {', '.join(diagnostics.get('missingBigFonts') or []) or '无'}")
    print(f"缺失外部参照: {', '.join(diagnostics.get('missingXrefs') or []) or '无'}")
    print(f"建议 viewerMode: {diagnostics.get('viewerMode')}")
    print(f"qualityScore: {diagnostics.get('qualityScore')}")


def write_text_trace_jsonl(trace_entries: list[dict[str, Any]], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for trace in trace_entries:
            handle.write(json.dumps(trace, ensure_ascii=False) + "\n")


def emit_trace_debug_logs(trace_entries: list[dict[str, Any]]) -> None:
    tag_counts: dict[str, int] = {}
    detailed_tags = {
        "contains-replacement-char",
        "contains-question-mark",
        "contains-unicode-escape",
        "contains-autocad-control-code",
        "contains-mojibake-token",
        "used-shx-fallback",
        "question-mark-only",
        "ordinary-chinese-sent-to-shx",
    }
    detailed_count = 0
    detailed_limit = 200
    for trace in trace_entries:
        warnings = trace_warning_tags(trace)
        if not warnings:
            continue
        for warning in warnings:
            tag_counts[warning] = tag_counts.get(warning, 0) + 1
        if not any(warning in detailed_tags for warning in warnings):
            continue
        if detailed_count >= detailed_limit:
            continue
        entity_id = str(trace.get("entityId") or trace.get("entityType") or "text")
        entity_type = str(trace.get("entityType") or "text")
        print(
            f"TRACE [{entity_id}] type={entity_type} warnings={','.join(warnings)}",
            file=sys.stderr,
        )
        detailed_count += 1
    if detailed_count >= detailed_limit:
        print(f"TRACE detailed warning logs reached limit={detailed_limit}", file=sys.stderr)
    if tag_counts:
        joined = ",".join(f"{key}={tag_counts[key]}" for key in sorted(tag_counts))
        print(f"TRACE warning-counts: {joined}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="cad-diagnose",
        description="Generate CADDrawingDiagnostics JSON without attempting text repair.",
    )
    parser.add_argument("dwg_file", type=Path, help="DWG file to diagnose.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("diagnostics.json"),
        help="Output diagnostics JSON path. Defaults to ./diagnostics.json.",
    )
    parser.add_argument(
        "--parser",
        type=Path,
        help="Existing dwg_probe executable. If omitted, the probe is built first.",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=DEFAULT_PROBE_BUILD_DIR,
        help="Directory for the generated parser probe executable.",
    )
    parser.add_argument(
        "--parser-timeout",
        type=int,
        default=180,
        help="Seconds before DWG parsing is treated as failed.",
    )
    parser.add_argument(
        "--font-dir",
        type=Path,
        action="append",
        default=[],
        help="Additional local font/SHX directory to check for missing fonts.",
    )
    parser.add_argument(
        "--text-trace-output",
        type=Path,
        default=Path("text_trace.jsonl"),
        help="Output text trace JSONL path. Defaults to ./text_trace.jsonl.",
    )
    parser.add_argument(
        "--text-trace-summary-output",
        type=Path,
        default=Path("text_trace_summary.json"),
        help="Output text trace summary JSON path. Defaults to ./text_trace_summary.json.",
    )
    args = parser.parse_args()

    repo_root = repo_root_from_script()
    dwg_path = args.dwg_file if args.dwg_file.is_absolute() else (Path.cwd() / args.dwg_file)
    dwg_path = dwg_path.resolve()
    if not dwg_path.exists():
        print(f"ERROR DWG file not found: {dwg_path}", file=sys.stderr)
        return 2

    try:
        if args.parser:
            probe = args.parser if args.parser.is_absolute() else repo_root / args.parser
        else:
            build_dir = args.build_dir if args.build_dir.is_absolute() else repo_root / args.build_dir
            probe = build_probe(repo_root, build_dir)
        parse_result = run_probe(probe, dwg_path, max(args.parser_timeout, 1))
        font_dirs = [path.resolve() for path in args.font_dir]
        diagnostics = build_diagnostics(dwg_path, parse_result, font_dirs)
    except Exception as exc:  # noqa: BLE001 - command should always produce an actionable error.
        print(f"ERROR cad diagnostics failed: {exc}", file=sys.stderr)
        return 2

    output_path = args.output if args.output.is_absolute() else (Path.cwd() / args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(diagnostics, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    trace_entries = [item for item in as_list(diagnostics.get("textTrace")) if isinstance(item, dict)]
    trace_output_path = args.text_trace_output if args.text_trace_output.is_absolute() else (Path.cwd() / args.text_trace_output)
    write_text_trace_jsonl(trace_entries, trace_output_path)
    trace_summary = as_dict(diagnostics.get("textTraceSummary"))
    trace_summary_output_path = (
        args.text_trace_summary_output
        if args.text_trace_summary_output.is_absolute()
        else (Path.cwd() / args.text_trace_summary_output)
    )
    trace_summary_output_path.parent.mkdir(parents=True, exist_ok=True)
    trace_summary_output_path.write_text(
        json.dumps(trace_summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print_summary(diagnostics, output_path)
    print(f"text trace: {trace_output_path}")
    print(f"text trace summary: {trace_summary_output_path}")
    emit_trace_debug_logs(trace_entries)
    severe = as_int(trace_summary.get("ordinaryChineseIncorrectlySentToSHXCount")) > 0
    if severe:
        print(
            "SEVERE text trace: ordinaryChineseIncorrectlySentToSHXCount > 0",
            file=sys.stderr,
        )
    if severe:
        return 1
    return 0 if parse_result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
