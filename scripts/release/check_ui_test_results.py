#!/usr/bin/env python3
"""Require a successful UI test result with no recorded runtime warnings."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys


class ResultValidationError(ValueError):
    """The result is unsuccessful or cannot be checked safely."""


def load_summary(result_bundle: str) -> object:
    command = [
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", result_bundle,
    ]
    try:
        result = subprocess.run(
            command, check=True, capture_output=True, text=True, timeout=60
        )
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        raise ResultValidationError(
            f"xcresulttool failed (exit {error.returncode}): {detail}"
        ) from error
    except subprocess.TimeoutExpired as error:
        raise ResultValidationError("xcresulttool timed out after 60 seconds") from error
    except OSError as error:
        raise ResultValidationError(f"cannot execute xcresulttool: {error}") from error

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ResultValidationError(f"xcresulttool returned invalid JSON: {error}") from error


def validate_summary(summary: object) -> None:
    if not isinstance(summary, dict):
        raise ResultValidationError("test summary must be a JSON object")

    required_types = {
        "result": str,
        "totalTestCount": int,
        "passedTests": int,
        "failedTests": int,
        "skippedTests": int,
        "expectedFailures": int,
        "testFailures": list,
        "runtimeWarnings": list,
    }
    for field, expected_type in required_types.items():
        if field not in summary or type(summary[field]) is not expected_type:
            raise ResultValidationError(f"missing or invalid summary field: {field}")
        if expected_type is int and summary[field] < 0:
            raise ResultValidationError(f"negative test count: {field}")

    errors = []
    if summary["result"] != "Passed":
        errors.append(f"test result is {summary['result']!r}, expected 'Passed'")
    if summary["failedTests"] or summary["testFailures"]:
        errors.append("test summary contains failures")
    if summary["skippedTests"] or summary["expectedFailures"]:
        errors.append("all selected tests must execute and pass without expected failures")
    if summary["totalTestCount"] != summary["passedTests"]:
        errors.append("not all selected tests passed")
    if summary["totalTestCount"] == 0 or summary["passedTests"] == 0:
        errors.append("no UI tests passed")
    for warning in summary["runtimeWarnings"]:
        if not isinstance(warning, dict) or any(
            not isinstance(warning.get(field), str)
            for field in ("issueType", "message")
        ):
            raise ResultValidationError("invalid runtimeWarnings entry")
        errors.append(f"{warning['issueType']}: {warning['message']}")
    if errors:
        raise ResultValidationError("\n".join(errors))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result-bundle", required=True, help="Path to the UI test .xcresult bundle")
    arguments = parser.parse_args(argv)
    try:
        summary = load_summary(arguments.result_bundle)
        validate_summary(summary)
    except ResultValidationError as error:
        print(f"[ui-test-results] FAIL: {error}", file=sys.stderr)
        print(f"Result bundle: {arguments.result_bundle}", file=sys.stderr)
        return 1
    print(f"[ui-test-results] PASS: {summary['passedTests']} tests passed; no runtime warnings.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
