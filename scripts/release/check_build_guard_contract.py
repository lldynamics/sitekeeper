#!/usr/bin/env python3
"""Verify that the actual Xcode build phase stops on any failed guard."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    project = (root / "project.yml").read_text(encoding="utf-8")
    match = re.search(r"        script: \|\n((?:          [^\n]*\n)+)", project)
    if not match:
        raise SystemExit("[build-guard-contract] FAIL: cannot find the build guard phase")
    phase = textwrap.dedent(match.group(1))
    names = re.findall(r'\$\{SRCROOT\}/(scripts/release/check_[^"\n]+\.sh)', phase)
    if not names or len(names) != len(set(names)):
        raise SystemExit("[build-guard-contract] FAIL: missing or repeated guards")

    with tempfile.TemporaryDirectory(prefix="sitekeeper-guard-contract-") as directory:
        sandbox = Path(directory)
        for name in names:
            path = sandbox / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                '#!/bin/sh\n[ "$0" != "$FAILING_GUARD" ]\n', encoding="utf-8"
            )
            path.chmod(0o700)
        for failing in [None, *names]:
            environment = dict(os.environ, SRCROOT=directory)
            environment["FAILING_GUARD"] = str(sandbox / failing) if failing else ""
            result = subprocess.run(["/bin/sh", "-c", phase], env=environment, check=False)
            if (result.returncode == 0) != (failing is None):
                raise SystemExit(f"[build-guard-contract] FAIL: incorrect exit for {failing}")
    print(f"[build-guard-contract] PASS: all {len(names)} failures propagate")


if __name__ == "__main__":
    main()
