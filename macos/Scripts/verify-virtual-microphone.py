#!/usr/bin/env python3
"""Inspects audio installers without installing them or restarting system audio."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from device_identities import identity, source_digest, uninstall_script


def verify(app, development=False, edition=None):
    if edition is None:
        edition = plistlib.loads((app / "Contents/Info.plist").read_bytes())["FaceNowEdition"]
    selected = identity(edition)
    source = Path(__file__).resolve().parent.parent
    driver_package = app / 'Contents/Resources/FaceNowMicrophone.pkg'
    uninstall_package = app / 'Contents/Resources/FaceNowMicrophoneUninstall.pkg'
    for package in [driver_package, uninstall_package]:
        assert package.is_file(), package
        if not development:
            signature = subprocess.check_output(['pkgutil', '--check-signature', str(package)])
            assert b'Developer ID Installer:' in signature and b'A84PZNYY82' in signature
            subprocess.run(['xcrun', 'stapler', 'validate', str(package)], check=True, capture_output=True)
            subprocess.run(['spctl', '--assess', '--type', 'install', str(package)], check=True, capture_output=True)
    with tempfile.TemporaryDirectory(prefix='FaceNowAudioVerify-') as directory:
        root = Path(directory)
        for package, name in [(driver_package, 'install'), (uninstall_package, 'uninstall')]:
            subprocess.run(['pkgutil', '--expand-full', str(package), str(root / name)], check=True, capture_output=True)
        drivers = list((root / 'install').rglob(selected['driverFilename']))
        assert len(drivers) == 1
        driver = drivers[0]
        info = plistlib.loads((driver / 'Contents/Info.plist').read_bytes())
        assert info['CFBundleIdentifier'] == selected['driverBundleID']
        assert info.get('FaceNowAudioSourceDigest') == source_digest(edition), 'Audio package was built from different driver source or edition'
        assert info['FaceNowAudioEdition'] == edition
        assert info['FaceNowMicrophoneUID'] == selected['microphoneUID']
        assert info['FaceNowWriterUID'] == selected['writerUID']
        assert info['FaceNowMicrophoneName'] == selected['microphoneName']
        assert info['FaceNowSpeakerName'] == selected['speakerName']
        assert info['CFPlugInFactories'] == {selected['factoryUUID']: selected['factoryFunction']}
        assert info['CFPlugInTypes'] == {'443ABAB8-E7B3-491A-B985-BEB9187030DB': [selected['factoryUUID']]}
        subprocess.run(['codesign', '--verify', '--strict', str(driver)], check=True, capture_output=True)
        signature = subprocess.run(['codesign', '-dvv', str(driver)], check=True, capture_output=True).stderr
        assert b'TeamIdentifier=A84PZNYY82' in signature
        if not development:
            assert b'Authority=Developer ID Application:' in signature
        binary = driver / 'Contents/MacOS/FaceNowMicrophone'
        archs = subprocess.check_output(['lipo', '-archs', str(binary)]).decode().split()
        if not development:
            assert set(archs) == {'arm64', 'x86_64'}
        package_info = list((root / 'install').rglob('PackageInfo'))
        assert len(package_info) == 1
        install_info = ET.parse(package_info[0]).getroot()
        assert install_info.get('identifier') == selected['installerID']
        assert install_info.get('version') == info['CFBundleShortVersionString'], 'Installer and driver versions differ'
        for bundle in install_info.findall('.//relocate/bundle'):
            raise AssertionError('Audio driver installer must not relocate to backup or build folders')
        assert not list((root / 'install').rglob('postinstall')), 'Installer must not restart system audio'
        scripts = list((root / 'uninstall').rglob('postinstall'))
        assert len(scripts) == 1
        assert scripts[0].read_text() == uninstall_script(edition)
        uninstall_info = ET.parse(next((root / 'uninstall').rglob('PackageInfo'))).getroot()
        assert uninstall_info.get('identifier') == selected['uninstallerID']
        linked = subprocess.check_output(['otool', '-L', str(binary)])
        assert b'Agora' not in linked and b'XmaxSDK' not in linked
    return dict(audioInstallerVerified=True, audioInstallerNotarizationVerified=not development,
                audioDriverArchitectures=archs)


if __name__ == '__main__':
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--development', action='store_true')
    options = parser.parse_args()
    print(json.dumps(verify(options.app.resolve(), options.development), indent=2))
