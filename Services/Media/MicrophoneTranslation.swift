//
//  MicrophoneTranslation.swift
//  FaceNow
//

import AppKit
import AVFoundation
import Foundation
import SnapKit
import Speech
import SwiftUI
import Translation
import os

/// Publishes translated subtitles while the app's selected microphone is capturing.
@MainActor
final class MicrophoneTranslation {

    /// The recognition and subtitle languages selected for a capture.
    struct LanguagePair: Equatable, Sendable {
        let source: String
        let target: String

        /// Preserves the original first-run translation direction.
        static let defaultPair = Self(source: "zh-Hans", target: "en")
    }

    /// The independently managed resource types required by live translation.
    enum ResourceKind: CaseIterable, Hashable, Sendable {
        case recognition
        case translation
    }

    /// System availability and progress for one language resource.
    enum ResourceStatus: Equatable, Sendable {
        case installed
        case needsDownload
        case downloading(percent: Int?)
        case failed
        case unavailable

        /// Whether the resource is being installed by this app or the system.
        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }

    /// Delivers installation progress on the application's main actor.
    typealias ResourceUpdate = @MainActor @Sendable (ResourceKind, ResourceStatus) -> Void

    /// Returns the system translation languages and the subset supported by on-device recognition.
    @concurrent
    static func availableLanguages() async -> (sources: [String], targets: [String]) {
        guard #available(macOS 27.0, *) else { return ([], []) }
        async let recognized = SpeechTranscriber.supportedLocales
        let languages = await LanguageAvailability(preferredStrategy: .lowLatency).supportedLanguages
        let recognitionLanguages = await recognized.map(\.language)
        let sources = languages.filter { language in
            recognitionLanguages.contains { $0.isEquivalent(to: language) }
        }
        return (sources.map(languageIdentifier), languages.map(languageIdentifier))
    }

    /// Keeps the system's default Chinese entry aligned with the original Simplified Chinese setting.
    private nonisolated static func languageIdentifier(
        _ language: Locale.Language
    ) -> String {
        let identifier = language.minimalIdentifier
        return identifier == "zh" ? "zh-Hans" : identifier
    }

