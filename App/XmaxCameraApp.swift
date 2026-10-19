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
import SwiftUI

/// The independent host application for the Xmax virtual camera.
@main
struct XmaxCameraApp: App {
    /// The delegate retains resources until asynchronous shutdown finishes.
    @NSApplicationDelegateAdaptor(CameraAppDelegate.self) private var delegate

    /// One workspace prevents concurrent producers from the same application.
    var body: some Scene {
        Window("Xmax Camera", id: "camera") {
            CameraView(session: delegate.session, cameraExtension: delegate.cameraExtension)
        }
        .defaultSize(width: 1120, height: 700)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

/// Releases camera, network and sink resources before process termination.
@MainActor
final class CameraAppDelegate: NSObject, NSApplicationDelegate {
    /// Application-lifetime controllers shared with the workspace.
    let session = CameraSessionController()
    let cameraExtension = CameraExtensionController()

    /// Reconciles approval changes when the user returns from System Settings.
    func applicationDidBecomeActive(_ notification: Notification) {
        cameraExtension.refresh()
    }

    /// Quit and window closing both complete asynchronous shutdown.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await session.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Closing the only workspace also stops virtual output.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
