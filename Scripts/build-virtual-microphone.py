#!/usr/bin/env python3
"""Builds an offline, signed HAL loopback driver and an opt-in system installer."""
import os
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from device_identities import identity as device_identity, source_digest, uninstall_script, compiler_definitions

source = Path(os.environ['SRCROOT'])
edition = os.environ['FACENOW_EDITION']
selected = device_identity(edition)
resources = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']
resources.mkdir(parents=True, exist_ok=True)
prepared = os.environ.get('FACENOW_AUDIO_INSTALLERS_DIRECTORY')
if prepared:
    # Stapled packages must be preserved byte-for-byte before Xcode signs the enclosing app.
    for name in ['FaceNowMicrophone.pkg', 'FaceNowMicrophoneUninstall.pkg']:
        shutil.copy2(Path(prepared) / name, resources / name)
    spec = importlib.util.spec_from_file_location('audio_verify', source / 'Scripts/verify-virtual-microphone.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.verify(Path(os.environ['TARGET_BUILD_DIR']) / os.environ['WRAPPER_NAME'], edition=edition)
    raise SystemExit(0)
identity = os.environ.get('FACENOW_AUDIO_DRIVER_SIGNING_IDENTITY') or os.environ.get('EXPANDED_CODE_SIGN_IDENTITY', '-')
release = os.environ.get('CONFIGURATION') == 'Release'
installer_identity = os.environ.get('FACENOW_AUDIO_INSTALLER_SIGNING_IDENTITY', '')
if release and not installer_identity:
    raise SystemExit('Release requires FACENOW_AUDIO_INSTALLER_SIGNING_IDENTITY (Developer ID Installer certificate).')
if release and not os.environ.get('FACENOW_AUDIO_DRIVER_SIGNING_IDENTITY'):
    raise SystemExit('Release requires FACENOW_AUDIO_DRIVER_SIGNING_IDENTITY (Developer ID Application certificate).')

def run(args):
    subprocess.run([str(x) for x in args], check=True)

with tempfile.TemporaryDirectory(prefix='FaceNowAudio-', dir=os.environ['TEMP_DIR']) as directory:
    work = Path(directory)
    driver = work / 'payload/Library/Audio/Plug-Ins/HAL' / selected['driverFilename']
    (driver / 'Contents/MacOS').mkdir(parents=True)
    info = plistlib.loads((source / 'VirtualMicrophoneDriver/Info.plist').read_bytes())
    info['CFBundleIdentifier'] = selected['driverBundleID']
    info['CFBundleName'] = selected['microphoneName']
    info['CFPlugInFactories'] = {selected['factoryUUID']: selected['factoryFunction']}
    info['CFPlugInTypes'] = {'443ABAB8-E7B3-491A-B985-BEB9187030DB': [selected['factoryUUID']]}
    info['FaceNowAudioEdition'] = edition
    info['FaceNowAudioSourceDigest'] = source_digest(edition)
    info['FaceNowMicrophoneUID'] = selected['microphoneUID']
    info['FaceNowWriterUID'] = selected['writerUID']
    info['FaceNowMicrophoneName'] = selected['microphoneName']
    info['FaceNowSpeakerName'] = selected['speakerName']
    (driver / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copytree(source / 'VirtualMicrophoneDriver/en.lproj', driver / 'Contents/Resources/en.lproj')
    shutil.copy2(source / 'VirtualMicrophoneDriver/LICENSE-Apple.txt', driver / 'Contents/Resources/LICENSE-Apple.txt')
    architectures = os.environ.get('ARCHS', 'arm64 x86_64').split()
    args = ['xcrun', 'clang', '-std=c11', '-O2', '-fblocks', '-mmacosx-version-min=13.0', '-bundle']
    for arch in architectures:
        args += ['-arch', arch]
    run(args + compiler_definitions(edition) + ['-I', source / 'Services/Media/Audio', source / 'VirtualMicrophoneDriver/FaceNowMicrophone.c',
                source / 'Services/Media/Audio/AudioTimelineBuffer.c', '-framework', 'CoreAudio', '-framework', 'CoreFoundation',
                '-framework', 'AudioUnit', '-o', driver / 'Contents/MacOS/FaceNowMicrophone'])
    run(['codesign', '--force', '--timestamp' if release else '--timestamp=none', '--options', 'runtime', '--sign', identity, driver])
    run(['codesign', '--verify', '--strict', driver])
    components = work / 'components.plist'
    run(['pkgbuild', '--analyze', '--root', work / 'payload', components])
    component_info = plistlib.loads(components.read_bytes())
    for component in component_info:
        component['BundleIsRelocatable'] = False
        component['BundleHasStrictIdentifier'] = True
        component['BundleIsVersionChecked'] = False
    components.write_bytes(plistlib.dumps(component_info))
    pkg = resources / 'FaceNowMicrophone.pkg'
    pkg.unlink(missing_ok=True)
    args = ['pkgbuild', '--root', work / 'payload', '--identifier', selected['installerID'],
            '--version', info['CFBundleShortVersionString'], '--install-location', '/', '--ownership', 'recommended', '--component-plist', components]
    # No postinstall script: installing must never restart system audio or terminate calls.
    if installer_identity:
        args += ['--sign', installer_identity]
    run(args + [pkg])
    print('Virtual microphone installer:', pkg, '(signed)' if installer_identity else '(local Debug package, unsigned installer)')
    uninstall_scripts = work / 'uninstall-scripts'
    uninstall_scripts.mkdir()
    postinstall = uninstall_scripts / 'postinstall'
    postinstall.write_text(uninstall_script(edition))
    postinstall.chmod(0o755)
    uninstall_pkg = resources / 'FaceNowMicrophoneUninstall.pkg'
    uninstall_pkg.unlink(missing_ok=True)
    args = ['pkgbuild', '--nopayload', '--scripts', uninstall_scripts,
            '--identifier', selected['uninstallerID'], '--version', '1.0.0']
    if installer_identity:
        args += ['--sign', installer_identity]
    run(args + [uninstall_pkg])
