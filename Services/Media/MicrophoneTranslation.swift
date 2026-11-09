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
import XmaxSDK
import os

/// Publishes translated subtitles from the SDK's active microphone.
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
        guard #available(macOS 26.0, *) else { return ([], []) }
        async let recognized = SpeechTranscriber.supportedLocales
        let languages = await makeLanguageAvailability().supportedLanguages
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
        guard #available(macOS 26.0, *) else {
            return [.recognition: .unavailable, .translation: .unavailable]
        }
        let transcriber = await makeTranscriber(for: languages.source)
        return await resourceStatus(for: languages, transcriber: transcriber)
    }

    /// Returns separate framework statuses without reserving or downloading any assets.
    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
    @concurrent
    private static func translationStatus(
        for languages: LanguagePair
    ) async -> ResourceStatus {
        guard languages.source != languages.target else { return .unavailable }
        switch await makeLanguageAvailability().status(
            from: Locale.Language(identifier: languages.source),
            to: Locale.Language(identifier: languages.target)
        ) {
        case .installed: return .installed
        case .supported: return .needsDownload
        default: return .unavailable
        }
    }

    /// Uses the low-latency language catalog where strategy selection is available.
    @available(macOS 26.0, *)
    private nonisolated static func makeLanguageAvailability() -> LanguageAvailability {
        if #available(macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .lowLatency)
        }
        return LanguageAvailability()
    }

    /// Preserves the system's distinct background download status for speech assets.
    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
    private struct LanguageDownloadPrompt: View {
        /// The languages whose system assets the user requested.
        let languages: LanguagePair

        /// Signals that the system finished prompting or downloading.
        let completion: AsyncThrowingStream<Void, any Error>.Continuation

        /// Binds the download to the current window using the available strategy API.
        var body: some View {
            if #available(macOS 26.4, *) {
                prompt.translationTask(
                    source: Locale.Language(identifier: languages.source),
                    target: Locale.Language(identifier: languages.target),
                    preferredStrategy: .lowLatency,
                    action: prepare
                )
            } else {
                prompt.translationTask(
                    source: Locale.Language(identifier: languages.source),
                    target: Locale.Language(identifier: languages.target),
                    action: prepare
                )
            }
        }

        /// An invisible view hosting the system approval prompt.
        private var prompt: some View {
            Color.clear
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }

        /// Waits for an existing system download if preparation returns before readiness.
        @concurrent
        private func prepare(_ session: TranslationSession) async {
            do {
                try await session.prepareTranslation()
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

    /// Cancels translation when the owner is released.
    deinit {
        task?.cancel()
    }

    /// Translates SDK microphone frames after the previous subscription has been removed.
    func start(
        using manager: any XmaxRealtimeManaging,
        languages: LanguagePair
    ) {
        guard #available(macOS 26.0, *) else { return }
        let previous = task
        previous?.cancel()
        let requestedAt = ContinuousClock.now
        task = Task { [onEvent] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await Self.translate(
                    manager: manager,
                    languages: languages,
                    requestedAt: requestedAt,
                    onEvent: { event in
                        if !Task.isCancelled { onEvent(event) }
                    }
                )
                if !Task.isCancelled { onEvent(.failed("Speech analysis ended unexpectedly.")) }
            } catch {
                if !Task.isCancelled { onEvent(.failed(error.localizedDescription)) }
            }
        }
    }

    /// Cancels speech processing and clears the current subtitle.
    func stop() {
        guard let task, !task.isCancelled else { return }
        task.cancel()
        onEvent(.clear)
    }

    /// Installs the selected speech recognition asset without starting capture.
    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
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
    @available(macOS 26.0, *)
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

    /// Analyzes the SDK's PCM and publishes translated drafts followed by finalized segments.
    @available(macOS 26.0, *)
    @concurrent
    private static func translate(
        manager: any XmaxRealtimeManaging,
        languages: LanguagePair,
        requestedAt: ContinuousClock.Instant,
        onEvent: @escaping @MainActor @Sendable (Event) -> Void
    ) async throws {
        let (transcriber, downloadedLanguages) = try await prepareResources(for: languages) { kind, status in
            onEvent(.resourceStatus(kind, status))
        }
        let translator = makeTranslationSession(for: languages)
        try await translator.prepareTranslation()
        await onEvent(.preparingCapture)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              format.commonFormat == .pcmFormatInt16, format.channelCount == 1 else {
            throw Failure(message: "No compatible mono PCM16 format is available for speech analysis.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()

        let audio = SpeechAudioInput(outputFormat: format)
        let (frames, continuation) = AsyncStream<RealtimeMediaFrame>.makeStream(
            bufferingPolicy: .bufferingNewest(20)
        )
        let inputs = frames.compactMap { event -> AnalyzerInput? in
            guard case let .audio(frame) = event.content,
                  let (input, isFirst) = try await audio.convert(frame, discontinuous: event.isDiscontinuous)
            else { return nil }
            if isFirst {
                let setup = requestedAt.duration(to: .now).description
                logger.notice("SDK microphone ready after \(setup, privacy: .public) (downloaded languages: \(downloadedLanguages, privacy: .public))")
                await onEvent(.ready)
            }
            return input
        }

        await manager.setLocalMediaFrameListener(tracks: [.audio]) { frame in
            continuation.yield(frame)
        }
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let captureStartedAt = ContinuousClock.now
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        do {
                            _ = try await analyzer.analyzeSequence(inputs)
                        } catch {
                            await analyzer.cancelAndFinishNow()
                            throw error
                        }
                        await analyzer.cancelAndFinishNow()
                    }
                    do {
                        try await streamTranslations(
                            from: transcriber,
                            using: translator,
                            languages: languages,
                            analyzer: analyzer,
                            captureStartedAt: captureStartedAt,
                            onEvent: onEvent
                        )
                        group.cancelAll()
                        await analyzer.cancelAndFinishNow()
                        try await group.waitForAll()
                    } catch {
                        group.cancelAll()
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                }
            } onCancel: {
                continuation.finish()
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            continuation.finish()
            await manager.setLocalMediaFrameListener(nil)
            throw error
        }
        continuation.finish()
        await manager.setLocalMediaFrameListener(nil)
    }

    /// Opens an on-device translation session for the selected, installed languages.
    @available(macOS 26.0, *)
    nonisolated private static func makeTranslationSession(
        for languages: LanguagePair
    ) -> TranslationSession {
        let source = Locale.Language(identifier: languages.source)
        let target = Locale.Language(identifier: languages.target)
        if #available(macOS 26.4, *) {
            return TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        }
        return TranslationSession(installedSource: source, target: target)
    }

    /// Drains speech independently while translating at most one phrase at a time.
    @available(macOS 26.0, *)
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

