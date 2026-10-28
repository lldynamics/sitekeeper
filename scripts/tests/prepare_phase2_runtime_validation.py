#!/usr/bin/env python3
"""Freeze source and isolate every app identity; never build, install, or launch."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

UTILITIES = Path(__file__).with_name("prepare_phase1_validation.py")
SPEC = importlib.util.spec_from_file_location("source_validation_utilities", UTILITIES)
helpers = importlib.util.module_from_spec(SPEC)
sys.dont_write_bytecode = True
SPEC.loader.exec_module(helpers)
PRODUCTION_ID = "com.chengjinfang.sitekeeper"
IDENTITY_FILES = (
    "project.yml", "Sources/Resources/sitekeeper.entitlements", "Widget/WidgetExtension.entitlements",
    "Sources/Shared/Services/Widgets/WidgetSharedModels.swift",
    "Sources/Shared/Services/Backups/Cloud/CloudBackupService.swift",
)


def install_thumbnail_fixture(output: Path, manifest: dict) -> None:
    """Add the opt-in UI surface only to the isolated application copy."""
    fixture = Path("scripts/tests/fixtures/Phase2ThumbnailValidationView.swift")
    target = Path("Sources/App/Phase2ThumbnailValidationView.swift")
    fixture_bytes = (output / fixture).read_bytes()
    if (output / target).exists():
        if (output / target).read_bytes() != fixture_bytes:
            raise RuntimeError("Existing validation fixture differs; review before preparing")
    else:
        (output / target).write_bytes(fixture_bytes)
        manifest["injected_files"] = {str(target): helpers.fingerprint(output / target)}
    app_path = Path("Sources/App/SitekeeperApp.swift")
    app = (output / app_path).read_text()
    anchor = "    private var rootContent: some View {\n        normalRootContent\n    }"
    replacement = """    private var rootContent: some View {
#if DEBUG && targetEnvironment(simulator)
        if Phase2ThumbnailValidationView.isRequested {
            Phase2ThumbnailValidationView()
        } else {
            normalRootContent
        }
#else
        normalRootContent
#endif
    }"""
    if app.count(anchor) != 1:
        raise RuntimeError("Review the current app root before injecting the validation fixture")
    helpers.transform(output, app_path, app.replace(anchor, replacement).encode(),
                      "Add synthetic UI fixture only to the isolated copy", manifest)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xcodegen", type=Path, required=True)
    parser.add_argument("--suffix", required=True)
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output.exists() or output == source or output in source.parents:
        parser.error("output must be a new directory, never an input or its ancestor")
    if source in output.parents and not helpers.is_excluded(output.relative_to(source)):
        parser.error("output inside source must be under build or another excluded directory")
    if not re.fullmatch(r"[a-z][a-z0-9-]{3,40}", args.suffix):
        parser.error("suffix must be 4-41 lowercase letters, digits or hyphens, starting with a letter")
    tool = args.xcodegen.resolve()
    if not tool.is_file() or not os.access(tool, os.X_OK):
        parser.error("xcodegen must be an executable file")
    identity = PRODUCTION_ID + ".validation.followup." + args.suffix
    names, selection = helpers.source_files(source)
    initial = {str(p): helpers.fingerprint(source / p) for p in names if (source / p).is_file()}
    output.mkdir(parents=True)
    manifest = {"schema": 1, "source": str(source), "output": str(output), "selection": selection,
                "copied_files": initial, "transformations": [], "identity": identity,
                "configuration": "optimized Debug with DEBUG and testability retained",
                "scope": "source preparation only; no device or application data access", "success": False}
    try:
        for name in initial:
            original, target = source / name, helpers.ensure_owned(output, Path(name))
            target.parent.mkdir(parents=True, exist_ok=True)
            if original.is_symlink():
                os.symlink(os.readlink(original), target)
            else:
                target.write_bytes(original.read_bytes())
                target.chmod(stat.S_IMODE(original.stat().st_mode))
            if helpers.fingerprint(target) != initial[name]:
                raise RuntimeError("Source changed during copy: " + name)
        install_thumbnail_fixture(output, manifest)
        for name in IDENTITY_FILES:
            text = (output / name).read_text()
            if PRODUCTION_ID not in text:
                raise RuntimeError("Missing expected identity in " + name)
            helpers.transform(output, Path(name), text.replace(PRODUCTION_ID, identity).encode(),
                              "Isolate app, extension, group and iCloud identities", manifest)
        spec = (output / "project.yml").read_text()
        if any(key + ":" in spec for key in ("SWIFT_OPTIMIZATION_LEVEL", "SWIFT_COMPILATION_MODE", "ENABLE_TESTABILITY")):
            raise RuntimeError("Review existing optimization/testability before overriding")
        spec, count = re.subn(r"(?m)^settings:\s*$", 'settings:\n  ENABLE_TESTABILITY: YES\n'
                              '  SWIFT_OPTIMIZATION_LEVEL: "-O"\n  SWIFT_COMPILATION_MODE: wholemodule', spec)
        if count != 1:
            raise RuntimeError("Expected one global settings block")
        # All test launches skip cloud/reminder automation through the existing
        # UITestLaunchConfig guard, including the app-hosted native test process.
        spec, count = re.subn(r"(?m)^(    test:)\s*$", r'\1\n      environmentVariables:\n'
                              r'        UITEST_VALIDATION_ISOLATED: "1"\n'
                              r'        SITEKEEPER_PHASE2_UI_FIXTURE: "1"', spec)
        if count != 2:
            raise RuntimeError("Expected the two existing test schemes")
        helpers.transform(output, Path("project.yml"), spec.encode(), "Explicit isolated validation build settings", manifest)
        command = [str(tool), "generate", "--spec", str(output / "project.yml")]
        with (output / "validation-xcodegen.log").open("w") as log:
            result = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT, check=False)
        if result.returncode:
            raise RuntimeError("XcodeGen failed: " + str(result.returncode))
        if any(helpers.fingerprint(source / p) != digest for p, digest in initial.items()):
            raise RuntimeError("Live source drifted while freezing")
        final_names, _ = helpers.source_files(output)
        manifest["candidate_files"] = {str(p): helpers.fingerprint(output / p) for p in final_names
                                       if (output / p).is_file()}
        manifest["xcodegen_sha256"] = helpers.sha(tool.read_bytes())
        manifest["success"] = True
    finally:
        (output / "isolated-validation-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"candidate": str(output), "identity": identity, "source_files": len(initial)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
