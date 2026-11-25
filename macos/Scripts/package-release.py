#!/usr/bin/env python3
"""Package an already-notarized FaceNow app and verify the mounted disk image."""

import argparse
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path


def run(*arguments):
    subprocess.run(arguments, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--build", required=True)
    parser.add_argument("--output-directory", type=Path,
                        help="Override the default .build/releases/<version>-<build>/<edition> directory.")
    parser.add_argument("--signing-identity", required=True)
    arguments = parser.parse_args()
    app = arguments.app.resolve()
    output = arguments.output_directory
    if output is None:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        edition = {"domestic": "mainland", "oversea": "overseas"}.get(info.get("FaceNowEdition"))
        if edition is None:
            parser.error("The application has an unknown FaceNow edition.")
        release = f"{info.get('CFBundleShortVersionString')}-{arguments.build}"
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*-[0-9]+(?:\.[0-9]+)*", release):
            parser.error("The application version and build number must be numeric.")
        output = Path(__file__).resolve().parents[1] / ".build" / "releases" / release / edition
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    dmg = output / "FaceNow.dmg"
    assert not dmg.exists(), "Refusing to overwrite an existing release"
    verifier = Path(__file__).with_name("verify-release.py")
    report = output / "package-verification.json"
    run("python3", str(verifier), str(app), "--build", arguments.build, "--notarized", "--report", str(report))
    with tempfile.TemporaryDirectory(prefix="DiskImage-", dir=output) as staging:
        stage = Path(staging)
        run("ditto", str(app), str(stage / app.name))
        (stage / "Applications").symlink_to("/Applications")
        run("hdiutil", "create", "-volname", "FaceNow", "-srcfolder", str(stage), "-format", "UDZO", str(dmg))
    run("codesign", "--sign", arguments.signing_identity, "--timestamp", str(dmg))
    run("codesign", "--verify", "--strict", str(dmg))
    run("hdiutil", "verify", str(dmg))
    with tempfile.TemporaryDirectory(prefix="FaceNow-mounted-", dir="/private/tmp") as mountpoint:
        mount = Path(mountpoint)
        run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg))
        try:
            assert (mount / "Applications").is_symlink()
            run("python3", str(verifier), str(mount / app.name), "--build", arguments.build,
                "--notarized", "--report", str(output / "mounted-verification.json"))
        finally:
            run("hdiutil", "detach", str(mount))
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (output / "FaceNow.dmg.sha256").write_text(digest + "  FaceNow.dmg\n")
    result = json.loads(report.read_text())
    result.update(dmg=str(dmg), sha256=digest, sizeBytes=dmg.stat().st_size, mountedDMGVerified=True)
    report.write_text(json.dumps(result, indent=2) + "\n")
    print("Verified release:", dmg)