@available(macOS 26.0, *)
private extension MicrophoneTranslation {

    /// Resamples SDK packets and places them on a continuous, session-relative speech timeline.
    actor SpeechAudioInput {

        /// The PCM format requested by the speech modules.
        private let outputFormat: AVAudioFormat

        /// The streaming resampler and its current source format.
        private var converter: AVAudioConverter?

        /// The host time used as the speech timeline's origin.
        private var origin: CMTime?

        /// The expected timestamp of the next incoming PCM packet.
        private var nextSourceTime: CMTime?

        /// The end of the last buffer accepted for speech.
        private var nextOutputTime: CMTime?

        /// Creates a converter for the selected speech format.
        init(outputFormat: AVAudioFormat) {
            self.outputFormat = outputFormat
        }

        /// Preserves gaps and resets resampling history when capture or delivery drops samples.
        func convert(
            _ frame: RealtimeAudioFrame,
            discontinuous: Bool
        ) throws -> (AnalyzerInput, isFirst: Bool)? {
            let rate = Double(frame.sampleRate)
            let channels = AVAudioChannelCount(frame.channels)
            if converter?.inputFormat.sampleRate != rate || converter?.inputFormat.channelCount != channels {
                guard let source = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: rate,
                    channels: channels,
                    interleaved: true
                ), let resampler = AVAudioConverter(from: source, to: outputFormat) else {
                    throw Failure(message: "The microphone audio format is unsupported for speech analysis.")
                }
                resampler.primeMethod = .none
                converter = resampler
                nextSourceTime = nil
            }
            guard let converter,
                  let input = AVAudioPCMBuffer(
                    pcmFormat: converter.inputFormat,
                    frameCapacity: AVAudioFrameCount(frame.samplesPerChannel)
                  ),
                  let output = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(ceil(frame.duration.seconds * outputFormat.sampleRate)) + 64
                  )
            else { throw Failure(message: "Could not allocate a speech audio buffer.") }

            input.frameLength = input.frameCapacity
            guard let bytes = input.mutableAudioBufferList.pointee.mBuffers.mData,
                  frame.data.count == input.mutableAudioBufferList.pointee.mBuffers.mDataByteSize
            else { throw Failure(message: "The microphone returned an invalid PCM packet.") }
            frame.data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: frame.data.count)

            let timestamp = frame.presentationTimeStamp
            let gap = nextSourceTime.map { abs(CMTimeSubtract(timestamp, $0).seconds) > 0.000_001 } ?? true
            if discontinuous || gap { converter.reset() }
            nextSourceTime = timestamp + frame.duration

            var suppliedInput = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, status in
                if suppliedInput {
                    status.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                status.pointee = .haveData
                return input
            }
            if status == .error {
                if let conversionError { throw conversionError }
                throw Failure(message: "Could not convert microphone PCM for speech analysis.")
            }
            guard output.frameLength > 0 else { return nil }

            let isFirst = origin == nil
            if isFirst { origin = timestamp }
            let capturedTime = timestamp - (origin ?? timestamp)
            let previousEnd = nextOutputTime ?? .zero
            let time = discontinuous || gap ? max(previousEnd, capturedTime) : previousEnd
            nextOutputTime = time + CMTime(value: Int64(output.frameLength), timescale: Int32(outputFormat.sampleRate))
            return (AnalyzerInput(buffer: output, bufferStartTime: time), isFirst)
        }
    }
}
