#!/usr/bin/env python3
"""Verify a signed FaceNow release, including the real sandboxed helper launch."""

import argparse
import base64
import json
import plistlib
import re
import subprocess
import importlib.util
from pathlib import Path
from urllib.parse import urlsplit


SPARKLE_VERSION = "2.10.1"


def pinned_sdk_version():
    """Read the SDK version from the selected local checkout or pinned release."""
    root = Path(__file__).resolve().parents[1]
    project = root / "FaceNow.xcodeproj"
    objects = json.loads(run("plutil", "-convert", "json", "-o", "-", str(project / "project.pbxproj")))["objects"]
    sdk_product = next(value for value in objects.values()
                       if value.get("isa") == "XCSwiftPackageProductDependency" and value.get("productName") == "XmaxSDK")
    package = objects[sdk_product["package"]]
    if package["isa"] == "XCLocalSwiftPackageReference":
        source = root / package["relativePath"] / "Sources/XmaxSDK/XmaxSDKInfo.swift"
        match = re.search(r'public\s+static\s+let\s+version\s*=\s*"([^"]+)"', source.read_text())
        assert match, f"The local SDK version is missing from {source}"
        return match.group(1)
    lockfile = project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    pins = json.loads(lockfile.read_text())["pins"]
    return next(pin["state"]["version"] for pin in pins if pin["identity"] == "xmaxsdk-macos")


def run(*arguments):
    return subprocess.check_output(arguments, stderr=subprocess.PIPE)


def entitlements(path):
    return plistlib.loads(run("codesign", "-d", "--entitlements", "-", "--xml", str(path)))


def diagnostic_json(output, required_fields):
    """Read the diagnostic payload even when SDK shutdown logs follow its JSON line."""
    for line in reversed(output.decode("utf-8", errors="replace").splitlines()):
        try:
            payload = json.loads(line)
        except ValueError:
            continue
        if isinstance(payload, dict) and set(required_fields).issubset(payload):
            return payload
    raise AssertionError("Diagnostic output is missing its required JSON payload")


def verify_update_configuration(info):
    """Allow intentionally disabled updates, but reject incomplete or insecure release settings."""
    feed = info.get("SUFeedURL", "")
    public_key = info.get("SUPublicEDKey", "")
    assert isinstance(feed, str) and isinstance(public_key, str)
    assert bool(feed) == bool(public_key), "Configure both the appcast URL and Ed25519 public key"
    assert info.get("SUEnableInstallerLauncherService") is True
    assert info.get("SUEnableDownloaderService") is False
    assert info.get("SUVerifyUpdateBeforeExtraction") is True
    if not feed:
        return False
    url = urlsplit(feed)
    assert feed.startswith("https://") and url.hostname and not url.fragment
    assert url.username is None and url.password is None
    assert "$(" not in feed and "$(" not in public_key
    assert len(base64.b64decode(public_key, validate=True)) == 32
    return True


