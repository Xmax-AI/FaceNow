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


def verify_clearvision(bundle):
    contents = bundle / "Contents"
    worker = contents / "MacOS/XmaxRealtimeBeautyWorker"
    clearvision = contents / "Frameworks/AgoraClearVisionExtension.framework/Versions/A/AgoraClearVisionExtension"
    if not clearvision.is_file():
        raise RuntimeError(f"Missing ClearVision executable in the beauty service: {clearvision}")

    worker_architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(worker)], text=True).split()
    framework_architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(clearvision)], text=True).split()
    for architecture in worker_architectures:
        if architecture not in framework_architectures:
            raise RuntimeError(f"ClearVision is missing the beauty service's {architecture} architecture")
        commands = subprocess.check_output(["/usr/bin/otool", "-arch", architecture, "-l", str(worker)], text=True)
        if not any(
            "cmd LC_RPATH" in command
            and any(line.strip().startswith("path @executable_path/../Frameworks (offset ") for line in command.splitlines())
            for command in commands.split("Load command ")
        ):
            raise RuntimeError(
                f"The {architecture} beauty service must include @executable_path/../Frameworks in its runpaths"
            )


def main():
    source = Path(os.environ["FACENOW_SHARED_PRODUCTS_DIR"]) / "XmaxRealtimeBeautyWorker.xpc"
    destination = (
        Path(os.environ["TARGET_BUILD_DIR"])
        / os.environ["CONTENTS_FOLDER_PATH"]
        / "XPCServices/XmaxRealtimeBeautyWorker.xpc"
    )
    if source.resolve() == destination.resolve():
        raise RuntimeError("The beauty service source and destination must differ")
    verify_clearvision(source)
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
    print("Embedded beauty service and verified ClearVision packaging")


if __name__ == "__main__":
    main()
