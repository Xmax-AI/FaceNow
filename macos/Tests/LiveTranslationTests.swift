import CoreMedia
import CoreVideo
import XCTest
@testable import CameraCore

final class LiveTranslationTests: XCTestCase, @unchecked Sendable {

    func testOnlyTheNewestUnstartedDraftIsTranslated() async {
        let queue = SpeechTranslationQueue()
        let start = CMTime(value: 0, timescale: 1)
        await queue.offer(.init(start: start, text: "First draft", isFinal: false))
        await queue.offer(.init(start: start, text: "Updated draft", isFinal: false))

        let next = await queue.takeNext()
        XCTAssertEqual(next?.text, "Updated draft")
    }

    func testFinalInvalidatesAnInFlightDraftAndPrecedesTheNextPhrase() async throws {
        let queue = SpeechTranslationQueue()
        let start = CMTime(value: 0, timescale: 1)
        let nextStart = CMTime(value: 1, timescale: 1)
        await queue.offer(.init(start: start, text: "First draft", isFinal: false))
        let inFlight = await queue.takeNext()
        let draft = try XCTUnwrap(inFlight)
        let canInitiallyPublish = await queue.canPublishDraft(draft)
        XCTAssertTrue(canInitiallyPublish)

        await queue.offer(.init(start: start, text: "Final text", isFinal: true))
        await queue.offer(.init(start: nextStart, text: "Next phrase", isFinal: false))
        let canStillPublish = await queue.canPublishDraft(draft)
        let next = await queue.takeNext()
        XCTAssertFalse(canStillPublish)
        XCTAssertEqual(next?.text, "Final text")
        XCTAssertEqual(next?.isFinal, true)
    }

    func testFinalBacklogRetainsRecentPhrasesInSourceOrder() async {
        let queue = SpeechTranslationQueue()
        for index in 0..<12 {
            await queue.offer(.init(
                start: CMTime(value: Int64(index), timescale: 1),
                text: "Phrase \(index)",
                isFinal: true
            ))
        }

        var translated: [String] = []
        while let segment = await queue.takeNext() { translated.append(segment.text) }
        XCTAssertEqual(translated, ["Phrase 10", "Phrase 11"])
    }

    func testPublishedDraftHoldsLaterDraftsButDoesNotDelayTheFinal() async {
        let queue = SpeechTranslationQueue()
        let start = CMTime(value: 0, timescale: 1)
        await queue.offer(.init(start: start, text: "First draft", isFinal: false))
        let first = await queue.takeNext()
        XCTAssertEqual(first?.text, "First draft")
        await queue.didPublishDraft()

        await queue.offer(.init(start: start, text: "Updated draft", isFinal: false))
        let held = await queue.takeNext()
        XCTAssertNil(held)

        await queue.offer(.init(start: start, text: "Final text", isFinal: true))
        let final = await queue.takeNext()
        XCTAssertEqual(final?.text, "Final text")
        XCTAssertEqual(final?.isFinal, true)
        queue.finish()
    }

    func testLongFinalCaptionPreservesEveryWordAcrossPages() {
        let format = VideoFormat(
            width: 1920,
            height: 1080,
            frameRate: 60,
            pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        )
        let text = """
            Good morning everyone. Today I will explain how the microphone picks up your speech, how the system translates it into English, \
            and how the subtitles appear over the video so that everyone in the meeting can follow along without missing the details.
            """

        let pages = VideoSubtitle.pages(text: text, format: format)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.joined(separator: " "), text)
        for page in pages {
            XCTAssertNotNil(VideoSubtitle.makeImage(text: page, format: format))
        }
    }
}
