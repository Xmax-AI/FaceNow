"""Edition-specific system-device packaging identities shared by build and verification."""
import hashlib
import json
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent
IDENTITIES = json.loads((SOURCE / 'Configuration/DeviceIdentities.json').read_text())
DRIVER_SOURCES = [
    'Configuration/DeviceIdentities.json', 'Scripts/device_identities.py',
    'VirtualMicrophoneDriver/FaceNowMicrophone.c', 'VirtualMicrophoneDriver/Info.plist',
    'Services/Media/Audio/AudioTimelineBuffer.c', 'Services/Media/Audio/AudioTimelineBuffer.h',
    'Scripts/Audio/uninstall-microphone.sh',
]


def identity(edition):
    if edition not in IDENTITIES:
        raise ValueError('Unknown FaceNow edition: ' + str(edition))
    return IDENTITIES[edition]


def source_digest(edition):
    identity(edition)
    return hashlib.sha256(edition.encode() + b'\0' + b''.join(
        name.encode() + b'\0' + hashlib.sha256((SOURCE / name).read_bytes()).digest()
        for name in DRIVER_SOURCES
    )).hexdigest()


def uninstall_script(edition):
    domestic, selected = identity('domestic'), identity(edition)
    return (SOURCE / 'Scripts/Audio/uninstall-microphone.sh').read_text().replace(
        domestic['driverFilename'], selected['driverFilename']
    ).replace(domestic['driverBundleID'], selected['driverBundleID'])


def compiler_definitions(edition):
    selected = identity(edition)
    fields = {
        'DRIVER_BUNDLE_ID': 'driverBundleID', 'BOX_UID': 'boxUID', 'DEVICE_UID': 'microphoneUID',
        'WRITER_UID': 'writerUID', 'MODEL_UID': 'modelUID', 'MICROPHONE_NAME': 'microphoneName',
        'SPEAKER_NAME': 'speakerName',
    }
    return ['-DFACENOW_' + macro + '=' + json.dumps(selected[key], ensure_ascii=False)
            for macro, key in fields.items()] + ['-DFACENOW_FACTORY_FUNCTION=' + selected['factoryFunction']]