def verify(app, expected_build, notarized):
    from device_identities import identity
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    edition = info["FaceNowEdition"]
    selected = identity(edition)
    microphone_script = Path(__file__).resolve().with_name("verify-virtual-microphone.py")
    spec = importlib.util.spec_from_file_location("verify_virtual_microphone", microphone_script)
    microphone_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(microphone_module)
    microphone_report = microphone_module.verify(app)
    extension = app / "Contents/Library/SystemExtensions" / (selected["extensionBundleID"] + ".systemextension")
    helper = app / "Contents/Helpers" / ("FaceNowOverseaCameraProbe" if edition == "oversea" else "FaceNowCameraProbe")
    beauty_service = app / "Contents/XPCServices/XmaxRealtimeBeautyWorker.xpc"
    beauty_binary = beauty_service / "Contents/MacOS/XmaxRealtimeBeautyWorker"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    extension_info = plistlib.loads((extension / "Contents/Info.plist").read_bytes())
    assert info["CFBundleVersion"] == expected_build
    assert extension_info["CFBundleVersion"] == expected_build
    assert info["LSMinimumSystemVersion"] == "13.0"
    assert not info.get("FaceNowDiagnoseCameraActivation", False)
    updates_configured = verify_update_configuration(info)

    sparkle = app / "Contents/Frameworks/Sparkle.framework"
    sparkle_root = sparkle / "Versions/B"
    sparkle_info = plistlib.loads((sparkle_root / "Resources/Info.plist").read_bytes())
    assert sparkle_info["CFBundleShortVersionString"] == SPARKLE_VERSION
    updater = sparkle_root / "Updater.app"
    installer = sparkle_root / "XPCServices/Installer.xpc"
    downloader = sparkle_root / "XPCServices/Downloader.xpc"
    update_binaries = [sparkle_root / "Sparkle", sparkle_root / "Autoupdate",
                       updater / "Contents/MacOS/Updater", installer / "Contents/MacOS/Installer",
                       downloader / "Contents/MacOS/Downloader"]

    binaries = [app / "Contents/MacOS" / info["CFBundleExecutable"], extension / "Contents/MacOS" / extension_info["CFBundleExecutable"], helper]
    for binary in binaries + update_binaries + [beauty_binary]:
        assert set(run("lipo", "-archs", str(binary)).decode().split()) == {"arm64", "x86_64"}
    for signed in [app, extension, helper, beauty_service, sparkle, sparkle_root / "Autoupdate", updater, installer, downloader]:
        run("codesign", "--verify", "--deep", "--strict", str(signed))
        signature = subprocess.run(["codesign", "-dv", str(signed)], capture_output=True, check=True)
        assert b"TeamIdentifier=A84PZNYY82" in signature.stderr

    helper_entitlements = entitlements(helper)
    sandbox_keys = {key: value for key, value in helper_entitlements.items() if key.startswith("com.apple.security.")}
    assert sandbox_keys == {"com.apple.security.app-sandbox": True, "com.apple.security.inherit": True}, sandbox_keys
    beauty_entitlements = entitlements(beauty_service)
    assert beauty_entitlements["com.apple.security.app-sandbox"] is True
    assert not beauty_entitlements.get("com.apple.security.inherit", False)
    assert not beauty_entitlements.get("com.apple.security.device.camera", False)
    assert not beauty_entitlements.get("com.apple.security.device.audio-input", False)
    assert not beauty_entitlements.get("com.apple.security.get-task-allow", False)
    for bundle in [app, extension]:
        signed_entitlements = entitlements(bundle)
        assert signed_entitlements["com.apple.security.app-sandbox"] is True
        assert not signed_entitlements.get("com.apple.security.inherit", False)
    app_entitlements = entitlements(app)
    update_services = app_entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name", [])
    assert {f"{info['CFBundleIdentifier']}-spks", f"{info['CFBundleIdentifier']}-spki"}.issubset(update_services)
    linked = run("otool", "-L", str(helper)).decode()
    assert "Agora" not in linked and "XmaxSDK" not in linked and "Sparkle" not in linked
    assert "Sparkle" not in run("otool", "-L", str(binaries[1])).decode()

    sdk_version = pinned_sdk_version()
    samples = []
    for _ in range(3):
        completed = subprocess.run([str(binaries[0]), "--verify-camera-probe"], capture_output=True, timeout=15, check=True)
        sample = diagnostic_json(completed.stdout, ["sdkVersion", "hostProcessID", "helper"])
        assert sample["sdkVersion"] == sdk_version, sample
        assert sample["hostProcessID"] != sample["helper"]["processID"]
        samples.append(sample)
    assert len({sample["helper"]["processID"] for sample in samples}) == len(samples)
    beauty_result = subprocess.run([str(binaries[0]), "--verify-video-beauty"], capture_output=True, timeout=25, check=True)
    beauty_sample = diagnostic_json(beauty_result.stdout, [
        "hostProcessID", "helperProcessID", "pixelProcessingVerified", "timingPreserved",
        "sharedBufferOwnershipVerified", "rtcCoexistenceVerified",
    ])
    assert beauty_sample["hostProcessID"] != beauty_sample["helperProcessID"]
    for field in ["pixelProcessingVerified", "timingPreserved", "sharedBufferOwnershipVerified", "rtcCoexistenceVerified"]:
        assert beauty_sample[field] is True, beauty_sample

    if notarized:
        run("xcrun", "stapler", "validate", str(app))
        run("spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
    return {**microphone_report, "app": str(app), "build": expected_build, "sdkVersion": sdk_version, "universalBinariesVerified": True,
            "signaturesVerified": True, "sandboxInheritanceVerified": True, "signedProbeLaunches": samples,
            "signedBeautyServiceVerified": beauty_sample,
            "sparkleVersion": SPARKLE_VERSION, "automaticUpdatesConfigured": updates_configured,
            "notarizationVerified": notarized}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--build", required=True)
    parser.add_argument("--notarized", action="store_true")
    parser.add_argument("--report", type=Path)
    arguments = parser.parse_args()
    result = verify(arguments.app.resolve(), arguments.build, arguments.notarized)
    report = json.dumps(result, indent=2) + "\n"
    if arguments.report:
        arguments.report.write_text(report)
    print(report, end="")
