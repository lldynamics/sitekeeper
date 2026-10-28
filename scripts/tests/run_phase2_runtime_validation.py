#!/usr/bin/env python3
"""Run the bounded synthetic validation plan under the shared simulator wrapper."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time

IPHONE = "973C5D68-8743-4DDB-A2C1-5E6E54397141"
PLAN = (
    ("import", "sitekeeperTests", 4, ("BackupWorkflowIntegrationTests",)),
    ("journal", "sitekeeperTests", 2, (
        "BackupRestoreJournalTests/restartRollsBackEachPreMetadataInterruption()",
        "BackupRestoreJournalTests/restartFinalizesCommittedMetadataWithoutRollingBackAttachments()",
    )),
    ("thumbnail", "sitekeeperTests", 6, ("ThumbnailRuntimeValidationTests",)),
    ("ui", "sitekeeperUITests", 4, (
        "SitekeeperUITests/testPhase2ThumbnailsRefreshAfterSameNameReplacement",
        "SitekeeperUITests/testPhase2ThumbnailsSurviveMemoryWarningResizeAndReappearance",
        "SitekeeperUITests/testLocalBackupRoundTripRestoresClearedProjectAfterRestart",
        "SitekeeperUITests/testBackupOverwriteImportShowsSecondConfirmation",
    )),
)


def require_lock() -> None:
    if os.environ.get("CODEX_SIM_POOL", "primary") != "primary":
        raise RuntimeError("This plan requires the ordinary primary pool")
    if os.environ.get("CODEX_SIM_IPHONE_UDID") != IPHONE:
        raise RuntimeError("Run through scripts/release/run_shared_simulator.sh")
    fd = int(os.environ.get("CODEX_SIM_SESSION_FD", "-1"))
    held = os.fstat(fd)
    expected = (Path.home() / "Library/Caches/CodexSimulatorPool/session.lock").stat()
    if (held.st_dev, held.st_ino) != (expected.st_dev, expected.st_ino):
        raise RuntimeError("The inherited descriptor is not the shared pool lock")


def verify_inputs(candidate: Path, products: Path) -> tuple[str, dict]:
    manifest = json.loads((candidate / "isolated-validation-manifest.json").read_text())
    identity = manifest["identity"]
    if not manifest["success"] or not identity.startswith("com.chengjinfang.sitekeeper.validation.followup."):
        raise RuntimeError("A successful isolated candidate is required")
    for name, expected in manifest["candidate_files"].items():
        path = candidate / name
        data = os.fsencode(os.readlink(path)) if expected["kind"] == "symlink" else path.read_bytes()
        if hashlib.sha256(data).hexdigest() != expected["sha256"]:
            raise RuntimeError("Frozen source changed: " + name)
    info = plistlib.loads((products / "Debug-iphonesimulator/工地掌柜.app/Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != identity:
        raise RuntimeError("Built app identity does not match the isolated source")
    runs = {}
    for scheme, target in (("sitekeeper-iOS", "sitekeeperTests"), ("sitekeeper-iOS-UITests", "sitekeeperUITests")):
        matches = list(products.glob(scheme + "_*.xctestrun"))
        if len(matches) != 1:
            raise RuntimeError("Expected one xctestrun file for " + scheme)
        config = plistlib.loads(matches[0].read_bytes())[target]
        if not config["TestHostBundleIdentifier"].startswith(identity):
            raise RuntimeError("Test host is not isolated")
        environment = config["EnvironmentVariables"]
        if environment.get("UITEST_VALIDATION_ISOLATED") != "1":
            raise RuntimeError("Isolated test launch guard missing")
        if target == "sitekeeperUITests" and environment.get("SITEKEEPER_PHASE2_UI_FIXTURE") != "1":
            raise RuntimeError("Synthetic UI fixture opt-in missing")
        runs[target] = matches[0]
    return identity, runs


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--execute", action="store_true", help="Otherwise verify inputs and print the plan without using devices")
    parser.add_argument("--groups", nargs="+", choices=[item[0] for item in PLAN], help="Resume only unaccepted groups")
    parser.add_argument("--timeout-seconds", type=int, default=600, help="Per-group limit before normal cancellation")
    args = parser.parse_args()
    if not 30 <= args.timeout_seconds <= 900:
        parser.error("--timeout-seconds must be between 30 and 900")
    plan = [item for item in PLAN if not args.groups or item[0] in args.groups]
    candidate, products = args.candidate.resolve(), args.products.resolve()
    identity, runs = verify_inputs(candidate, products)
    if not args.execute:
        print(json.dumps({"identity": identity, "device": IPHONE, "executed": False,
                          "plan": plan}, ensure_ascii=False, indent=2))
        return
    require_lock()
    if args.output is None:
        parser.error("--output is required with --execute")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    results = []
    for name, target, count, selectors in plan:
        result_path = output / (name + ".xcresult")
        command = ["xcodebuild", "test-without-building", "-xctestrun", str(runs[target]),
                   "-destination", "platform=iOS Simulator,id=" + IPHONE,
                   "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                   "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "180" if name == "ui" else "120",
                   "-maximum-test-execution-time-allowance", "180", "-destination-timeout", "30",
                   "-resultBundlePath", str(result_path)]
        command += ["-only-testing:" + target + "/" + selector for selector in selectors]
        started = time.monotonic()
        timed_out = False
        with (output / (name + ".log")).open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            (output / "active-process.json").write_text(json.dumps({"group": name, "pid": process.pid,
                "command": command, "timeout_seconds": args.timeout_seconds}, indent=2))
            print(json.dumps({"group": name, "pid": process.pid, "state": "started"}), flush=True)
            try:
                status = process.wait(timeout=args.timeout_seconds)
            except subprocess.TimeoutExpired:
                timed_out = True
                process.send_signal(signal.SIGINT)
                try:
                    status = process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    # Keep this process and its inherited pool lock alive while
                    # the supervising thread inspects the exact owned child.
                    print(json.dumps({"group": name, "pid": process.pid,
                        "state": "normal cancellation pending; shared lock retained"}), flush=True)
                    status = process.wait()
        row = {"name": name, "command": command, "exit_code": status, "expected_count": count,
               "identity": identity, "source_manifest_sha256": hashlib.sha256(
                   (candidate / "isolated-validation-manifest.json").read_bytes()).hexdigest()}
        row.update(elapsed_seconds=round(time.monotonic() - started, 3), timed_out=timed_out)
        results.append(row)
        try:
            summary = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                      "--path", str(result_path)], capture_output=True, text=True, check=True, timeout=60)
            row["summary"] = json.loads(summary.stdout)
            data = row["summary"]
            if (timed_out or status != 0 or data["result"] != "Passed" or data["totalTestCount"] != count
                    or data["passedTests"] != count or data["failedTests"] != 0
                    or data["skippedTests"] != 0 or data["expectedFailures"] != 0
                    or data["testFailures"] or data["runtimeWarnings"]):
                raise RuntimeError("Selected tests did not all pass cleanly: " + name)
        finally:
            (output / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"executed": True, "passed": sum(item[2] for item in plan), "results": str(output)}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
