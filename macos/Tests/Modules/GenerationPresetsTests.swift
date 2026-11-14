import Foundation
import XCTest
@testable import FNGenerationModels

final class GenerationPresetsTests: XCTestCase {

    func testPresetIdentityAndImagesMatchTheRegionalPlayground() throws {
        #if OVERSEA
            let expectedHost = "cdn.xmax.ai"
        #else
            let expectedHost = "cdn.22duck.cn"
        #endif
        let presets = GenerationMode.allCases.flatMap(\.presets)
        XCTAssertFalse(presets.isEmpty)
        XCTAssertEqual(
            Set(presets.map(\.id)).count,
            presets.count
        )
        for reference in presets {
            guard let thumbnailURL = reference.thumbnailURL else {
                XCTAssertEqual(reference.mode, .dimx)
                XCTAssertTrue(reference.referencePath.isEmpty)
                XCTAssertFalse(reference.prompt?.isEmpty ?? true)
                continue
            }
            XCTAssertEqual(
                reference.id,
                reference.referencePath
            )
            XCTAssertEqual(
                thumbnailURL.host,
                expectedHost
            )
            XCTAssertTrue(thumbnailURL.absoluteString.contains("imageMogr2/crop/256x256/gravity/center"))
            XCTAssertTrue(thumbnailURL.absoluteString.contains("format/webp/quality/90"))
            XCTAssertFalse(reference.referencePath.contains("imageMogr2"))
            let original = try XCTUnwrap(URLComponents(string: reference.referencePath))
            let thumbnail = try XCTUnwrap(URLComponents(url: thumbnailURL, resolvingAgainstBaseURL: false))
            XCTAssertEqual(original.path, thumbnail.path, "The displayed image must be the generation reference")
            XCTAssertTrue(original.path.hasPrefix("/images/playground/\(reference.mode.rawValue)/"))
            XCTAssertEqual(original.queryItems?.first { $0.name == "presetVersion" }?.value, "20261030")
            XCTAssertEqual(original.queryItems?.first { $0.name == "v" }?.value, "32")
            XCTAssertFalse(reference.prompt?.isEmpty ?? true)
        }
    }

    func testImageOrderMatchesFaceNowCatalog() {
        let expected: [(GenerationMode, [String])] = [
            (.charx, [
                "charx_image21.png", "charx_image2.jpeg", "charx_image22.png", "charx_image23.jpeg",
                "charx_image24.png", "charx_image25.jpeg", "charx_image13.jpeg", "charx_image14.png",
                "charx_image16.png", "charx_real_image17.jpeg", "charx_image18.png",
            ]),
            (.clothx, [
                "clothx_image1.png", "clothx_image2.png", "clothx_real_image3.png", "clothx_real_image4.png",
                "clothx_image5.png", "clothx_image6.png", "clothx_image7.png", "clothx_image8.png",
                "clothx_real_image9.png", "clothx_real_image10.png", "clothx_image11.jpeg", "clothx_image12.jpeg",
            ]),
            (.vibex, (1...8).map { "vibex_real_image\($0).png" }),
        ]
        for (mode, filenames) in expected {
            XCTAssertEqual(mode.presets.map { URL(string: $0.referencePath)?.lastPathComponent }, filenames)
        }
    }

    func testCharacterAccessoryAndStylePromptsMatchX21() throws {
        let cap = try XCTUnwrap(GenerationMode.clothx.presets.first {
            URL(string: $0.referencePath)?.lastPathComponent == "clothx_image11.jpeg"
        })
        let glasses = try XCTUnwrap(GenerationMode.clothx.presets.first {
            URL(string: $0.referencePath)?.lastPathComponent == "clothx_image12.jpeg"
        })
        #if OVERSEA
            let charxPrompt = "Become the character in the reference image"
            let vibexPrompt = "The character from the reference image recreates the actions in the video. "
                + "Preserve all appearance details of the reference character exactly, "
                + "and keep the original background from the reference image unchanged."
            let vibexPresetPrompt = vibexPrompt
            XCTAssertEqual(cap.prompt, "Apply the cap from the reference image to the video character.")
            XCTAssertEqual(glasses.prompt, "Apply the glasses from the reference image to the video character.")
        #else
            let charxPrompt = "视频中人物替换成参考图中角色"
            let vibexPrompt = "参考图角色重现视频动作，角色全部外观细节保留，保留并使用参考图的背景"
            let vibexPresetPrompt = vibexPrompt + "。"
            XCTAssertEqual(cap.prompt, "将参考图棒球帽应用到视频角色身上")
            XCTAssertEqual(glasses.prompt, "将参考图眼镜应用到视频角色身上")
        #endif
        XCTAssertEqual(GenerationMode.charx.prompt, charxPrompt)
        XCTAssertTrue(GenerationMode.charx.presets.allSatisfy { $0.prompt == charxPrompt })
        XCTAssertEqual(GenerationMode.vibex.prompt, vibexPrompt)
        XCTAssertTrue(GenerationMode.vibex.presets.allSatisfy { $0.prompt == vibexPresetPrompt })
        XCTAssertNotEqual(cap.prompt, GenerationMode.clothx.prompt)
        XCTAssertNotEqual(glasses.prompt, GenerationMode.clothx.prompt)
    }

