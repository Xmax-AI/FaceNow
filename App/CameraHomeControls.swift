//
//  CameraHomeControls.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import SwiftUI

/// Adds camera setup to the landing toolbar using the example's shared pill styles.
struct CameraHomeControls: View {
    @ObservedObject var controller: CameraSessionController
    @ObservedObject var cameraExtension: CameraExtensionController
    let height: CGFloat
    @State private var cameraPickerOpen = false
    @State private var extensionSettingsOpen = false

    var body: some View {
        HStack(spacing: 12) {
            Button { cameraPickerOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "video").font(.system(size: 13))
                    Text(controller.cameras.first { $0.id == controller.cameraID }?.name ?? "Select Camera")
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: 150)
                    RealtimeHeaderChevron().foregroundStyle(RealtimePalette.secondary)
                }
            }
            .buttonStyle(RealtimeHeaderButtonStyle(height: height))
            .fixedSize(horizontal: true, vertical: false)
            .disabled(controller.settingsLocked)
            .accessibilityLabel("Select Camera")
            .popover(isPresented: $cameraPickerOpen, arrowEdge: .bottom) {
                VStack(spacing: 2) {
                    ForEach(controller.cameras) { camera in
                        RealtimeMenuOption(title: camera.name, isSelected: controller.cameraID == camera.id) {
                            controller.cameraID = camera.id
                            cameraPickerOpen = false
                        }
                    }
                    if controller.cameras.isEmpty {
                        Text("No cameras found").foregroundStyle(RealtimePalette.secondary).padding(12)
                    }
                    Divider().padding(.vertical, 4)
                    RealtimeMenuOption(title: "Refresh Cameras", isSelected: false) { controller.refreshCameras() }
                }
                .padding(8).frame(width: 260)
            }
            Button { extensionSettingsOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "video.badge.checkmark").font(.system(size: 13))
                    Text("Virtual Camera")
                    RealtimeHeaderChevron().foregroundStyle(RealtimePalette.secondary)
                }
            }
            .buttonStyle(RealtimeHeaderButtonStyle(height: height))
            .fixedSize()
            .accessibilityLabel("Virtual Camera")
            .popover(isPresented: $extensionSettingsOpen, arrowEdge: .bottom) {
                extensionSettings
                    .onAppear { cameraExtension.refresh() }
            }
        }
    }

    /// Keeps extension installation and diagnostics out of the main example layout.
    private var extensionSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Virtual Camera").font(RealtimeHeaderTypography.font(size: 15, weight: .medium))
                Spacer()
                Button { cameraExtension.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(RealtimeHeaderButtonStyle(height: 30, iconOnly: true))
                .disabled(cameraExtension.isRefreshing || (cameraExtension.isBusy && !cameraExtension.isAwaitingApproval))
                .accessibilityLabel("Refresh Virtual Camera")
            }
            Text(cameraExtension.status)
                .foregroundStyle(RealtimePalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if cameraExtension.isEnabled {
                    Button("Update") { cameraExtension.install() }
                        .buttonStyle(RealtimeHeaderButtonStyle())
                    Button("Remove") { cameraExtension.uninstall() }
                        .buttonStyle(RealtimeHeaderButtonStyle(destructive: true))
                } else {
                    Button(cameraExtension.isAwaitingApproval ? "Awaiting Approval" : "Install & Enable") {
                        cameraExtension.install()
                    }
                    .buttonStyle(RealtimeHeaderButtonStyle())
                }
            }
            .disabled(controller.settingsLocked || cameraExtension.isBusy || cameraExtension.isRefreshing)
            if cameraExtension.isBusy && !cameraExtension.isAwaitingApproval {
                ProgressView().controlSize(.small)
            }
            Button("Open System Settings") { cameraExtension.openSettings() }
                .buttonStyle(RealtimeHeaderButtonStyle())
            Divider()
            Text("Select “Xmax Virtual Camera” in your meeting app. Keep Xmax Camera running while you present.")
                .foregroundStyle(RealtimePalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Use your regular microphone for audio.")
                .foregroundStyle(RealtimePalette.secondary)
            Button(controller.testPatternActive ? "Stop Test Pattern" : "Send Test Pattern") {
                Task { await controller.toggleTestPattern() }
            }
            .buttonStyle(RealtimeHeaderButtonStyle(destructive: controller.testPatternActive))
            .disabled(controller.isBusy || controller.sessionActive || !cameraExtension.isEnabled || cameraExtension.isBusy)
        }
        .font(RealtimeHeaderTypography.font(size: 12))
        .foregroundStyle(RealtimePalette.text)
        .padding(18).frame(width: 340)
        .tint(RealtimePalette.accent)
    }
}
