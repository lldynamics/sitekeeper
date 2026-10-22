import contextlib
import io
import json
import subprocess
import unittest
from unittest.mock import patch

import check_ui_test_results as checker


def passed_summary():
    return {
        "result": "Passed",
        "totalTestCount": 1,
        "passedTests": 1,
        "failedTests": 0,
        "skippedTests": 0,
        "expectedFailures": 0,
        "testFailures": [],
        "runtimeWarnings": [],
    }


class UITestResultTests(unittest.TestCase):
    def test_successful_tests_without_warnings_pass(self):
        checker.validate_summary(passed_summary())

    def test_failed_or_empty_test_runs_fail(self):
        for change in (
            {"result": "Failed"},
            {"skippedTests": 1},
            {"expectedFailures": 1},
            {"totalTestCount": 2},
            {"failedTests": 1},
            {"testFailures": [{"failureText": "assertion failed"}]},
            {"totalTestCount": 0, "passedTests": 0},
            {"passedTests": 0, "skippedTests": 1},
        ):
            with self.subTest(change=change), self.assertRaises(checker.ResultValidationError):
                checker.validate_summary(passed_summary() | change)

    def test_runtime_warnings_fail_even_when_xctest_passed(self):
        for message in (
            "Invalid frame dimension (negative or non-finite).",
            "Publishing changes from background threads is not allowed.",
        ):
            summary = passed_summary()
            summary["runtimeWarnings"] = [{"issueType": "Runtime Warning", "message": message}]
            with self.subTest(message=message), self.assertRaisesRegex(
                checker.ResultValidationError, "Runtime Warning:"
            ):
                checker.validate_summary(summary)

    def test_missing_fields_cannot_silently_pass(self):
        for field in passed_summary():
            summary = passed_summary()
            del summary[field]
            with self.subTest(field=field), self.assertRaisesRegex(
                checker.ResultValidationError, field
            ):
                checker.validate_summary(summary)

    def test_quicklook_appintents_warning_is_rejected_without_an_exception(self):
        summary = passed_summary()
        summary["runtimeWarnings"] = [{
            "issueType": "Runtime Warning",
            "message": 'Programming error: a caseDisplayRepresentations entry for AppEnum case "to-0.0" was not found. This case will be ignored.',
        }]
        with self.assertRaisesRegex(checker.ResultValidationError, "caseDisplayRepresentations"):
            checker.validate_summary(summary)

    def test_bad_summary_types_and_warning_entries_fail(self):
        invalid_summaries = [None, [], "Passed"]
        invalid_summaries.extend(passed_summary() | change for change in (
            {"passedTests": True},
            {"failedTests": -1},
            {"runtimeWarnings": None},
            {"runtimeWarnings": ["Invalid frame dimension"]},
            {"runtimeWarnings": [{"issueType": "Runtime Warning"}]},
            {"runtimeWarnings": [{"issueType": "Runtime Warning", "message": None}]},
        ))
        for summary in invalid_summaries:
            with self.subTest(summary=summary), self.assertRaises(checker.ResultValidationError):
                checker.validate_summary(summary)

    def test_cli_reads_xcresult_summary_and_reports_success(self):
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(passed_summary()))
        with patch.object(checker.subprocess, "run", return_value=result) as run:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(checker.main(["--result-bundle", "/tmp/UI result.xcresult"]), 0)
        run.assert_called_once_with(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", "/tmp/UI result.xcresult"],
            check=True, capture_output=True, text=True, timeout=60,
        )
        self.assertIn("PASS", output.getvalue())

    def test_cli_runtime_warning_returns_failure_and_keeps_bundle_path(self):
        summary = passed_summary()
        summary["runtimeWarnings"] = [{
            "issueType": "Runtime Warning",
            "message": "Invalid frame dimension (negative or non-finite).",
        }]
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(summary))
        with patch.object(checker.subprocess, "run", return_value=result):
            output = io.StringIO()
            with contextlib.redirect_stderr(output):
                self.assertEqual(checker.main(["--result-bundle", "/tmp/UI.xcresult"]), 1)
        self.assertIn("Invalid frame dimension", output.getvalue())
        self.assertIn("/tmp/UI.xcresult", output.getvalue())

    def test_cli_tool_errors_fail_closed(self):
        for error in (
            subprocess.CalledProcessError(64, ["xcrun"], stderr="unsupported schema"),
            subprocess.TimeoutExpired(["xcrun"], 60),
            FileNotFoundError("xcrun not found"),
        ):
            with self.subTest(error=error), patch.object(checker.subprocess, "run", side_effect=error):
                output = io.StringIO()
                with contextlib.redirect_stderr(output):
                    self.assertEqual(checker.main(["--result-bundle", "/tmp/UI.xcresult"]), 1)
                self.assertIn("FAIL", output.getvalue())

    def test_cli_bad_json_fails_closed(self):
        for text in ("", "{", "xcodebuild succeeded"):
            result = subprocess.CompletedProcess([], 0, stdout=text)
            with self.subTest(text=text), patch.object(checker.subprocess, "run", return_value=result):
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(checker.main(["--result-bundle", "/tmp/UI.xcresult"]), 1)


if __name__ == "__main__":
    unittest.main()
