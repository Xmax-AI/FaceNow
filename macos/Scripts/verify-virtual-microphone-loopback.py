#!/usr/bin/env python3
"""Exercise production PCM scheduling and AUHAL through the installed, idle system driver."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from device_identities import compiler_definitions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('.build/virtual-microphone-loopback/verification.json'))
    parser.add_argument('--edition', choices=['domestic', 'oversea'], default='domestic')
    parser.add_argument('--build-only', action='store_true', help='Compile the probe without opening system audio devices.')
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = options.output if options.output.is_absolute() else root / options.output
    build = output.parent
    build.mkdir(parents=True, exist_ok=True)
    sources = [
        'Tests/NativeAudio/VirtualMicrophoneLoopbackMain.swift',
        'Modules/FNVirtualMicrophone/VirtualMicrophoneOutput.swift',
        'Modules/FNVirtualMicrophone/VirtualMicrophoneStatus.swift',
        'Services/Media/AudioPCMConverter.swift',
        'Services/Media/ScheduledFrameStore.swift',
    ]
    native = root / 'Tests/NativeAudio'
    audio = root / 'Services/Media/Audio'
    for name, source in [('ReadProbe', native / 'SystemMicrophoneReadProbe.c'), ('AudioTimelineBuffer', audio / 'AudioTimelineBuffer.c')]:
        subprocess.run(['xcrun', 'clang', *compiler_definitions(options.edition), '-I', str(audio), '-I', str(native), '-c', str(source), '-o', str(build / (name + '.o'))], check=True)
    executable = build / 'MicrophoneLoopbackProbe'
    subprocess.run([
        'xcrun', 'swiftc', *(['-DOVERSEA'] if options.edition == 'oversea' else []), '-swift-version', '6', '-module-cache-path', str(build / 'ModuleCache'),
        '-import-objc-header', str(native / 'SystemMicrophoneReadProbe.h'), '-Xcc', '-I', '-Xcc', str(audio),
        *[str(root / name) for name in sources], str(build / 'ReadProbe.o'), str(build / 'AudioTimelineBuffer.o'),
        '-framework', 'CoreAudio', '-framework', 'AudioUnit', '-framework', 'AVFoundation', '-framework', 'CoreVideo',
        '-o', str(executable),
    ], check=True)
    if options.build_only:
        print('Compiled system loopback probe without opening audio devices: ' + str(executable))
        return
    result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)
    (build / 'runtime.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    report = json.loads(result.stdout.strip().splitlines()[-1])
    report['sourceSHA256'] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sources}
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'sourceSHA256'}, ensure_ascii=False))
    print('Report: ' + str(output))


if __name__ == '__main__':
    main()
