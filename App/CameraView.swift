//
//  CameraView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import SwiftUI
import XmaxSDK

/// The standalone camera workspace, with separate local and generated previews.
struct CameraView: View {
    /// App-owned session and installation controllers.
    @ObservedObject var session: CameraSessionController
    @ObservedObject var cameraExtension: CameraExtensionController

    /// The workspace uses the SDK's native video views without frame copies for UI.
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "video.badge.waveform.fill")
                    .font(.system(size: 28)).foregroundStyle(.indigo)
                    .frame(width: 56, height: 56).background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Xmax Camera").font(.system(size: 26, weight: .semibold))
                    Text("Your generated video, in your next meeting.").foregroundStyle(.secondary)
                }
                Spacer()
                Label("720p · 30 fps", systemImage: "circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
            HStack(alignment: .top, spacing: 24) {
                controls.frame(width: 280)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 16) {
                        videoPanel(title: "Camera", subtitle: "Local preview", track: session.localStream?.videoTrack)
                        videoPanel(title: "Output", subtitle: "Generated video", track: session.remoteStream?.videoTrack)
                    }
                    HStack(spacing: 10) {
                        Circle().fill(session.phase == .generating || session.phase == .testing ? .green : .secondary)
                            .frame(width: 7, height: 7)
                        Text(session.status).font(.callout)
                        Spacer()
                        if session.phase == .preparing || session.phase == .stopping {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    if let error = session.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("In your meeting app").font(.headline)
                        Text("Select “Xmax Virtual Camera” as your camera. Keep Xmax Camera running while you present.")
                        Text("Use your regular microphone for audio.").foregroundStyle(.secondary)
                    }
                    .font(.callout).padding(.top, 8)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(28).frame(minWidth: 1060, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { cameraExtension.refresh() }
    }

    /// Setup and generation controls remain visually stable throughout startup.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Virtual camera", systemImage: "video.badge.checkmark").font(.headline)
                    Text(cameraExtension.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Group {
                            if cameraExtension.isEnabled {
                                Button("Update") { cameraExtension.install() }
                                Button("Remove") { cameraExtension.uninstall() }
                            } else {
                                Button(cameraExtension.isAwaitingApproval ? "Awaiting Approval" : "Install & Enable") {
                                    cameraExtension.install()
                                }
                            }
                        }
                        .disabled(cameraExtension.isBusy || cameraExtension.isRefreshing || !session.isIdle)
                        Button { cameraExtension.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(cameraExtension.isRefreshing ||
                                      (cameraExtension.isBusy && !cameraExtension.isAwaitingApproval) || !session.isIdle)
                    }
                    Button("Open System Settings") { cameraExtension.openSettings() }.font(.caption)
                    if (cameraExtension.isBusy && !cameraExtension.isAwaitingApproval) || cameraExtension.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key").font(.callout.weight(.medium))
                SecureField("Enter your API key", text: $session.apiKey).textFieldStyle(.roundedBorder)
                HStack {
                    Text("Camera").font(.callout.weight(.medium))
                    Spacer()
                    Button { session.refreshCameras() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                }
                Picker("Camera", selection: $session.cameraID) {
                    if session.cameras.isEmpty { Text("No camera connected").tag("") }
                    ForEach(session.cameras) { camera in Text(camera.name).tag(camera.id) }
                }.labelsHidden()
                Text("Model").font(.callout.weight(.medium)).padding(.top, 4)
                Picker("Model", selection: $session.model) {
                    Text("X2.1.1 Preview · China").tag(RealtimeModel.x2_1_1_preview_cn)
                    Text("X2.1.1 Preview · US").tag(RealtimeModel.x2_1_1_preview_us)
                }.labelsHidden()
                Text("Free Prompt").font(.callout.weight(.medium)).padding(.top, 4)
                TextEditor(text: $session.prompt).font(.body).scrollContentBackground(.hidden)
                    .padding(6).frame(height: 90)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }.disabled(!session.isIdle)
            if session.isIdle {
                Button { session.startGeneration() } label: {
                    Label("Start Generation", systemImage: "sparkles").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(.indigo)
                Button("Send Test Pattern") { session.startTestPattern() }.frame(maxWidth: .infinity)
            } else {
                Button { session.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(.indigo)
                    .disabled(session.phase == .stopping)
            }
        }
    }

    /// Keeps the local view mounted while its first frame makes the SDK ready.
    private func videoPanel(title: String, subtitle: String, track: RealtimeVideoTrack?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.headline); Spacer(); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            ZStack {
                Color(red: 0.045, green: 0.05, blue: 0.075)
                XmaxVideo(track: track, videoContentMode: .fit)
                if track == nil {
                    VStack(spacing: 10) {
                        Image(systemName: title == "Camera" ? "video" : "sparkles").font(.system(size: 26))
                        Text(session.phase == .testing && title == "Output" ? "Test pattern is being sent" : "Waiting for video")
                            .font(.caption)
                    }.foregroundStyle(.white.opacity(0.45))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }.frame(maxWidth: .infinity)
    }
}
