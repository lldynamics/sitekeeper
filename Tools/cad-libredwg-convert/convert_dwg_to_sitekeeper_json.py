#!/usr/bin/env python3
"""External LibreDWG worker that emits SiteKeeper CAD kernel artifacts.

The iOS app must not execute or link LibreDWG. This worker is intended to run
outside the app process, then hand the app a drawing.sitekeeper-cad.json file.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any


TEXT_UNICODE_RE = re.compile(r"\\U\+([0-9A-Fa-f]{4})")


def run_command(args: list[str]) -> dict[str, Any]:
    started = time.perf_counter()
    try:
        completed = subprocess.run(args, text=True, capture_output=True, check=False)
    except FileNotFoundError as error:
        return {
            "args": args,
            "returncode": 127,
            "stdout": "",
            "stderr": str(error),
            "elapsedMs": int((time.perf_counter() - started) * 1000),
        }
    return {
        "args": args,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "elapsedMs": int((time.perf_counter() - started) * 1000),
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def as_float(value: Any, default: float = 0) -> float:
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    if isinstance(value, str):
        try:
            parsed = float(value)
            return parsed if math.isfinite(parsed) else default
        except ValueError:
            return default
    return default


def handle_value(value: Any) -> str | None:
    if isinstance(value, list) and value:
        return str(value[-1])
    if isinstance(value, dict):
        for key in ("handle", "id", "name", "value"):
            if value.get(key) is not None:
                return str(value[key])
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def entity_type(item: dict[str, Any]) -> str:
    for key in ("entity", "object", "type", "entityType"):
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip().upper().replace("-", "_")
    return "UNSUPPORTED"


def point_from_value(value: Any) -> dict[str, float] | None:
    if isinstance(value, list) and len(value) >= 2:
        return {"x": as_float(value[0]), "y": as_float(value[1])}
    if isinstance(value, dict):
        if "x" in value or "y" in value:
            return {"x": as_float(value.get("x")), "y": as_float(value.get("y"))}
    return None


def point_from_keys(item: dict[str, Any], keys: list[str]) -> dict[str, float] | None:
    for key in keys:
        point = point_from_value(item.get(key))
        if point is not None:
            return point
    return None


def bounds_from_points(points: list[dict[str, float]]) -> dict[str, float]:
    if not points:
        return {"minX": 0, "minY": 0, "maxX": 0, "maxY": 0}
    xs = [point["x"] for point in points]
    ys = [point["y"] for point in points]
    return {"minX": min(xs), "minY": min(ys), "maxX": max(xs), "maxY": max(ys)}


def bounds_for_text(point: dict[str, float], text: str, height: float) -> dict[str, float]:
    width = max(len(text), 1) * max(height, 1) * 0.6
    return {
        "minX": point["x"],
        "minY": point["y"],
        "maxX": point["x"] + width,
        "maxY": point["y"] + max(height, 1),
    }


def union_bounds(bounds: list[dict[str, float]]) -> dict[str, float]:
    non_empty = [item for item in bounds if item["minX"] <= item["maxX"] and item["minY"] <= item["maxY"]]
    if not non_empty:
        return {"minX": 0, "minY": 0, "maxX": 0, "maxY": 0}
    return {
        "minX": min(item["minX"] for item in non_empty),
        "minY": min(item["minY"] for item in non_empty),
        "maxX": max(item["maxX"] for item in non_empty),
        "maxY": max(item["maxY"] for item in non_empty),
    }


def decode_text(raw: str) -> str:
    return TEXT_UNICODE_RE.sub(lambda match: chr(int(match.group(1), 16)), raw)


def normalize_text(decoded: str) -> str:
    output: list[str] = []
    index = 0
    while index < len(decoded):
        chunk = decoded[index:index + 3].lower()
        if chunk == "%%d":
            output.append("°")
            index += 3
        elif chunk == "%%p":
            output.append("±")
            index += 3
        elif chunk == "%%c":
            output.append("∅")
            index += 3
        elif chunk == "%%%":
            output.append("%")
            index += 3
        else:
            output.append(decoded[index])
            index += 1
    text = "".join(output)
    text = text.replace("\\P", "\n").replace("\\p", "\n").replace("\\~", " ")
    text = re.sub(r"\\[fFHhWwQqAaCcp][^;]*;", "", text)
    text = re.sub(r"\\S([^;]+);", lambda match: match.group(1).replace("#", "/").replace("^", "/"), text)
    text = text.replace("{", "").replace("}", "")
    return text


def make_text_trace(entity_id: str, entity_kind: str, raw: str, style: dict[str, Any]) -> dict[str, Any]:
    decoded = decode_text(raw)
    normalized = normalize_text(decoded)
    warnings: list[str] = []
    font_file = style.get("fontFile")
    big_font_file = style.get("bigFontFile")
    if font_file:
        warnings.append(f"CAD_WORKER_FONT_NOT_VALIDATED:{font_file}")
    if big_font_file:
        warnings.append(f"CAD_WORKER_BIGFONT_NOT_VALIDATED:{big_font_file}")
    return {
        "entityId": entity_id,
        "entityType": entity_kind.lower(),
        "rawText": raw,
        "decodedText": decoded,
        "normalizedText": normalized,
        "displayText": normalized,
        "textStyleName": style.get("name", "Standard"),
        "fontFile": font_file,
        "bigFontFile": big_font_file,
        "selectedFontName": "worker-unresolved",
        "fontWasAvailable": False if font_file else True,
        "fallbackReason": "resolved-in-app-cad-text-engine",
        "warnings": warnings,
    }


def style_lookup(item: dict[str, Any], style_by_handle: dict[str, dict[str, Any]]) -> dict[str, Any]:
    handle = handle_value(item.get("style") or item.get("styleHandle") or item.get("textStyle"))
    if handle and handle.lower() in style_by_handle:
        return style_by_handle[handle.lower()]
    return {"id": "standard", "name": "Standard"}


def layer_id(item: dict[str, Any], layer_by_handle: dict[str, str]) -> str:
    raw = handle_value(item.get("layer") or item.get("layerId") or item.get("layerID"))
    if not raw:
        return "0"
    return layer_by_handle.get(raw.lower(), raw)


def convert_libredwg_json(raw_payload: Any, source_file: Path) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    objects = as_list(raw_payload.get("OBJECTS") if isinstance(raw_payload, dict) else raw_payload)
    if not objects and isinstance(raw_payload, dict):
        objects = as_list(raw_payload.get("objects")) + as_list(raw_payload.get("entities"))

    layers: dict[str, dict[str, Any]] = {"0": {"id": "0", "name": "0"}}
    layer_by_handle: dict[str, str] = {}
    styles: dict[str, dict[str, Any]] = {
        "standard": {"id": "standard", "name": "Standard", "fontName": None, "bigFontName": None}
    }
    style_by_handle: dict[str, dict[str, Any]] = {}

    for item in [as_dict(value) for value in objects]:
        kind = entity_type(item)
        handle = handle_value(item.get("handle"))
        if kind == "LAYER":
            name = str(item.get("name") or handle or "0")
            layers[name] = {"id": name, "name": name}
            if handle:
                layer_by_handle[handle.lower()] = name
        elif kind == "STYLE":
            name = str(item.get("name") or handle or "Standard")
            style = {
                "id": name.lower(),
                "name": name,
                "fontName": item.get("font") or item.get("font_name"),
                "bigFontName": item.get("bigfont") or item.get("bigfont_name"),
                "fontFile": item.get("font_file"),
                "bigFontFile": item.get("bigfont_file"),
            }
            styles[style["id"]] = {key: value for key, value in style.items() if value is not None}
            if handle:
                style_by_handle[handle.lower()] = style

    entities: list[dict[str, Any]] = []
    text_traces: list[dict[str, Any]] = []
    unsupported: list[dict[str, Any]] = []

    for item in [as_dict(value) for value in objects]:
        raw_kind = entity_type(item)
        handle = handle_value(item.get("handle")) or str(uuid.uuid4())
        layer = layer_id(item, layer_by_handle)
        common = {"handle": handle, "sourceHandle": handle, "layerID": layer}
        if layer not in layers:
            layers[layer] = {"id": layer, "name": layer}

        if raw_kind == "LINE":
            start = point_from_keys(item, ["start", "startPoint", "start_pt", "pt1"]) or {"x": as_float(item.get("x1") or item.get("10")), "y": as_float(item.get("y1") or item.get("20"))}
            end = point_from_keys(item, ["end", "endPoint", "end_pt", "pt2"]) or {"x": as_float(item.get("x2") or item.get("11")), "y": as_float(item.get("y2") or item.get("21"))}
            entities.append({**common, "type": "line", "start": start, "end": end, "bounds": bounds_from_points([start, end])})
        elif raw_kind in {"LWPOLYLINE", "POLYLINE", "SPLINE", "HATCH"}:
            points = [
                point for point in (point_from_value(value) for value in as_list(item.get("points") or item.get("vertices")))
                if point is not None
            ]
            if points:
                entity_type_name = "lwPolyline" if raw_kind == "LWPOLYLINE" else raw_kind.lower()
                entities.append({**common, "type": entity_type_name, "points": points, "isClosed": bool(item.get("closed") or item.get("isClosed")), "bounds": bounds_from_points(points)})
            else:
                unsupported.append({"id": handle, "type": raw_kind, "reason": "No supported boundary points."})
        elif raw_kind in {"CIRCLE", "ARC"}:
            center = point_from_keys(item, ["center", "centerPoint", "center_pt"]) or {"x": as_float(item.get("x") or item.get("10")), "y": as_float(item.get("y") or item.get("20"))}
            radius = as_float(item.get("radius") or item.get("40"), 1)
            entities.append({
                **common,
                "type": raw_kind.lower(),
                "center": center,
                "radius": radius,
                "bounds": {"minX": center["x"] - radius, "minY": center["y"] - radius, "maxX": center["x"] + radius, "maxY": center["y"] + radius},
            })
        elif raw_kind in {"TEXT", "MTEXT", "ATTRIB", "ATTDEF"}:
            raw_text = str(item.get("rawText") or item.get("text") or item.get("text_value") or item.get("contents") or item.get("default_value") or "")
            insertion = point_from_keys(item, ["insertionPoint", "insert", "ins_pt", "position", "pt"]) or {"x": as_float(item.get("x") or item.get("10")), "y": as_float(item.get("y") or item.get("20"))}
            style = style_lookup(item, style_by_handle)
            trace = make_text_trace(handle, "attrib" if raw_kind == "ATTDEF" else raw_kind, raw_text, style)
            text_traces.append(trace)
            height = as_float(item.get("height") or item.get("text_height") or item.get("40"), 2.5)
            entities.append({
                **common,
                "type": "attrib" if raw_kind in {"ATTRIB", "ATTDEF"} else raw_kind.lower(),
                "rawText": raw_text,
                "displayText": trace["displayText"],
                "textStyleId": str(style.get("id") or "standard"),
                "textStyleName": str(style.get("name") or "Standard"),
                "insertionPoint": insertion,
                "bounds": bounds_for_text(insertion, trace["displayText"], height),
            })
        elif raw_kind == "INSERT":
            insertion = point_from_keys(item, ["insertionPoint", "insert", "ins_pt", "position", "pt"]) or {"x": as_float(item.get("x") or item.get("10")), "y": as_float(item.get("y") or item.get("20"))}
            block_name = str(item.get("blockName") or item.get("name") or item.get("block") or "")
            entities.append({**common, "type": "insert", "blockName": block_name, "insertionPoint": insertion, "bounds": bounds_from_points([insertion])})
        elif raw_kind not in {"LAYER", "STYLE", "BLOCK", "ENDBLK", "VERTEX", "SEQEND"}:
            unsupported.append({"id": handle, "type": raw_kind, "reason": "Unsupported LibreDWG JSON object in worker v1."})

    payload = {
        "schema": "sitekeeper-cad-worker-v1",
        "drawingId": str(uuid.uuid5(uuid.NAMESPACE_URL, str(source_file.resolve()))),
        "units": {"name": "unitless"},
        "extents": union_bounds([as_dict(entity.get("bounds")) for entity in entities]),
        "layers": list(layers.values()),
        "layouts": [{"id": "model", "name": "Model", "isModelSpace": True}],
        "textStyles": list(styles.values()),
        "blocks": [],
        "entities": entities,
        "xrefs": [],
    }
    return payload, text_traces, unsupported


def decode_dxf_pairs(contents: str) -> list[tuple[int, str]]:
    lines = contents.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    pairs: list[tuple[int, str]] = []
    index = 0
    while index + 1 < len(lines):
        try:
            pairs.append((int(lines[index].strip()), lines[index + 1].strip("\n")))
        except ValueError:
            pass
        index += 2
    return pairs


def dxf_records(path: Path) -> list[list[tuple[int, str]]]:
    pairs = decode_dxf_pairs(path.read_text(encoding="utf-8", errors="replace"))
    in_entities = False
    records: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    for code, value in pairs:
        normalized = value.strip().upper()
        if code == 0 and normalized == "SECTION":
            current = []
        elif code == 2 and normalized == "ENTITIES":
            in_entities = True
        elif code == 0 and normalized == "ENDSEC" and in_entities:
            if current:
                records.append(current)
            break
        elif in_entities and code == 0:
            if current:
                records.append(current)
            current = [(code, normalized)]
        elif in_entities:
            current.append((code, value.strip()))
    return records


def values(record: list[tuple[int, str]], code: int) -> list[str]:
    return [value for pair_code, value in record if pair_code == code]


def first(record: list[tuple[int, str]], code: int, default: str = "") -> str:
    found = values(record, code)
    return found[0] if found else default


def convert_dxf(path: Path, source_file: Path) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]]]:
    entities: list[dict[str, Any]] = []
    layers: dict[str, dict[str, Any]] = {"0": {"id": "0", "name": "0"}}
    text_traces: list[dict[str, Any]] = []
    unsupported: list[dict[str, Any]] = []

    for index, record in enumerate(dxf_records(path)):
        kind = record[0][1].upper() if record else "UNSUPPORTED"
        handle = first(record, 5, f"DXF-{index}")
        layer = first(record, 8, "0")
        layers.setdefault(layer, {"id": layer, "name": layer})
        common = {"handle": handle, "sourceHandle": handle, "layerID": layer}
        if kind == "LINE":
            start = {"x": as_float(first(record, 10)), "y": as_float(first(record, 20))}
            end = {"x": as_float(first(record, 11)), "y": as_float(first(record, 21))}
            entities.append({**common, "type": "line", "start": start, "end": end, "bounds": bounds_from_points([start, end])})
        elif kind == "LWPOLYLINE":
            xs, ys = values(record, 10), values(record, 20)
            points = [{"x": as_float(x), "y": as_float(y)} for x, y in zip(xs, ys)]
            entities.append({**common, "type": "lwPolyline", "points": points, "isClosed": first(record, 70) == "1", "bounds": bounds_from_points(points)})
        elif kind in {"CIRCLE", "ARC"}:
            center = {"x": as_float(first(record, 10)), "y": as_float(first(record, 20))}
            radius = as_float(first(record, 40), 1)
            entities.append({**common, "type": kind.lower(), "center": center, "radius": radius, "bounds": {"minX": center["x"] - radius, "minY": center["y"] - radius, "maxX": center["x"] + radius, "maxY": center["y"] + radius}})
        elif kind in {"TEXT", "MTEXT", "ATTRIB"}:
            raw = first(record, 1) or first(record, 3)
            insertion = {"x": as_float(first(record, 10)), "y": as_float(first(record, 20))}
            trace = make_text_trace(handle, kind, raw, {"id": "standard", "name": "Standard"})
            text_traces.append(trace)
            entities.append({**common, "type": kind.lower(), "rawText": raw, "displayText": trace["displayText"], "textStyleId": "standard", "textStyleName": "Standard", "insertionPoint": insertion, "bounds": bounds_for_text(insertion, trace["displayText"], as_float(first(record, 40), 2.5))})
        else:
            unsupported.append({"id": handle, "type": kind, "reason": "Unsupported DXF entity in worker v1."})

    payload = {
        "schema": "sitekeeper-cad-worker-v1",
        "drawingId": str(uuid.uuid5(uuid.NAMESPACE_URL, str(source_file.resolve()))),
        "units": {"name": "unitless"},
        "extents": union_bounds([as_dict(entity.get("bounds")) for entity in entities]),
        "layers": list(layers.values()),
        "layouts": [{"id": "model", "name": "Model", "isModelSpace": True}],
        "textStyles": [{"id": "standard", "name": "Standard"}],
        "blocks": [],
        "entities": entities,
        "xrefs": [],
    }
    return payload, text_traces, unsupported


def performance_trace(input_path: Path, command_ms: int, adapter_ms: int, entity_count: int, drawable_count: int, warnings: list[str]) -> dict[str, Any]:
    elapsed = command_ms + adapter_ms
    return {
        "fileSizeBytes": input_path.stat().st_size if input_path.exists() else 0,
        "entityCount": entity_count,
        "visibleEntityCount": drawable_count,
        "renderCommandCount": 0,
        "drawCallCount": 0,
        "spatialIndexBuildMs": 0,
        "resolveMs": elapsed,
        "renderMs": 0,
        "firstFrameMs": elapsed,
        "frameTimeMilliseconds": elapsed,
        "peakMemoryMB": 0,
        "skippedEntityCount": 0,
        "warnings": warnings,
    }


def drawing_diagnostics(entries: list[dict[str, Any]]) -> dict[str, Any]:
    normalized: list[dict[str, Any]] = []
    for entry in entries:
        code = str(entry.get("code") or "CAD_WORKER_DIAGNOSTIC")
        normalized.append({
            "id": str(entry.get("id") or code),
            "severity": str(entry.get("severity") or "warning"),
            "code": code,
            "message": str(entry.get("message") or ""),
            "detail": str(entry["detail"]) if entry.get("detail") is not None else None,
        })
    return {"entries": normalized}


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert DWG to SiteKeeper CAD worker artifacts without linking LibreDWG into the iOS app.")
    parser.add_argument("dwg", type=Path, help="Input original.dwg")
    parser.add_argument("--output", type=Path, required=True, help="Worker output directory")
    parser.add_argument("--font-package", type=Path, action="append", default=[], help="Optional font package directory/archive reference")
    parser.add_argument("--xref-package", type=Path, action="append", default=[], help="Optional xref package directory/archive reference")
    parser.add_argument("--dwgread", default=shutil.which("dwgread") or "dwgread")
    parser.add_argument("--dwg2dxf", default=shutil.which("dwg2dxf") or "dwg2dxf")
    args = parser.parse_args()

    started = time.perf_counter()
    args.output.mkdir(parents=True, exist_ok=True)
    raw_json = args.output / "libredwg.raw.json"
    converted_dxf = args.output / "libredwg.converted.dxf"
    drawing_path = args.output / "drawing.sitekeeper-cad.json"
    diagnostics_path = args.output / "diagnostics.json"
    performance_path = args.output / "performance_trace.json"
    text_trace_path = args.output / "text_trace.jsonl"
    unsupported_path = args.output / "unsupported_entities.json"

    route = "failed"
    commands: list[dict[str, Any]] = []
    diagnostics: list[dict[str, Any]] = []
    warnings: list[str] = []
    payload: dict[str, Any] = {
        "schema": "sitekeeper-cad-worker-v1",
        "drawingId": str(uuid.uuid5(uuid.NAMESPACE_URL, str(args.dwg.resolve()))),
        "units": {"name": "unitless"},
        "extents": {"minX": 0, "minY": 0, "maxX": 0, "maxY": 0},
        "layers": [{"id": "0", "name": "0"}],
        "layouts": [{"id": "model", "name": "Model", "isModelSpace": True}],
        "textStyles": [{"id": "standard", "name": "Standard"}],
        "blocks": [],
        "entities": [],
        "xrefs": [],
    }
    text_traces: list[dict[str, Any]] = []
    unsupported: list[dict[str, Any]] = []

    json_result = run_command([args.dwgread, "-O", "JSON", "-o", str(raw_json), str(args.dwg)])
    commands.append(json_result)
    if json_result["returncode"] == 0 and raw_json.exists() and raw_json.stat().st_size > 0:
        try:
            adapter_started = time.perf_counter()
            payload, text_traces, unsupported = convert_libredwg_json(json.loads(raw_json.read_text(encoding="utf-8")), args.dwg)
            route = "json"
            adapter_ms = int((time.perf_counter() - adapter_started) * 1000)
        except Exception as error:  # noqa: BLE001 - worker records route diagnostics.
            diagnostics.append({"severity": "warning", "code": "LIBREDWG_JSON_IMPORT_FAILED", "message": str(error)})
            warnings.append(f"LIBREDWG_JSON_IMPORT_FAILED:{error}")
            adapter_ms = 0
    else:
        detail = json_result["stderr"] or json_result["stdout"] or "dwgread did not produce JSON"
        diagnostics.append({"severity": "warning", "code": "LIBREDWG_DWGREAD_FAILED", "message": detail})
        warnings.append("LIBREDWG_DWGREAD_FAILED")
        adapter_ms = 0

    if route != "json":
        dxf_result = run_command([args.dwg2dxf, "-o", str(converted_dxf), str(args.dwg)])
        commands.append(dxf_result)
        if dxf_result["returncode"] == 0 and converted_dxf.exists() and converted_dxf.stat().st_size > 0:
            try:
                adapter_started = time.perf_counter()
                payload, text_traces, unsupported = convert_dxf(converted_dxf, args.dwg)
                route = "dxf"
                adapter_ms += int((time.perf_counter() - adapter_started) * 1000)
            except Exception as error:  # noqa: BLE001
                diagnostics.append({"severity": "warning", "code": "DXF_IMPORT_FAILED", "message": str(error)})
                warnings.append(f"DXF_IMPORT_FAILED:{error}")
        else:
            detail = dxf_result["stderr"] or dxf_result["stdout"] or "dwg2dxf did not produce DXF"
            diagnostics.append({"severity": "warning", "code": "LIBREDWG_DWG2DXF_FAILED", "message": detail})
            warnings.append("LIBREDWG_DWG2DXF_FAILED")

    geometry_parsed = bool(payload.get("entities"))
    diagnostics.append({
        "severity": "info" if geometry_parsed else "warning",
        "code": "CAD_WORKER_GEOMETRY_PARSED" if geometry_parsed else "CAD_WORKER_DIAGNOSTIC_ONLY",
        "message": "Worker generated SiteKeeper CAD JSON." if geometry_parsed else "Worker did not generate drawable CAD entities.",
        "detail": route,
    })

    command_ms = sum(int(command.get("elapsedMs", 0)) for command in commands)
    perf = performance_trace(
        args.dwg,
        command_ms=command_ms,
        adapter_ms=adapter_ms,
        entity_count=len(payload.get("entities", [])),
        drawable_count=len(payload.get("entities", [])),
        warnings=warnings,
    )
    payload["importSource"] = "sitekeeper.dwg.libredwg"
    payload["geometryParsed"] = geometry_parsed
    payload["isDiagnosticOnly"] = not geometry_parsed
    payload["diagnostics"] = drawing_diagnostics(diagnostics)
    payload["performanceTrace"] = perf
    payload["textTrace"] = text_traces
    payload["importWarnings"] = warnings

    write_json(drawing_path, payload)
    write_json(performance_path, perf)
    write_jsonl(text_trace_path, text_traces)
    write_json(unsupported_path, {"count": len(unsupported), "unsupportedEntities": unsupported})
    write_json(diagnostics_path, {
        "input": str(args.dwg),
        "route": route,
        "geometryParsed": geometry_parsed,
        "drawableEntityCount": len(payload.get("entities", [])),
        "fontPackages": [str(path) for path in args.font_package],
        "xrefPackages": [str(path) for path in args.xref_package],
        "commands": commands,
        "diagnostics": diagnostics,
        "outputs": {
            "drawing": str(drawing_path),
            "diagnostics": str(diagnostics_path),
            "performanceTrace": str(performance_path),
            "textTrace": str(text_trace_path),
            "unsupportedEntities": str(unsupported_path),
        },
        "elapsedMs": int((time.perf_counter() - started) * 1000),
    })

    print(drawing_path)
    return 0 if geometry_parsed else 2


if __name__ == "__main__":
    raise SystemExit(main())
