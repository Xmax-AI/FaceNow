//
//  VirtualMicrophoneRepository.swift
//  FaceNow
//

import AppKit
import Combine
import Factory

/// Owns opt-in generated-audio output; driver installation always remains an explicit user action.
@MainActor
final class VirtualMicrophoneRepository: ObservableObject {

    /// Queries device publication and the installed bundle outside the main actor.
    typealias DeviceQuery = @Sendable () -> (available: Bool, installed: Bool)

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

    /// Exposes progress and completion only for user-requested checks.
    @Published private(set) var deviceCheckState: VirtualMicrophoneDeviceCheckState = .idle

    /// Supplies system facts without blocking rendering and can be substituted in offline tests.
    private let deviceQuery: DeviceQuery

    /// Bounds user-visible checking even if a system query does not return.
    private let deviceCheckTimeout: Duration

    /// Ends explicit checking without cancelling or duplicating a shared system query.
    private var deviceCheckDeadline: Task<Void, Never>?

    /// Coalesces foreground refreshes without blocking UI rendering on Core Audio.
    private var deviceRefresh: Task<Void, Never>?

    /// The latest nonfatal output failure, shown in the setup dialog.
    @Published private(set) var failure: String?

    /// Shares one interpretation of device availability and output intent across all status views.
    var status: VirtualMicrophoneStatus {
        VirtualMicrophoneStatus.resolve(
            driverInstalled: driverInstalled,
            deviceAvailable: deviceAvailable,
            enabled: enabled,
            hasFailure: failure != nil
        )
    }

    /// Connects worker status to the main actor without retaining the repository through its transport.
    init(
        deviceQuery: @escaping DeviceQuery = VirtualMicrophoneRepository.readDeviceAvailability,
        deviceCheckTimeout: Duration = .seconds(5)
    ) {
        self.deviceQuery = deviceQuery
        self.deviceCheckTimeout = deviceCheckTimeout
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
        let query = deviceQuery
        deviceRefresh = Task { [weak self] in
            let status = await Task.detached(operation: query).value
            guard !Task.isCancelled, let self else { return }
            self.deviceAvailable = status.available
            self.driverInstalled = status.installed
            self.deviceRefresh = nil
            if self.deviceCheckState == .checking {
                self.deviceCheckDeadline?.cancel()
                self.deviceCheckDeadline = nil
                self.deviceCheckState = .completed
            }
        }
    }

    /// Reuses current discovery while publishing progress and a bounded completion result.
    func checkDeviceAvailability() {
        guard deviceCheckState != .checking else { return }
        deviceCheckDeadline?.cancel()
        deviceCheckState = .checking
        let timeout = deviceCheckTimeout
        deviceCheckDeadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard !Task.isCancelled, let self, self.deviceCheckState == .checking else { return }
            self.deviceCheckState = .timedOut
            self.deviceCheckDeadline = nil
        }
        refreshDeviceAvailability()
    }

    /// Clears view-bound feedback while allowing shared background discovery to finish.
    func resetDeviceCheck() {
        deviceCheckDeadline?.cancel()
        deviceCheckDeadline = nil
        if deviceCheckState != .idle { deviceCheckState = .idle }
    }

    /// Reads installation and publication independently without loading or starting any audio device.
    nonisolated private static func readDeviceAvailability() -> (available: Bool, installed: Bool) {
        let available = VirtualMicrophoneOutput.installedDevice() != nil
        let url = URL(
            fileURLWithPath: VirtualMicrophoneConfiguration.installedInfoPath
        )
        let info = (try? Data(contentsOf: url)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        let installed = info?["CFBundleIdentifier"] as? String == VirtualMicrophoneConfiguration.driverBundleID
        return (available: available, installed: installed || available)
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
            failure = VirtualMicrophoneStrings.installerUnavailable
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
