#!/usr/bin/env python3
"""Compare matched Phase 1 benchmark logs; timings only apply to this test setup."""
import argparse
import json
from pathlib import Path


def records(path):
    result = {}
    for line in path.read_text(errors="replace").splitlines():
        marker = "PHASE1_BENCH "
        if marker not in line:
            continue
        value = json.loads(line.split(marker, 1)[1])
        key = (value["name"], value["logs"], value["financialRecords"], value["projects"])
        if key in result:
            raise ValueError(f"Duplicate workload in {path}: {key}")
        if len(value["samples_ms"]) != 7:
            raise ValueError(f"Incomplete samples in {path}: {key}")
        result[key] = value
    if not result:
        raise ValueError(f"No benchmark samples found in {path}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-regression", type=float,
                        help="Optional allowed ratio, for example 1.20; use only on a comparable idle host.")
    args = parser.parse_args()
    before, after = records(args.before), records(args.after)
    if set(before) != set(after):
        raise ValueError("Before/after workloads do not match; refusing a partial comparison")
    comparisons = []
    for key in sorted(before):
        old, new = before[key], after[key]
        if old["phase"] != "before" or new["phase"] != "after":
            raise ValueError("Unexpected phase labels")
        ratio = new["median_ms"] / old["median_ms"]
        comparisons.append({"name": key[0], "logs": key[1], "financialRecords": key[2], "projects": key[3],
                            "before_ms": old["median_ms"], "after_ms": new["median_ms"],
                            "after_over_before": ratio, "reduction_percent": (1 - ratio) * 100,
                            "before_samples_ms": old["samples_ms"], "after_samples_ms": new["samples_ms"]})
    output = {"scope": "Synthetic in-process workloads; optimized Debug, serial execution; not device UI FPS or launch acceptance",
              "comparisons": comparisons}
    with args.output.open("x") as handle:
        json.dump(output, handle, ensure_ascii=False, indent=2)
    for value in comparisons:
        print(f"{value['name']:24} {value['logs']:>7} logs: {value['before_ms']:.3f} -> "
              f"{value['after_ms']:.3f} ms ({value['reduction_percent']:+.1f}% reduction)")
    if args.max_regression is not None and any(v["after_over_before"] > args.max_regression for v in comparisons):
        raise SystemExit("At least one workload exceeded the requested regression ratio")


if __name__ == "__main__":
    main()
