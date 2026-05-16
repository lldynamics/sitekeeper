#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <input.dwg> [output-directory]" >&2
  exit 64
fi

input_dwg="$1"
if [[ ! -f "$input_dwg" ]]; then
  echo "Input DWG does not exist: $input_dwg" >&2
  exit 66
fi

output_dir="${2:-$(dirname "$input_dwg")}"
mkdir -p "$output_dir"

base_name="$(basename "$input_dwg")"
stem="${base_name%.*}"
output_dxf="$output_dir/$stem.dxf"
log_file="$output_dir/$stem.libredwg.log"
trace_file="$output_dir/$stem.libredwg_trace.json"

count_dxf_lines() {
  python3 - "$1" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print(0)
    raise SystemExit

lines = path.read_text(errors="ignore").replace("\r\n", "\n").replace("\r", "\n").split("\n")
pairs = []
index = 0
while index + 1 < len(lines):
    try:
        code = int(lines[index].strip())
    except ValueError:
        index += 2
        continue
    pairs.append((code, lines[index + 1].strip()))
    index += 2

in_entities = False
count = 0
for idx, (code, value) in enumerate(pairs):
    upper = value.upper()
    if code == 0 and upper == "SECTION" and idx + 1 < len(pairs):
        next_code, next_value = pairs[idx + 1]
        in_entities = next_code == 2 and next_value.upper() == "ENTITIES"
        continue
    if in_entities and code == 0 and upper == "ENDSEC":
        in_entities = False
        continue
    if in_entities and code == 0 and upper == "LINE":
        count += 1
print(count)
PY
}

write_trace() {
  local tool="$1"
  local status="$2"
  local exit_code="$3"
  local raw_line_count="0"
  local output_size="0"
  if [[ -f "$output_dxf" ]]; then
    raw_line_count="$(count_dxf_lines "$output_dxf")"
    output_size="$(wc -c < "$output_dxf" | tr -d ' ')"
  fi

  python3 - "$trace_file" "$input_dwg" "$output_dxf" "$tool" "$status" "$exit_code" "$raw_line_count" "$output_size" "$log_file" <<'PY'
import json
import sys
from pathlib import Path

trace_path = Path(sys.argv[1])
log_path = Path(sys.argv[9])
stderr_tail = ""
if log_path.exists():
    stderr_tail = "\n".join(log_path.read_text(errors="ignore").splitlines()[-40:])

payload = {
    "inputDWG": sys.argv[2],
    "outputDXF": sys.argv[3],
    "tool": sys.argv[4],
    "status": sys.argv[5],
    "exitCode": int(sys.argv[6]),
    "rawLineCount": int(sys.argv[7]),
    "outputDXFSizeBytes": int(sys.argv[8]),
    "logFile": str(log_path),
    "stderrTail": stderr_tail,
}
trace_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
PY
}

if command -v dwg2dxf >/dev/null 2>&1; then
  if dwg2dxf -y -o "$output_dxf" "$input_dwg" 2> "$log_file"; then
    write_trace "dwg2dxf" "converted" 0
    echo "$output_dxf"
    exit 0
  fi
  exit_code=$?
  write_trace "dwg2dxf" "failed" "$exit_code"
  exit "$exit_code"
fi

if command -v dwgread >/dev/null 2>&1; then
  if dwgread -O DXF -o "$output_dxf" "$input_dwg" 2> "$log_file"; then
    write_trace "dwgread" "converted" 0
    echo "$output_dxf"
    exit 0
  fi
  exit_code=$?
  write_trace "dwgread" "failed" "$exit_code"
  exit "$exit_code"
fi

echo "Neither dwg2dxf nor dwgread is available on PATH." > "$log_file"
write_trace "none" "missing_tools" 127
exit 127
