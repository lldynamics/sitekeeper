#!/usr/bin/env python3
"""Run only the host unit-conversion package and retain timing/hash evidence.

No source extraction, simulator, cleanup, signing or sandbox override is used.
"""
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_ROOT = ROOT / "build/unit-conversion-host"
INPUTS = [
    "Package.swift",
    "Sources/Shared/Helpers/EngineeringCalculations.swift",
    "Sources/Shared/Helpers/CalculationValidator.swift",
    "Tests/UnitConverterTests.swift",
    "HostTests/UnitConversion/UnitConversionContractTests.swift",
    "scripts/tests/run_unit_conversion_host_tests.py",
]
EXPECTED_TESTS = 9
EXPECTED_SUITES = {"UnitConverterTests": 5, "UnitConversionContractTests": 4}
EXPECTED_TEST_NAMES = {
    "meterToFeet", "feetToMeter", "muToSquareMeter", "tonToKg", "zeroValue",
    "unitConvertBasic", "unitConvertZero", "unitConvertInvalidFactor",
    "unitConvertValidatedRejectsInvalidFactor",
}


def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in INPUTS}


def test_evidence(text):
    # SwiftPM can execute each test target separately and emit one summary per
    # product. Require both suites and every named case, rather than taking the
    # final summary or trusting a total that could include repeated tests.
    counts = [int(value) for value in re.findall(r"Test run with (\d+) tests? (?:in .*? )?passed", text)]
    names = re.findall(r"\bTest ([A-Za-z_][A-Za-z_0-9]*)\(\) passed", text)
    suites = re.findall(r"\bSuite ([A-Za-z_][A-Za-z_0-9]*) passed", text)
    verified = (sorted(counts) == sorted(EXPECTED_SUITES.values())
                and len(names) == EXPECTED_TESTS and set(names) == EXPECTED_TEST_NAMES
                and len(suites) == len(EXPECTED_SUITES) and set(suites) == set(EXPECTED_SUITES))
    return {"passedTests": sum(counts) if counts else None, "summaryCounts": counts,
            "passedTestNames": names, "passedSuites": suites, "countVerified": verified}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="New directory below build/unit-conversion-host")
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (args.output or EVIDENCE_ROOT / (stamp + "-" + uuid.uuid4().hex[:8])).resolve()
    if not output.is_relative_to(EVIDENCE_ROOT.resolve()) or output == EVIDENCE_ROOT.resolve():
        parser.error("output must be a new child of build/unit-conversion-host")
    if output.exists():
        parser.error("output already exists; no files will be overwritten or deleted")
    swift = shutil.which("swift")
    if not swift:
        parser.error("swift is not available")
    before = hashes()
    output.mkdir(parents=True, exist_ok=False)
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(output / "clang-module-cache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(output / "swift-module-cache")
    command = [
        swift, "test", "--package-path", str(ROOT),
        "--scratch-path", str(output / "scratch"),
        "--cache-path", str(output / "cache"),
        "--config-path", str(output / "config"),
        "--security-path", str(output / "security"),
        "--disable-automatic-resolution",
    ]
    toolchain = subprocess.run([swift, "--version"], capture_output=True, text=True, check=True)
    receipt = {
        "startedAtUTC": datetime.now(timezone.utc).isoformat(),
        "swiftVersion": toolchain.stdout.strip(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "developerDirEnvironment": environment.get("DEVELOPER_DIR"),
        "command": command,
        "inputsBefore": before,
        "expectedTests": EXPECTED_TESTS,
        "coldDefinition": "New task scratch/cache/config/security/module-cache directories; OS and SDK caches may already be warm.",
        "timingDefinition": "perf_counter wall seconds for the full swift test subprocess, including planning/build/testing.",
        "runs": [],
        "scope": "Unit conversion only; other EngineeringCalculations functions are compiled but not validated by this package.",
    }
    receipt_path = output / "receipt.json"

    def save():
        receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")

    save()
    for phase in ["cold", "warm"]:
        if hashes() != before:
            receipt["stoppedReason"] = "Inputs changed before " + phase + "; not running a drifting candidate"
            break
        log = output / (phase + ".log")
        print("Running " + phase + "; log: " + str(log), flush=True)
        start = time.perf_counter()
        try:
            with log.open("w") as stream:
                result = subprocess.run(command, cwd=ROOT, env=environment, stdout=stream, stderr=subprocess.STDOUT)
            returncode = result.returncode
        except OSError as error:
            returncode = None
            receipt["stoppedReason"] = str(error)
        elapsed = time.perf_counter() - start
        text = log.read_text() if log.exists() else ""
        evidence = test_evidence(text)
        run = {"phase": phase, "wallSeconds": elapsed, "returncode": returncode,
               **evidence, "log": log.name,
               "logSHA256": hashlib.sha256(log.read_bytes()).hexdigest() if log.exists() else None,
               "success": returncode == 0 and evidence["countVerified"]}
        receipt["runs"].append(run)
        save()
        print(json.dumps(run, ensure_ascii=False), flush=True)
        if not run["success"]:
            receipt["stoppedReason"] = receipt.get("stoppedReason", "Test/build failed or expected count was not confirmed; no automatic retry")
            break
    receipt["inputsAfter"] = hashes()
    receipt["inputsUnchanged"] = receipt["inputsAfter"] == before
    receipt["success"] = (len(receipt["runs"]) == 2 and all(run["success"] for run in receipt["runs"])
                          and receipt["inputsUnchanged"])
    receipt["finishedAtUTC"] = datetime.now(timezone.utc).isoformat()
    save()
    print("Evidence: " + str(receipt_path), flush=True)
    return 0 if receipt["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
