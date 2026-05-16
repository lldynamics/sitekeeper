#!/usr/bin/env python3
"""Minimal HTTP worker for SiteKeeper DWG conversion.

The iOS app posts raw DWG bytes to /convert/dwg. This service runs the external
LibreDWG converter and returns drawing.sitekeeper-cad.json. LibreDWG still stays
outside the iOS app process and production target.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote


def write_json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    data = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def safe_file_name(raw: str | None) -> str:
    name = unquote(raw or "").split("/")[-1].split("\\")[-1].strip()
    if not name:
        return "original.dwg"
    return name if name.lower().endswith(".dwg") else f"{name}.dwg"


def diagnostic_payload(file_name: str, code: str, message: str, detail: str) -> dict[str, Any]:
    return {
        "schema": "sitekeeper-cad-worker-v1",
        "drawingId": str(uuid.uuid5(uuid.NAMESPACE_URL, file_name)),
        "importSource": "sitekeeper.dwg.libredwg",
        "geometryParsed": False,
        "isDiagnosticOnly": True,
        "units": {"name": "unitless"},
        "extents": {"minX": 0, "minY": 0, "maxX": 0, "maxY": 0},
        "layers": [{"id": "0", "name": "0"}],
        "layouts": [{"id": "model", "name": "Model", "isModelSpace": True}],
        "textStyles": [{"id": "standard", "name": "Standard"}],
        "blocks": [],
        "entities": [],
        "xrefs": [],
        "diagnostics": {
            "entries": [
                {
                    "id": code,
                    "severity": "error",
                    "code": code,
                    "message": message,
                    "detail": detail,
                }
            ]
        },
        "performanceTrace": {
            "fileSizeBytes": 0,
            "entityCount": 0,
            "visibleEntityCount": 0,
            "renderCommandCount": 0,
            "drawCallCount": 0,
            "spatialIndexBuildMs": 0,
            "resolveMs": 0,
            "renderMs": 0,
            "firstFrameMs": 0,
            "frameTimeMilliseconds": 0,
            "peakMemoryMB": 0,
            "skippedEntityCount": 0,
            "warnings": [f"{code}:{message}"],
        },
        "textTrace": [],
        "importWarnings": [f"{code}:{message}"],
    }


class ConversionHandler(BaseHTTPRequestHandler):
    converter: Path
    max_upload_bytes: int

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler naming.
        if self.path == "/health":
            write_json_response(self, 200, {"ok": True, "service": "sitekeeper-cad-libredwg"})
            return
        write_json_response(self, 404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler naming.
        if self.path != "/convert/dwg":
            write_json_response(self, 404, {"error": "not_found"})
            return

        try:
            content_length = int(self.headers.get("Content-Length") or "0")
        except ValueError:
            content_length = 0
        if content_length <= 0:
            write_json_response(self, 400, {"error": "empty_body"})
            return
        if content_length > self.max_upload_bytes:
            write_json_response(self, 413, {"error": "upload_too_large", "maxBytes": self.max_upload_bytes})
            return

        file_name = safe_file_name(self.headers.get("X-SiteKeeper-File-Name"))
        started = time.perf_counter()
        with tempfile.TemporaryDirectory(prefix="sitekeeper-dwg-worker-") as temp:
            temp_dir = Path(temp)
            dwg_path = temp_dir / file_name
            output_dir = temp_dir / "output"
            dwg_path.write_bytes(self.rfile.read(content_length))

            command = [str(self.converter), str(dwg_path), "--output", str(output_dir)]
            completed = subprocess.run(command, text=True, capture_output=True, check=False)
            drawing_path = output_dir / "drawing.sitekeeper-cad.json"
            if drawing_path.exists() and drawing_path.stat().st_size > 0:
                data = drawing_path.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("X-SiteKeeper-Worker-Exit-Code", str(completed.returncode))
                self.end_headers()
                self.wfile.write(data)
                return

            detail = completed.stderr or completed.stdout or "converter did not produce drawing.sitekeeper-cad.json"
            payload = diagnostic_payload(
                file_name=file_name,
                code="CAD_WORKER_CONVERSION_FAILED",
                message="LibreDWG worker did not produce a CADDatabase JSON file.",
                detail=detail,
            )
            payload["performanceTrace"]["resolveMs"] = int((time.perf_counter() - started) * 1000)
            write_json_response(self, 502, payload)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"{self.address_string()} - {format % args}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Serve SiteKeeper DWG conversion over HTTP.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--converter",
        type=Path,
        default=Path(__file__).with_name("convert_dwg_to_sitekeeper_json.py"),
    )
    parser.add_argument("--max-upload-mb", type=int, default=150)
    args = parser.parse_args()

    handler = ConversionHandler
    handler.converter = args.converter.resolve()
    handler.max_upload_bytes = max(args.max_upload_mb, 1) * 1024 * 1024

    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"SiteKeeper CAD LibreDWG conversion service listening on http://{args.host}:{args.port}")
    print("POST raw DWG bytes to /convert/dwg")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
