#!/usr/bin/env python3
"""Compare paired opt-in macOS ImageIO/cache benchmark records, never process RSS.

Use --input for a host-test log containing both phases, or --before and --after
for separate logs. Single-test --filter output is supported; both sides must
contain exactly the same workloads, fixture hashes, sizes and cache budgets.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics

MARKER = "PHASE2_IMAGE_BENCH "
KEY_FIELDS = ("name", "fixture_sha256", "legacy_source_sha256", "max_pixel_size",
              "requests", "concurrency", "budget_bytes", "count_limit")
COUNT_FIELDS = ("decode_attempts", "successful_decodes", "retained_decoded_cost_bytes",
                "retained_entries", "evictions", "coalesced_requests")


def records(path: Path, phase: str) -> dict:
    result = {}
    for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if MARKER not in line:
            continue
        value = json.loads(line.split(MARKER, 1)[1])
        label = f"{path}:{number}"
        if value.get("phase") not in {"before", "after"}:
            raise ValueError(f"Unknown phase at {label}")
        if value["phase"] != phase:
            continue
        if value.get("schema") != 1 or value.get("warmups_per_phase") != 1:
            raise ValueError(f"Unexpected schema/warm-up count at {label}")
        key = tuple(value[field] for field in KEY_FIELDS)
        if key in result:
            raise ValueError(f"Duplicate {phase} workload at {label}: {key[0]}")
        samples = value["samples_ms"]
        if len(samples) != 7 or any(not isinstance(x, (int, float)) or not math.isfinite(x) or x < 0 for x in samples):
            raise ValueError(f"Expected seven finite nonnegative timings at {label}")
        if not math.isclose(statistics.median(samples), value["median_ms"], rel_tol=1e-12, abs_tol=1e-12):
            raise ValueError(f"Stored median differs from raw timings at {label}")
        for field in COUNT_FIELDS:
            counts = value[field]
            if len(counts) != 7 or any(type(x) is not int or x < 0 for x in counts):
                raise ValueError(f"Expected seven nonnegative integer {field} values at {label}")
        if any(success > attempts for success, attempts in zip(value["successful_decodes"], value["decode_attempts"])):
            raise ValueError(f"Successful decodes exceed attempts at {label}")
        if any(cost > value["budget_bytes"] for cost in value["retained_decoded_cost_bytes"]):
            raise ValueError(f"Retained decoded-cost budget exceeded at {label}")
        if phase == "before" and any(value["retained_decoded_cost_bytes"]):
            raise ValueError(f"The uncached reference retained cache entries at {label}")
        result[key] = value
    if not result:
        raise ValueError(f"No {phase} image benchmark records in {path}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="One host-test log containing both phases")
    parser.add_argument("--before", type=Path, help="Reference log (may also contain candidate records)")
    parser.add_argument("--after", type=Path, help="Candidate log (may also contain reference records)")
    parser.add_argument("--output", type=Path, required=True, help="New JSON file; never overwritten")
    args = parser.parse_args()
    if args.input:
        if args.before or args.after:
            parser.error("Use --input or the --before/--after pair")
        before_path = after_path = args.input
    elif args.before and args.after:
        before_path, after_path = args.before, args.after
    else:
        parser.error("Supply --input or both --before and --after")
    before, after = records(before_path, "before"), records(after_path, "after")
    if set(before) != set(after):
        raise ValueError("Workloads/fixtures/sizes/concurrency/budgets differ; refusing a partial comparison")
    comparisons = []
    for key in sorted(before):
        old, new = before[key], after[key]
        old_ms, new_ms = statistics.median(old["samples_ms"]), statistics.median(new["samples_ms"])
        ratio = new_ms / old_ms if old_ms > 0 else None
        counts = {
            field: {"before_median": statistics.median(old[field]), "after_median": statistics.median(new[field]),
                    "before_samples": old[field], "after_samples": new[field]}
            for field in COUNT_FIELDS
        }
        comparisons.append({
            **dict(zip(KEY_FIELDS, key)), "before_median_ms": old_ms, "after_median_ms": new_ms,
            "after_over_before": ratio, "reduction_percent": (1 - ratio) * 100 if ratio is not None else None,
            "before_samples_ms": old["samples_ms"], "after_samples_ms": new["samples_ms"],
            "counts": counts,
            "invalidation_includes_temporary_file_write": new["invalidation_includes_temporary_file_write"],
            "sample_preconditions": new["sample_preconditions"],
            "host_os": new["host_os"],
        })
    output = {
        "schema": 1, "before_log": str(before_path.resolve()), "after_log": str(after_path.resolve()),
        "scope": "Synthetic macOS ImageIO and production core cache; excludes UIKit, real-device/UI/FPS and process RSS acceptance",
        "memory_metric": "retained_decoded_cost_bytes is final cache budget accounting (bytesPerRow * height), not RSS or peak process memory",
        "cold_definition": "fresh application cache, not cold disk/OS/decoder state",
        "precondition_definition": "fixture encoding/preflight excluded; each warm_repeated and invalidate_reload session is preloaded outside the timer and decode-count deltas",
        "concurrency_definition": "eight same-key requests held behind a loader gate until eight reference loaders or one candidate loader plus seven coalesced waiters are registered; timed work includes gate coordination",
        "reference_definition": "frozen uncached URL ImageIO options with a utility detached worker; excludes FileIOTaskRunner logging/cancellation relay and UIImage wrapping",
        "sampling": "one unreported warm-up per phase, seven interleaved paired samples with alternating order; medians shown",
        "acceptance_note": "This file compares emitted metrics only. Check the host test exit status and full test summary separately.",
        "comparisons": comparisons,
    }
    with args.output.open("x") as handle:
        json.dump(output, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    for row in comparisons:
        attempts = row["counts"]["decode_attempts"]
        costs = row["counts"]["retained_decoded_cost_bytes"]
        print(f"{row['name']:22} {row['before_median_ms']:.3f} -> {row['after_median_ms']:.3f} ms; "
              f"decode attempts {attempts['before_median']} -> {attempts['after_median']}; "
              f"retained cache cost {costs['before_median']} -> {costs['after_median']} bytes (not RSS)")


if __name__ == "__main__":
    main()
