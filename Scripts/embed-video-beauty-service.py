#!/usr/bin/env python3
"""Embed the signed XPC product without retaining an incremental build's old signature."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess


def entitlements(bundle):
    result = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(bundle)],
        check=True,
        capture_output=True,
    )
    return plistlib.loads(result.stdout)


def main():
    source = Path(os.environ["BUILT_PRODUCTS_DIR"]) / "XmaxVideoBeautyWorker.xpc"
    destination = (
        Path(os.environ["TARGET_BUILD_DIR"])
        / os.environ["CONTENTS_FOLDER_PATH"]
        / "XPCServices/XmaxVideoBeautyWorker.xpc"
    )
    if source.resolve() == destination.resolve():
        raise RuntimeError("The beauty service source and destination must differ")
    signed = os.environ.get("CODE_SIGNING_ALLOWED", "YES") != "NO"
    if signed:
        expected = entitlements(source)
        if bool(expected.get("com.apple.security.get-task-allow")) != (os.environ["CONFIGURATION"] == "Debug"):
            raise RuntimeError("The beauty service's debug attach entitlement does not match its configuration")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # codesign can preserve executable modification times. Replace the complete bundle,
    # including its signature, instead of letting an incremental copy compare timestamps.
    if destination.exists():
        shutil.rmtree(destination)
    subprocess.run(["/usr/bin/ditto", str(source), str(destination)], check=True)
    if signed:
        if entitlements(destination) != expected:
            raise RuntimeError("The embedded beauty service lost its signing entitlements")
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(destination)], check=True)
    print("Embedded beauty service with matching signature and configuration entitlements")


if __name__ == "__main__":
    main()
