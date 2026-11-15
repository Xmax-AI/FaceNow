# FaceNow virtual microphone driver

The HAL plug-in is adapted from Apple’s [Creating an Audio Server Driver Plug-in](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in) sample (NullAudio). The MIT license is retained in `LICENSE-Apple.txt` and copied into the built driver.

Upstream ZIP: `https://docs-assets.developer.apple.com/published/430ad6501f6f/CreatingAnAudioServerDriverPlugIn.zip`
Upstream `NullAudio.c` SHA-256: `8b61fb9f96c12356c7da6696a6c1bee5da73222dfb4e831aa9487244e7bf5dfc`

Local changes replace product identities, implement timestamp-tagged Float32 stereo loopback with a 512-frame capture delay, apply volume/mute, and keep zero timestamps current after idle gaps. The device supports 44.1/48 kHz. A normal Core Audio output client feeds the same device’s input stream. The plug-in never captures a physical microphone, loads the SDK, or changes default audio devices.

The mainland China edition uses device UID `com.xmax.facenow.microphone.device` and driver `FaceNowMicrophone.driver`. The overseas edition uses `com.xmax.facenow.oversea.microphone.device` and `FaceNowMicrophoneOversea.driver`. Both drivers install under `/Library/Audio/Plug-Ins/HAL/`. The [edition identity configuration](../Configuration/DeviceIdentities.json) records the corresponding writer UIDs and installer identities. FaceNow addresses the hidden writer by UID.

`Scripts/build-virtual-microphone.py` builds from local source, signs the driver, and embeds install/uninstall packages in the app. Debug packages are local test artifacts. Release requires `FACENOW_AUDIO_DRIVER_SIGNING_IDENTITY` (Developer ID Application) and `FACENOW_AUDIO_INSTALLER_SIGNING_IDENTITY` (Developer ID Installer); each installer package must also be notarized and stapled before release validation. After signing and notarizing both packages, use `FACENOW_AUDIO_INSTALLERS_DIRECTORY` to embed them byte-for-byte before signing the outer app. Embedded source digests reject packages from different driver source. Installer identities belong in ignored local configuration, never in source control. The release verifier checks the nested packages independently; notarization of the outer app is not a substitute.

Installation and removal are explicit actions in FaceNow’s app menu. Both use macOS Installer authorization. No script restarts `coreaudiod`, interrupts calls, or changes security settings. The install package is non-relocatable. Removal verifies the bundle identifier and removes only FaceNow’s driver. Restart macOS if necessary to load an installed driver or unload a removed one.

Tests under `Tests/NativeAudio` call the actual plug-in interface in a standalone process and load the signed packaged binary. They do not register a system driver. The C ring uses fixed storage and lock-free atomics in the render callback; gaps, expiry, and previous sessions produce silence. Swift tests cover PCM conversion and the mapping from generated video deadlines to audio delivery. End-to-end AUHAL/sandbox and meeting-app verification still requires the installed system driver.
