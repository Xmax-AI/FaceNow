import CoreImage
import CoreMedia
import CoreVideo
import XCTest
@testable import CameraCore
@testable import FNVirtualCameraCore

/// Exercises output pixels without opening a camera, a preview, or the extension transport.
final class VirtualCameraWatermarkTests: XCTestCase {
    private let format = VideoFormat(
        width: 640,
        height: 360,
        frameRate: 60,
        pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    )

    func testArtworkPlacesBrandTopLeftAndCaptionTopRight() throws {
        let image = try VirtualCameraWatermark.makeImage(format: format, generationCaption: "AI")
        let pixels = rgba(image)
        XCTAssertGreaterThan(alphaSum(pixels, region: CGRect(x: 0, y: 312, width: 200, height: 48)), 10_000)
        XCTAssertGreaterThan(alphaSum(pixels, region: CGRect(x: 440, y: 312, width: 200, height: 48)), 10_000)
        XCTAssertEqual(alphaSum(pixels, region: CGRect(x: 0, y: 0, width: 640, height: 180)), 0)
        XCTAssertEqual(alphaSum(pixels, region: CGRect(x: 200, y: 80, width: 240, height: 200)), 0)
        var captionMaxX = 0
        var captionMaxY = 0
        for y in 312..<360 {
            for x in 440..<640 where pixels[(y * 640 + x) * 4 + 3] > 0 {
                captionMaxX = max(captionMaxX, x)
                captionMaxY = max(captionMaxY, y)
            }
        }
        XCTAssertEqual(639 - captionMaxX, 12)
        XCTAssertEqual(359 - captionMaxY, 12)
    }

    func testCaptionUsesTheSuppliedTextAndCanvas() throws {
        let chinese = rgba(try VirtualCameraWatermark.makeImage(format: format, generationCaption: "AI生成"))
        let english = rgba(try VirtualCameraWatermark.makeImage(format: format, generationCaption: "AI Generation"))
        XCTAssertFalse(chinese.elementsEqual(english))
        XCTAssertGreaterThan(
            alphaSum(english, region: CGRect(x: 440, y: 312, width: 200, height: 48)),
            alphaSum(chinese, region: CGRect(x: 440, y: 312, width: 200, height: 48))
        )
        let brandBytes: ([UInt8]) -> [UInt8] = { pixels in
            (312..<360).flatMap { y in Array(pixels[(y * 640 * 4)..<((y * 640 + 200) * 4)]) }
        }
        XCTAssertEqual(brandBytes(chinese), brandBytes(english))
        let large = try VirtualCameraWatermark.makeImage(
            format: VirtualCameraConfiguration.videoFormat,
            generationCaption: "AI Generation"
        )
        XCTAssertEqual(large.width, 1920)
        XCTAssertEqual(large.height, 1080)
    }

