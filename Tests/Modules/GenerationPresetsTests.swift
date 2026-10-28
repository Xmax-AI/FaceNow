import Foundation
import XCTest
@testable import FNGenerationModels

final class GenerationPresetsTests: XCTestCase {

    func testPresetIdentityAndOriginalReferencesSurviveModuleExtraction() {
        let presets = GenerationMode.allCases.flatMap(\.presets)
        XCTAssertFalse(presets.isEmpty)
        XCTAssertEqual(
            Set(presets.map(\.id)).count,
            presets.count
        )
        for reference in presets {
            XCTAssertEqual(
                reference.id,
                reference.referencePath
            )
            XCTAssertEqual(
                reference.thumbnailURL.host,
                "cdn.22duck.cn"
            )
            XCTAssertTrue(reference.thumbnailURL.absoluteString.contains("imageMogr2/thumbnail/160x160"))
            XCTAssertFalse(reference.referencePath.contains("imageMogr2"))
            XCTAssertEqual(
                reference.mode.prompt,
                GenerationMode(rawValue: reference.mode.rawValue)?.prompt
            )
        }
    }

    func testFaceRestorationRemainsLimitedToVirtualTryOn() {
        XCTAssertEqual(
            GenerationMode.allCases.filter(\.faceRestoration),
            [.clothx]
        )
    }

    func testFreePromptStartsWithoutPresetImagesOrImplicitPrompt() {
        XCTAssertTrue(GenerationMode.free.presets.isEmpty)
        XCTAssertEqual(
            GenerationMode.free.prompt,
            ""
        )
    }
}
