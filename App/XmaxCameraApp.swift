//
//  XmaxCameraApp.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// Native AppKit application lifecycle, window ownership, and standard editing menus.
@main
@MainActor
final class XmaxCameraApp: NSObject, NSApplicationDelegate {
    private let realtime = CameraViewController()
    private var window: NSWindow?
    private var terminating = false

    static func main() {
        let application = NSApplication.shared
        let delegate = XmaxCameraApp()
        application.delegate = delegate
        // Set the Dock icon directly when launching from Xcode, where Launch Services may cache an older icon.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            application.applicationIconImage = icon
        }
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenus()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 850),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Alter"
        window.contentViewController = realtime
        window.contentMinSize = NSSize(width: 1180, height: 760)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("XmaxCamera.MainWindow")
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        realtime.cameraExtension.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            await realtime.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func configureMenus() {
        let menu = NSMenu()
        let app = NSMenu(title: "Alter")
        app.addItem(withTitle: "About Alter", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Alter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Alter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = app; menu.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)

        let windows = NSMenu(title: "Window")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(); windowItem.submenu = windows; menu.addItem(windowItem)
        NSApplication.shared.windowsMenu = windows
        NSApplication.shared.mainMenu = menu
    }
}