    func testFaceRestorationIsEnabledOnlyForTheTenClothingPresets() {
        let restoredImages: Set<String> = [
            "clothx_image1.png", "clothx_image2.png", "clothx_real_image3.png", "clothx_real_image4.png",
            "clothx_image5.png", "clothx_image6.png", "clothx_image7.png", "clothx_image8.png",
            "clothx_real_image9.png", "clothx_real_image10.png",
        ]
        let presets = GenerationMode.allCases.flatMap(\.presets)
        XCTAssertEqual(presets.filter(\.faceRestoration).count, restoredImages.count)
        for reference in presets {
            let filename = URL(string: reference.referencePath)?.lastPathComponent ?? ""
            XCTAssertEqual(
                reference.faceRestoration,
                reference.mode == .clothx && restoredImages.contains(filename),
                "Unexpected face restoration setting for \(reference.id)"
            )
        }
    }

    func testUploadedReferencesDisableFaceRestorationInEveryMode() {
        for mode in GenerationMode.allCases {
            var uploaded = GenerationReference(
                id: UUID().uuidString,
                mode: mode,
                name: "Custom image",
                thumbnailURL: URL(fileURLWithPath: "/tmp/reference.png"),
                referencePath: "",
                thumbnailData: Data([1]),
                prompt: mode.prompt
            )
            XCTAssertFalse(uploaded.faceRestoration, "Custom references must opt out even in virtual try-on")
            uploaded.referencePath = "https://example.com/uploaded-reference.png"
            uploaded.uploadState = .ready
            XCTAssertFalse(uploaded.faceRestoration, "Completing an upload must preserve the reference setting")
        }
    }

    func testSummonSupportsPromptOnlyAndImagePresetsInPlaygroundOrder() {
        XCTAssertEqual(GenerationMode.allCases, [.charx, .clothx, .vibex, .dimx, .free])
        let presets = GenerationMode.dimx.presets
        XCTAssertEqual(presets.count, 7)
        XCTAssertEqual(Array(presets.prefix(2).map(\.id)), ["preset:dimx-little-dog", "preset:dimx-little-mouse"])
        for preset in presets.prefix(2) {
            XCTAssertNil(preset.thumbnailURL)
            XCTAssertTrue(preset.referencePath.isEmpty)
            XCTAssertEqual(preset.uploadState, .ready)
        }
        XCTAssertEqual(
            presets.dropFirst(2).map { URL(string: $0.referencePath)?.lastPathComponent },
            [3, 4, 5, 7, 8].map { "dimx_image\($0).png" }
        )
        XCTAssertTrue(presets.dropFirst(2).allSatisfy { $0.thumbnailURL != nil })
        #if OVERSEA
            XCTAssertEqual(presets.first?.prompt, "Summon a small dog onto the person's shoulder.")
            XCTAssertEqual(presets[1].prompt, "Summon a little mouse onto the person's shoulder.")
            XCTAssertTrue(presets[2].prompt?.contains("without replacing any existing subject") == true)
        #else
            XCTAssertEqual(presets.first?.prompt, "召唤一只小狗到人的肩膀上")
            XCTAssertEqual(presets[1].prompt, "召唤一只小老鼠到人物肩膀上")
            XCTAssertTrue(presets[2].prompt?.contains("不替换任何原有主体") == true)
        #endif
        XCTAssertTrue(GenerationMode.dimx.presets.allSatisfy { !$0.faceRestoration })
    }

    func testFreePromptStartsWithoutPresetImagesOrImplicitPrompt() {
        XCTAssertTrue(GenerationMode.free.presets.isEmpty)
        XCTAssertEqual(
            GenerationMode.free.prompt,
            ""
        )
    }
}