    func testCompatibleInputIsCompositedWithoutChangingSharedPixelsOrTiming() throws {
        let cleanRenderer = try VideoFrameRenderer(format: format)
        let input = try cleanRenderer.waiting()
        let original = bytes(input)
        XCTAssertTrue(try cleanRenderer.normalize(input) === input)
        let renderer = try makeRenderer()
        let output = try renderer.normalize(input)
        XCTAssertFalse(output === input, "Watermarks must bypass compatible-buffer passthrough")
        XCTAssertEqual(bytes(input), original, "SDK-owned pixels must remain immutable")
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(output), format.pixelFormat)
        XCTAssertNotNil(CVPixelBufferGetIOSurface(output))
        XCTAssertTrue(CMVideoFormatDescriptionMatchesImageBuffer(renderer.formatDescription, imageBuffer: output))
        let before = luma(input)
        let after = luma(output)
        XCTAssertEqual(changedPixels(before, after, region: CGRect(x: 0, y: 0, width: 200, height: 60)), 0)
        XCTAssertEqual(changedPixels(before, after, region: CGRect(x: 440, y: 0, width: 200, height: 60)), 0)
        XCTAssertGreaterThan(changedPixels(before, after, region: CGRect(x: 0, y: 312, width: 200, height: 48)), 50)
        XCTAssertGreaterThan(changedPixels(before, after, region: CGRect(x: 440, y: 312, width: 200, height: 48)), 50)
        XCTAssertEqual(changedPixels(before, after, region: CGRect(x: 200, y: 80, width: 240, height: 200)), 0)
        let pts = CMTime(value: 1234, timescale: 60)
        let sample = try renderer.sampleBuffer(output, at: pts)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample), pts)
        XCTAssertEqual(CMSampleBufferGetDuration(sample), format.frameDuration)
    }

    func testNormalizationPreservesOrientationAndOverlaysResizedBGRAInput() throws {
        let smallFormat = VideoFormat(width: 320, height: 180, frameRate: 30, pixelFormat: kCVPixelFormatType_32BGRA)
        let input = try VideoFrameRenderer(format: smallFormat).testPattern(at: 1.25)
        let clean = try VideoFrameRenderer(format: format).normalize(input)
        let marked = try makeRenderer().normalize(input)
        XCTAssertEqual(
            changedPixels(
                luma(clean),
                luma(marked),
                region: CGRect(x: 0, y: 100, width: 640, height: 160)
            ),
            0
        )
        XCTAssertGreaterThan(
            changedPixels(
                luma(clean),
                luma(marked),
                region: CGRect(x: 440, y: 312, width: 200, height: 48)
            ),
            50
        )
    }

    func testWaitingAndDiagnosticsStayUnmarked() throws {
        let clean = try VideoFrameRenderer(format: format)
        let marked = try makeRenderer()
        XCTAssertEqual(luma(try clean.waiting()), luma(try marked.waiting()))
        XCTAssertEqual(luma(try clean.testPattern(at: 0.5)), luma(try marked.testPattern(at: 0.5)))
    }

    func testPortraitVideoFitsTheLandscapeOutputWithoutStretching() throws {
        let portrait = VideoFormat(width: 360, height: 640, frameRate: 30, pixelFormat: kCVPixelFormatType_32BGRA)
        let input = try VideoFrameRenderer(format: portrait).testPattern(at: 0)
        let renderer = try VideoFrameRenderer(format: format)
        let output = luma(try renderer.normalize(input, preservesAspectRatio: true))
        let black = [UInt8](repeating: 16, count: format.width * format.height)
        let left = CGRect(x: 0, y: 0, width: 210, height: 360)
        let right = CGRect(x: 430, y: 0, width: 210, height: 360)
        let center = CGRect(x: 220, y: 0, width: 200, height: 360)
        XCTAssertEqual(changedPixels(black, output, region: left), 0)
        XCTAssertEqual(changedPixels(black, output, region: right), 0)
        XCTAssertGreaterThan(changedPixels(black, output, region: center), 60_000)
    }

    func testSubtitleChangesAndClearsOnTheSameSourceFrame() throws {
        let input = try VideoFrameRenderer(format: format).testPattern(at: 0)
        let renderer = try makeRenderer()
        let clean = luma(try renderer.normalize(input))
        let first = try XCTUnwrap(VideoSubtitle.makeImage(text: "Hello, everyone.", format: format))
        let second = try XCTUnwrap(VideoSubtitle.makeImage(text: "Welcome to FaceNow.", format: format))
        let firstOutput = luma(try renderer.normalize(input, subtitle: CIImage(cgImage: first)))
        let secondOutput = luma(try renderer.normalize(input, subtitle: CIImage(cgImage: second)))
        let bottom = CGRect(x: 0, y: 0, width: 640, height: 64)
        let upper = CGRect(x: 0, y: 64, width: 640, height: 296)
        XCTAssertGreaterThan(changedPixels(clean, firstOutput, region: bottom), 100)
        XCTAssertGreaterThan(changedPixels(firstOutput, secondOutput, region: bottom), 100)
        XCTAssertEqual(changedPixels(clean, firstOutput, region: upper), 0)
        XCTAssertEqual(luma(try renderer.normalize(input)), clean)
    }

    func testBoundedPoolPreservesHeldWatermarkedFrames() throws {
        let input = try VideoFrameRenderer(format: format).waiting()
        let renderer = try makeRenderer()
        var held = try (0..<8).map { _ in try renderer.normalize(input) }
        let first = bytes(held[0])
        XCTAssertThrowsError(try renderer.normalize(input))
        XCTAssertEqual(bytes(held[0]), first)
        held.removeAll()
        XCTAssertNoThrow(try renderer.normalize(input))
    }

    private func makeRenderer() throws -> VideoFrameRenderer {
        try VideoFrameRenderer(
            format: format,
            overlay: VirtualCameraWatermark.makeImage(format: format, generationCaption: "AI")
        )
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { pointer in
            CIContext().render(
                CIImage(cgImage: image),
                toBitmap: pointer.baseAddress!,
                rowBytes: image.width * 4,
                bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        // Bitmap rows begin at the top; use Cartesian image coordinates for region assertions.
        return (0..<image.height).reversed().flatMap { row in
            Array(pixels[(row * image.width * 4)..<((row + 1) * image.width * 4)])
        }
    }

    private func alphaSum(_ pixels: [UInt8], region: CGRect) -> Int {
        var sum = 0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) { sum += Int(pixels[(y * 640 + x) * 4 + 3]) }
        }
        return sum
    }

    private func bytes(_ pixels: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        var result = Data()
        for plane in 0..<CVPixelBufferGetPlaneCount(pixels) {
            result.append(
                Data(
                    bytes: CVPixelBufferGetBaseAddressOfPlane(pixels, plane)!,
                    count: CVPixelBufferGetBytesPerRowOfPlane(pixels, plane)
                        * CVPixelBufferGetHeightOfPlane(pixels, plane)
                )
            )
        }
        return result
    }

    private func luma(_ pixels: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        return (0..<height).reversed().flatMap { Array(UnsafeBufferPointer(start: base + $0 * stride, count: width)) }
    }

    private func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8], region: CGRect) -> Int {
        var count = 0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                if abs(Int(lhs[y * 640 + x]) - Int(rhs[y * 640 + x])) > 2 { count += 1 }
            }
        }
        return count
    }
}
