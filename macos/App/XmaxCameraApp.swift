//
//  XmaxCameraApp.swift
//  FaceNow
//

import AppKit
import Darwin
import os
@_spi(Diagnostics) import XmaxSDK

/// Native AppKit application lifecycle, window ownership, and standard editing menus.
@main
@MainActor
final class XmaxCameraApp: NSObject, NSApplicationDelegate {

    /// The lazily created composition root for all FaceNow business components.
    private lazy var home: HomeViewController = {
        let viewController = HomeViewController()
        return viewController
    }()

    /// The retained main window containing the home coordinator.
    private var window: NSWindow?

    /// Bounds asynchronous business cleanup before AppKit termination completes.
    private let shutdownCoordinator = AppShutdownCoordinator()

    /// Keeps an independent termination deadline armed through final SDK notifications.
    private var exitWatchdog: AppExitWatchdog?

    /// Owns update checks while reading media availability from the composition root.
    private lazy var updater: ApplicationUpdater = {
        let updater = ApplicationUpdater { [weak self] in
            self?.home.canInstallApplicationUpdate ?? false
        }
        return updater
    }()

    /// Handles diagnostics before initializing the native application and its business components.
    static func main() {
        if CommandLine.arguments.contains("--verify-video-beauty") {
            Task {
                do {
                    let data = try await RealtimeBeautyDiagnostics.verify()
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    exit(EXIT_SUCCESS)
                } catch {
                    FileHandle.standardError.write(
                        Data("Beauty verification failed: \(error.localizedDescription)\n".utf8)
                    )
                    exit(EXIT_FAILURE)
                }
            }
            dispatchMain()
        }
        if VirtualCameraDiagnostics.handleCommandLine(sdkVersion: XmaxSDKInfo.version) { return }
        let application = NSApplication.shared
        let delegate = XmaxCameraApp()
        application.delegate = delegate
        // Set the Dock icon directly when launching from Xcode, where Launch Services may cache an older icon.
        if let url = Bundle.main.url(
            forResource: "AppIcon",
            withExtension: "icns"
        ),
            let icon = NSImage(contentsOf: url)
        {
            application.applicationIconImage = icon
        }
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }

    /// Creates the main FaceNow window and installs the business composition root.
    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        configureMenus()
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 1440,
                height: 900
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FaceNow"
        window.contentViewController = home
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("XmaxCamera.MainWindow")
        var initialSize = NSSize(
            width: 1440,
            height: 900
        )
        if let screen = NSScreen.main {
            let available = window.contentRect(
                forFrameRect: screen.visibleFrame.insetBy(
                    dx: 24,
                    dy: 24
                )
            ).size
            initialSize.width = min(initialSize.width, available.width)
            initialSize.height = min(initialSize.height, available.height)
        }
        window.contentMinSize = NSSize(
            width: min(1180, initialSize.width),
            height: min(760, initialSize.height)
        )
        // Apply the window-owned size after installing the composition root.
        window.setContentSize(initialSize)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        home.onUpdateInstallationAvailabilityChanged = { [weak self] in
            self?.updater.resumeInstallationIfPossible()
        }
        updater.start()
    }

    /// Refreshes extension status without requesting installation or opening capture.
    func applicationDidBecomeActive(
        _ notification: Notification
    ) {
        home.virtualCameraRepo.refresh()
    }

    /// Terminates the application after its last main window closes.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool { true }

    /// Coordinates bounded resource cleanup before replying to AppKit's termination request.
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        updater.shutdown()
        if exitWatchdog == nil {
            // Keep this deadline alive after cleanup: SDK termination observers can also deadlock.
            exitWatchdog = AppExitWatchdog { Darwin._exit(EXIT_SUCCESS) }
        }
        shutdownCoordinator.start(
            cleanup: { [home] in
                await home.shutdown()
            },
            completion: { timedOut in
                if timedOut {
                    Logger(
                        subsystem: VirtualCameraConfiguration.appBundleID,
                        category: "Shutdown"
                    )
                    .error("Shutdown exceeded 8 seconds; exiting without SDK termination observers")
                    // exit() and AppKit termination both invoke handlers that can re-enter a stuck SDK.
                    Darwin._exit(EXIT_SUCCESS)
                }
                sender.reply(toApplicationShouldTerminate: true)
            }
        )
        return .terminateLater
    }

    /// Installs native application and editing commands for the FaceNow window.
    private func configureMenus() {
        let menu = NSMenu()
        menu.font = Typography.font(size: 13)
        let app = NSMenu(title: "FaceNow")
        app.font = Typography.font(size: 13)
        app.addItem(
            withTitle: "About FaceNow",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        let updates = app.addItem(
            withTitle: UpdateStrings.checkForUpdates,
            action: #selector(ApplicationUpdater.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updates.target = updater
        app.addItem(.separator())
        app.addItem(
            withTitle: "Hide FaceNow",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        app.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        app.addItem(.separator())
        app.addItem(
            withTitle: "Quit FaceNow",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let appItem = NSMenuItem()
        appItem.submenu = app
        menu.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.font = Typography.font(size: 13)
        edit.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        edit.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        edit.addItem(.separator())
        edit.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        edit.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        edit.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        edit.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        let editItem = NSMenuItem()
        editItem.submenu = edit
        menu.addItem(editItem)

        let windows = NSMenu(title: "Window")
        windows.font = Typography.font(size: 13)
        windows.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windows.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        let windowItem = NSMenuItem()
        windowItem.submenu = windows
        menu.addItem(windowItem)
        NSApplication.shared.windowsMenu = windows
        NSApplication.shared.mainMenu = menu
    }
}
