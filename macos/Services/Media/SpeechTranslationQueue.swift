//
//  SpeechTranslationQueue.swift
//  FaceNow
//

import CoreMedia
import Foundation

/// Decouples speech recognition from a single translator and bounds pending work.
actor SpeechTranslationQueue {

    /// Identifies a revision by the start of its source audio range.
    struct Segment: Sendable {

        /// The start time on the analyzer's audio timeline.
        let start: CMTime

        /// The source text to translate.
        let text: String

        /// Whether recognition has finalized this segment.
        let isFinal: Bool
    }

    /// Coalesces wakeups independently of the pending segment storage.
    nonisolated let updates: AsyncStream<Void>

    /// Signals that a segment may now be eligible for translation.
    private nonisolated let signal: AsyncStream<Void>.Continuation

    /// The most recent recognition revision, even after translation takes it.
    private var latest: Segment?

    /// Up to two recent finals waiting in source order while translation catches up.
    private var finals: [Segment] = []

    /// The newest unstarted draft for the current phrase.
    private var draft: Segment?

    /// The earliest time the consumer can start another draft translation.
    private var nextDraftAt: ContinuousClock.Instant?

    /// Wakes the consumer if no newer recognition arrives after the draft interval.
    private var draftWake: Task<Void, Never>?

    /// Creates an empty queue with a single coalesced notification slot.
    init() {
        (updates, signal) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Supersedes drafts and retains finalized phrases ahead of pending previews.
    func offer(
        _ segment: Segment
    ) {
        if let latest {
            guard segment.start >= latest.start else { return }
            if segment.start == latest.start {
                guard !latest.isFinal, segment.isFinal || segment.text != latest.text else { return }
            }
        }
        latest = segment
        if segment.isFinal {
            draft = nil
            if finals.count == 2 { finals.removeFirst() }
            finals.append(segment)
        } else {
            draft = segment
        }
        signal.yield()
    }

    /// Takes a final immediately or waits for the previous draft's display interval.
    func takeNext() -> Segment? {
        if !finals.isEmpty { return finals.removeFirst() }
        guard let draft else { return nil }
        let now = ContinuousClock.now
        if let nextDraftAt, nextDraftAt > now {
            if draftWake == nil {
                draftWake = Task { [signal] in
                    do { try await ContinuousClock().sleep(until: nextDraftAt) } catch { return }
                    signal.yield()
                }
            }
            return nil
        }
        self.draft = nil
        draftWake?.cancel()
        draftWake = nil
        return draft
    }

    /// Spaces drafts from publication so translation time cannot compress their display interval.
    func didPublishDraft() {
        nextDraftAt = ContinuousClock.now + .seconds(1)
    }

    /// Rejects an in-flight draft once its phrase is finalized or a new phrase starts.
    func canPublishDraft(
        _ segment: Segment
    ) -> Bool {
        latest?.start == segment.start && latest?.isFinal == false
    }

    /// Releases the waiting consumer when recognition ends.
    nonisolated func finish() {
        signal.finish()
    }
}
