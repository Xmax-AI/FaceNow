//
//  MicrophoneTranslation.swift
//  XmaxCamera
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit
import AVFoundation
import Foundation
import SnapKit
import Speech
import SwiftUI
import Translation

/// Publishes English subtitles while the app's selected microphone is capturing.
@MainActor
final class MicrophoneTranslation {

    /// Reports capture readiness, translated text, and unexpected termination.
    enum Event: Sendable {
        case ready
        case subtitle(String?)
        case failed(String)
    }

    /// Explains why translation could not start.
    private struct Failure: LocalizedError {

        /// The prerequisite or operation that failed.
        let message: String

        /// A description of the failure returned to the capture task.
        var errorDescription: String? { message }
    }

    /// Gives the system translation task a window for its language download prompt.
    @available(macOS 27.0, *)
    private struct LanguageDownloadView: View {

        /// The source language to install for speech translation.
        let source: Locale.Language

        /// The target language to install for speech translation.
        let target: Locale.Language

        /// Finishes when the language pair is ready or the system returns an error.
        let completion: AsyncThrowingStream<Void, any Error>.Continuation

        /// Hosts the system prompt and verifies readiness before resuming microphone translation.
        var body: some View {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .translationTask(
                    source: source,
                    target: target,
                    preferredStrategy: .lowLatency
                ) { @concurrent session in
                    do {
                        // This request waits for the language download and verifies the pair is usable.
                        _ = try await session.translate("你好")
                        completion.finish()
                    } catch {
                        completion.finish(throwing: error)
                    }
                }
        }
    }

    /// The currently requested input, including attempts that failed for this capture.
    private var deviceID: String?

    /// The current or most recently cancelled task, retained until a replacement can start.
    private var task: Task<Void, Never>?

    /// Publishes capture and subtitle changes on the main actor.
    private let onEvent: @MainActor @Sendable (Event) -> Void

    /// Creates a translation session owner with a callback for capture events.
    init(
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) {
        self.onEvent = onEvent
    }

    /// Cancels capture when the owner is released.
    deinit {
        task?.cancel()
    }

    /// Translates the active input or stops when the ID is nil.
    /// Waits for the previous capture to release its microphone before opening another.
    func setDevice(
        _ deviceID: String?
    ) {
        guard self.deviceID != deviceID else { return }
        self.deviceID = deviceID
        let previous = task
        previous?.cancel()
        onEvent(.subtitle(nil))
        guard let deviceID, #available(macOS 27.0, *) else { return }
        task = Task { [onEvent] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await Self.translate(
                    deviceID: deviceID,
                    onEvent: onEvent
                )
                if !Task.isCancelled { onEvent(.failed("Speech capture ended unexpectedly.")) }
            } catch {
                if !Task.isCancelled { onEvent(.failed(error.localizedDescription)) }
            }
        }
    }

    /// Requests system approval in the app window and waits for the language pair to become usable.
    @available(macOS 27.0, *)
    private static func downloadLanguages(
        source: Locale.Language,
        target: Locale.Language
    ) async throws {
        try Task.checkCancellation()
        let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
        guard let contentView = window?.contentView else {
            throw Failure(message: "Open the FaceNow window to download the Chinese and English translation languages.")
        }

        let (completion, continuation) = AsyncThrowingStream<Void, any Error>.makeStream()
        let host = NSHostingView(rootView: LanguageDownloadView(
            source: source,
            target: target,
            completion: continuation
        ))
        contentView.addSubview(host)
        host.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview()
            make.width.height.equalTo(1)
        }
        defer { host.removeFromSuperview() }

        var iterator = completion.makeAsyncIterator()
        _ = try await iterator.next()
        try Task.checkCancellation()
    }

    /// Streams Mandarin recognition and publishes English previews followed by finalized segments.
    @available(macOS 27.0, *)
    @concurrent
    private static func translate(
        deviceID: String,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) async throws {
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: "en")
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)
        switch await availability.status(
            from: source,
            to: target
        ) {
        case .installed:
            break
        case .supported:
            try await downloadLanguages(
                source: source,
                target: target
            )
        default:
            throw Failure(message: "Chinese to English translation is unavailable on this Mac.")
        }
        let translator = TranslationSession(
            installedSource: source,
            target: target,
            preferredStrategy: .lowLatency
        )
        try await translator.prepareTranslation()

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) else {
            throw Failure(message: "On-device Mandarin speech recognition is unavailable on this Mac.")
        }
        guard let microphone = AVCaptureDevice(uniqueID: deviceID), microphone.hasMediaType(.audio) else {
            throw Failure(message: "The selected microphone is unavailable.")
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw Failure(message: "Allow microphone access in System Settings > Privacy & Security > Microphone.")
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await download.downloadAndInstall()
        }

        try Task.checkCancellation()
        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: microphone,
            compatibleWith: [transcriber]
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await withTaskCancellationHandler { @concurrent in
            try Task.checkCancellation()
            try await analyzer.start(inputSequence: provider.analyzerInputs)
            try Task.checkCancellation()

            let capture = provider.captureSession
            capture.startRunning()
            defer { capture.stopRunning() }
            try Task.checkCancellation()
            guard capture.isRunning else {
                throw Failure(message: "Could not start the selected microphone for translation.")
            }
            await MainActor.run {
                if !Task.isCancelled { onEvent(.ready) }
            }
            var lastPreview = ""
            var nextPreviewAt = ContinuousClock.now
            for try await result in transcriber.results {
                try Task.checkCancellation()
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if result.isFinal {
                    lastPreview = ""
                } else {
                    guard text.count >= 2, text != lastPreview, ContinuousClock.now >= nextPreviewAt else { continue }
                    lastPreview = text
                }
                let response = try await translator.translate(text)
                try Task.checkCancellation()
                if !result.isFinal { nextPreviewAt = ContinuousClock.now.advanced(by: .seconds(1)) }
                let translated = response.targetText
                await MainActor.run {
                    if !Task.isCancelled { onEvent(.subtitle(translated)) }
                }
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}
