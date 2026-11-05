// Copyright (c) 2026 XMAX.AI PTE. LTD.

import AppKit
import Combine
import Factory

/// Owns opt-in generated-audio output; driver installation always remains an explicit user action.
@MainActor
final class VirtualMicrophoneRepository: ObservableObject {

    /// The generation-owned transport, shared independently from local monitoring volume.
    let output = VirtualMicrophoneOutput()

    /// Remembers output intent within each app edition's preferences.
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "virtualMicrophone.enabled")

    /// Reports actual AUHAL activation rather than inferring it from an enabled switch.
    @Published private(set) var running = false

    /// Caches system publication for the home header; device queries run outside the main actor.
    @Published private(set) var deviceAvailable = false

    /// Separates the installed bundle from a device that Core Audio has actually published.
    @Published private(set) var driverInstalled = false

    /// Coalesces foreground refreshes without blocking UI rendering on Core Audio.
    private var deviceRefresh: Task<Void, Never>?

    /// The latest nonfatal output failure, shown in the setup dialog.
    @Published private(set) var failure: String?

    /// Connects worker status to the main actor without retaining the repository through its transport.
    init() {
        output.onStatus = { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let running): self.running = running
                case .failure:
                    self.running = false
                    self.failure = VirtualMicrophoneStrings.failed
                    self.setEnabled(false)
                }
            }
        }
        output.setEnabled(enabled)
        refreshDeviceAvailability()
    }

    /// Applies user intent without requesting microphone permission or changing the default input/output.
    func setEnabled(
        _ enabled: Bool
    ) {
        self.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "virtualMicrophone.enabled")
        output.setEnabled(enabled)
    }

    /// Refreshes system enumeration after launch or returning from installation/settings.
    func refreshDeviceAvailability() {
        guard deviceRefresh == nil else { return }
        deviceRefresh = Task { [weak self] in
            let status = await Task.detached {
                let available = VirtualMicrophoneOutput.installedDevice() != nil
                let url = URL(
                    fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/FaceNowMicrophone.driver/Contents/Info.plist"
                )
                let info = (try? Data(contentsOf: url)).flatMap {
                    try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
                }
                let installed = info?["CFBundleIdentifier"] as? String == "com.xmax.facenow.microphone.driver"
                return (available: available, installed: installed || available)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.deviceAvailable = status.available
            self.driverInstalled = status.installed
            self.deviceRefresh = nil
        }
    }

    /// Reports the actual installed bundle, including the period before Core Audio loads it.
    var isInstalled: Bool { driverInstalled }

    /// Shares one interpretation of device availability and output intent across all status views.
    var status: VirtualMicrophoneStatus {
        VirtualMicrophoneStatus.resolve(
            driverInstalled: driverInstalled,
            deviceAvailable: deviceAvailable,
            enabled: enabled,
            hasFailure: failure != nil
        )
    }

    /// Clears a previously displayed failure for a new explicit setup action.
    func clearFailure() { failure = nil }

    /// Opens the administrator-authorized system installer without executing it in the app sandbox.
    func installDriver() { openInstaller(named: "FaceNowMicrophone") }

    /// Stops output before opening the narrowly scoped removal package.
    func uninstallDriver() {
        setEnabled(false)
        openInstaller(named: "FaceNowMicrophoneUninstall")
    }

    /// Reports a missing or unlaunchable installer through the normal nonfatal status.
    private func openInstaller(
        named name: String
    ) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pkg"), NSWorkspace.shared.open(url) else {
            failure = VirtualMicrophoneStrings.failed
            return
        }
    }

}

extension Container {
    /// Shares one output owner across generation, setup, and application lifecycle.
    @MainActor
    var virtualMicrophoneRepo: Factory<VirtualMicrophoneRepository> {
        Factory(self) { @MainActor in VirtualMicrophoneRepository() }.singleton
    }
}