    /// Checks both speech recognition and translation assets for the selected pair.
    @concurrent
    static func resourceStatus(
        for languages: LanguagePair
    ) async -> [ResourceKind: ResourceStatus] {
        guard #available(macOS 27.0, *) else {
            return [.recognition: .unavailable, .translation: .unavailable]
        }
        let transcriber = await makeTranscriber(for: languages.source)
        return await resourceStatus(for: languages, transcriber: transcriber)
    }

    /// Returns separate framework statuses without reserving or downloading any assets.
    @available(macOS 27.0, *)
    @concurrent
    private static func resourceStatus(
        for languages: LanguagePair,
        transcriber: SpeechTranscriber?
    ) async -> [ResourceKind: ResourceStatus] {
        async let recognition = recognitionStatus(for: transcriber)
        async let translation = translationStatus(for: languages)
        return await [.recognition: recognition, .translation: translation]
    }

    /// Checks the translation pair independently of speech recognition.
    @available(macOS 27.0, *)
    @concurrent
    private static func translationStatus(
        for languages: LanguagePair
    ) async -> ResourceStatus {
        guard languages.source != languages.target else { return .unavailable }
        switch await LanguageAvailability(preferredStrategy: .lowLatency).status(
            from: Locale.Language(identifier: languages.source),
            to: Locale.Language(identifier: languages.target)
        ) {
        case .installed: return .installed
        case .supported: return .needsDownload
        default: return .unavailable
        }
    }

    /// Preserves the system's distinct background download status for speech assets.
    @available(macOS 27.0, *)
    @concurrent
    private static func recognitionStatus(
        for transcriber: SpeechTranscriber?
    ) async -> ResourceStatus {
        guard let transcriber else { return .unavailable }
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .downloading: return .downloading(percent: nil)
        default: return .unavailable
        }
    }

    /// Resolves a translation language to a compatible on-device speech locale.
    @available(macOS 27.0, *)
    @concurrent
    private static func makeTranscriber(
        for language: String
    ) async -> SpeechTranscriber? {
        let requested = Locale(identifier: language == "zh-Hans" ? "zh-CN" : language)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else { return nil }
        return SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

    /// Reports capture readiness, translated text, and unexpected termination.
    enum Event: Sendable {
        case resourceStatus(ResourceKind, ResourceStatus)
        case preparingCapture
        case ready
        case subtitle(String, isFinal: Bool)
        case clear
        case failed(String)
    }

    /// Reports timings without including speech or subtitle text.
    private nonisolated static let logger = Logger(subsystem: "com.xmax.facenow", category: "LiveTranslation")

    /// Explains why translation could not start.
    private struct Failure: LocalizedError {

        /// The prerequisite or operation that failed.
        let message: String

        /// A description of the failure returned to the capture task.
        var errorDescription: String? { message }
    }

    /// Gives macOS a view in which to confirm the requested translation download.
    @available(macOS 27.0, *)
    private struct LanguageDownloadPrompt: View {
        let languages: LanguagePair
        let completion: AsyncThrowingStream<Void, any Error>.Continuation

        var body: some View {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .translationTask(
                    source: Locale.Language(identifier: languages.source),
                    target: Locale.Language(identifier: languages.target),
                    preferredStrategy: .lowLatency
                ) { @concurrent session in
                    do {
                        try await session.prepareTranslation()
                        // The framework can return while an existing system download is still running.
                        let deadline = ContinuousClock.now + .seconds(600)
                        while ContinuousClock.now < deadline, !(await session.isReady) {
                            try await Task.sleep(for: .seconds(1))
                        }
                        completion.finish()
                    } catch CocoaError.userCancelled {
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
        _ deviceID: String?,
        languages: LanguagePair = .defaultPair
    ) {
        guard self.deviceID != deviceID else { return }
        self.deviceID = deviceID
        let previous = task
        previous?.cancel()
        onEvent(.clear)
        guard let deviceID, #available(macOS 27.0, *) else { return }
        let requestedAt = ContinuousClock.now
        task = Task { [onEvent] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await Self.translate(
                    deviceID: deviceID,
                    languages: languages,
                    requestedAt: requestedAt,
                    onEvent: { event in
                        if !Task.isCancelled { onEvent(event) }
                    }
                )
                if !Task.isCancelled { onEvent(.failed("Speech capture ended unexpectedly.")) }
            } catch {
                if !Task.isCancelled { onEvent(.failed(error.localizedDescription)) }
            }
        }
    }

    /// Installs the selected speech recognition asset without starting capture.
    @available(macOS 27.0, *)
    @concurrent
    static func downloadSpeechResource(
        for language: String,
        onUpdate: @escaping ResourceUpdate
    ) async throws {
        let transcriber = await makeTranscriber(for: language)
        let status = await recognitionStatus(for: transcriber)
        try Task.checkCancellation()
        await onUpdate(.recognition, status)
        guard let transcriber, status != .unavailable else {
            throw Failure(message: "The selected speech resource is unavailable on this Mac.")
        }
        try await installSpeechResource(transcriber, status: status, onUpdate: onUpdate)
    }

    /// Requests macOS approval in the originating window and returns the latest readiness.
    @available(macOS 27.0, *)
    static func downloadTranslationResource(
        for languages: LanguagePair,
        in window: NSWindow
    ) async throws -> ResourceStatus {
        let status = await translationStatus(for: languages)
        try Task.checkCancellation()
        guard status == .needsDownload else { return status }
        guard let content = window.contentView else {
            throw Failure(message: "The FaceNow window is unavailable for the language download.")
        }

        let (completion, continuation) = AsyncThrowingStream<Void, any Error>.makeStream()
        let host = NSHostingView(rootView: LanguageDownloadPrompt(languages: languages, completion: continuation))
        content.addSubview(host)
        host.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview()
            make.width.height.equalTo(1)
        }
        defer { host.removeFromSuperview() }

        var iterator = completion.makeAsyncIterator()
        _ = try await iterator.next()
        try Task.checkCancellation()
        return await translationStatus(for: languages)
    }

    /// Requires installed translation languages and prepares speech recognition before capture.
    @available(macOS 27.0, *)
    @concurrent
    private static func prepareResources(
        for languages: LanguagePair,
        onUpdate: @escaping ResourceUpdate
    ) async throws -> (transcriber: SpeechTranscriber, downloadedLanguages: Bool) {
        let transcriber = await makeTranscriber(for: languages.source)
        let statuses = await resourceStatus(for: languages, transcriber: transcriber)
        try Task.checkCancellation()
        for (kind, status) in statuses { await onUpdate(kind, status) }
        guard let transcriber, let recognition = statuses[.recognition], let translation = statuses[.translation],
            recognition != .unavailable, translation == .installed
        else {
            throw Failure(message: "The speech resource must be supported and both translation languages must be installed.")
        }
        try await installSpeechResource(transcriber, status: recognition, onUpdate: onUpdate)
        try Task.checkCancellation()
        return (transcriber, recognition != .installed)
    }

    /// Shares speech installation progress and failure handling with capture startup.
    @available(macOS 27.0, *)
    @concurrent
    private static func installSpeechResource(
        _ transcriber: SpeechTranscriber,
        status: ResourceStatus,
        onUpdate: @escaping ResourceUpdate
    ) async throws {
        guard status != .installed else { return }
        try Task.checkCancellation()
        await onUpdate(.recognition, .downloading(percent: nil))
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await downloadRecognition(request, onUpdate: onUpdate)
            }
            await onUpdate(.recognition, .installed)
        } catch {
            if !Task.isCancelled { await onUpdate(.recognition, .failed) }
            throw error
        }
    }

    /// Samples the framework's actual progress until installation completes or fails.
    @available(macOS 27.0, *)
    @concurrent
    private static func downloadRecognition(
        _ request: AssetInstallationRequest,
        onUpdate: @escaping ResourceUpdate
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let progress = request.progress
                var lastPercent: Int?
                while !Task.isCancelled {
                    let fraction = progress.fractionCompleted
                    let percent = progress.isIndeterminate || !fraction.isFinite ? nil : Int(min(1, max(0, fraction)) * 100)
                    if percent != lastPercent {
                        lastPercent = percent
                        await onUpdate(.recognition, .downloading(percent: percent))
                    }
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
            }
            defer { group.cancelAll() }
            try await request.downloadAndInstall()
        }
    }

    /// Streams recognition and publishes translated drafts followed by finalized segments.
    @available(macOS 27.0, *)
    @concurrent
    private static func translate(
        deviceID: String,
        languages: LanguagePair,
        requestedAt: ContinuousClock.Instant,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) async throws {
        guard let microphone = AVCaptureDevice(uniqueID: deviceID), microphone.hasMediaType(.audio) else {
            throw Failure(message: "The selected microphone is unavailable.")
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw Failure(message: "Allow microphone access in System Settings > Privacy & Security > Microphone.")
        }

        let (transcriber, downloadedLanguages) = try await prepareResources(for: languages) { kind, status in
            onEvent(.resourceStatus(kind, status))
        }
        let translator = makeTranslationSession(for: languages)
        try await translator.prepareTranslation()

        try Task.checkCancellation()
        await onEvent(.preparingCapture)
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
            let notifications = NotificationCenter.default
            let captureStopped = notifications.addObserver(
                forName: AVCaptureSession.didStopRunningNotification,
                object: capture,
                queue: nil
            ) { _ in
                Task { await analyzer.cancelAndFinishNow() }
            }
            let microphoneDisconnected = notifications.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: microphone,
                queue: nil
            ) { _ in
                Task { await analyzer.cancelAndFinishNow() }
            }
            defer {
                notifications.removeObserver(captureStopped)
                notifications.removeObserver(microphoneDisconnected)
                capture.stopRunning()
            }
            capture.startRunning()
            try Task.checkCancellation()
            guard capture.isRunning else {
                throw Failure(message: "Could not start the selected microphone for translation.")
            }
            let captureStartedAt = ContinuousClock.now
            let setup = requestedAt.duration(to: captureStartedAt).description
            logger.notice("Capture ready after \(setup, privacy: .public) (downloaded languages: \(downloadedLanguages, privacy: .public))")
            await onEvent(.ready)
            try await streamTranslations(
                from: transcriber,
                using: translator,
                languages: languages,
                analyzer: analyzer,
                captureStartedAt: captureStartedAt,
                onEvent: onEvent
            )
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// Opens an on-device translation session for the selected, installed languages.
    @available(macOS 27.0, *)
    nonisolated private static func makeTranslationSession(
        for languages: LanguagePair
    ) -> TranslationSession {
        TranslationSession(
            installedSource: Locale.Language(identifier: languages.source),
            target: Locale.Language(identifier: languages.target),
            preferredStrategy: .lowLatency
        )
    }

    /// Drains speech independently while translating at most one phrase at a time.
    @available(macOS 27.0, *)
    @concurrent
    private static func streamTranslations(
        from transcriber: SpeechTranscriber,
        using initialTranslator: TranslationSession,
        languages: LanguagePair,
        analyzer: SpeechAnalyzer,
        captureStartedAt: ContinuousClock.Instant,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) async throws {
        let queue = SpeechTranslationQueue()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                defer { queue.finish() }
                var hasRecognizedSpeech = false
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, result.isFinal || text.count >= 2 else { continue }
                    if !hasRecognizedSpeech {
                        hasRecognizedSpeech = true
                        let elapsed = captureStartedAt.duration(to: .now).description
                        logger.notice("First recognition after capture start: \(elapsed, privacy: .public)")
                    }
                    await queue.offer(SpeechTranslationQueue.Segment(
                        start: result.range.start,
                        text: text,
                        isFinal: result.isFinal
                    ))
                }
            }

            do {
                var translator = initialTranslator
                var previous: (segment: SpeechTranslationQueue.Segment, translation: String)?
                var hasPublishedCaption = false
                for await _ in queue.updates {
                    while let segment = await queue.takeNext() {
                        try Task.checkCancellation()
                        let translation: String
                        if let previous, previous.segment.start == segment.start, previous.segment.text == segment.text {
                            translation = previous.translation
                        } else {
                            do {
                                translation = try await translator.translate(segment.text).targetText
                            } catch TranslationError.internalError, TranslationError.notInstalled {
                                logger.notice("Retrying caption after the system translation session became unavailable")
                                try await Task.sleep(for: .milliseconds(350))
                                translator = makeTranslationSession(for: languages)
                                translation = try await translator.translate(segment.text).targetText
                            }
                        }
                        previous = (segment, translation)
                        try Task.checkCancellation()
                        if !segment.isFinal {
                            guard await queue.canPublishDraft(segment) else { continue }
                        }
                        if !hasPublishedCaption {
                            hasPublishedCaption = true
                            let elapsed = captureStartedAt.duration(to: .now).description
                            logger.notice("First translation ready after capture start: \(elapsed, privacy: .public)")
                        }
                        await onEvent(.subtitle(translation, isFinal: segment.isFinal))
                        if !segment.isFinal { await queue.didPublishDraft() }
                    }
                }
                try await group.waitForAll()
            } catch {
                group.cancelAll()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        }
    }
}
