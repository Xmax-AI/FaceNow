import CoreGraphics
import CoreImage
import CoreVideo
import XCTest
@testable import CameraCore

final class VideoWaitingArtworkTests: XCTestCase {

    func testOfflineArtworkIsSmallCenteredAndAspectFitted() throws {
        for size in [(640, 360), (360, 640)] {
            let format = VideoFormat(width: size.0, height: size.1, frameRate: 30, pixelFormat: kCVPixelFormatType_32BGRA)
            let renderer = try VideoFrameRenderer(format: format, waitingArtwork: makeArtwork())
            let frame = try renderer.waiting()
            let pixels = rgba(frame)
            var colored: [(Int, Int)] = []
            for y in 0..<size.1 {
                for x in 0..<size.0 {
                    let i = (y * size.0 + x) * 4
                    if pixels[i + 1] < 100 { colored.append((x, y)) }
                }
            }
            let minX = try XCTUnwrap(colored.map(\.0).min())
            let maxX = try XCTUnwrap(colored.map(\.0).max())
            let minY = try XCTUnwrap(colored.map(\.1).min())
            let maxY = try XCTUnwrap(colored.map(\.1).max())
            XCTAssertEqual(Double(minX + maxX + 1) / 2, Double(size.0) / 2, accuracy: 1)
            XCTAssertEqual(Double(minY + maxY + 1) / 2, Double(size.1) / 2, accuracy: 1)
            XCTAssertEqual(Double(maxX - minX + 1), Double(min(size.0, size.1)) * 0.28, accuracy: 2)
            XCTAssertEqual(Double(maxY - minY + 1), Double(maxX - minX + 1) / 2, accuracy: 2)
            XCTAssertGreaterThan(pixels[0], 245)
            XCTAssertGreaterThan(pixels[1], 245)
            XCTAssertGreaterThan(pixels[2], 245)
        }
    }

    func testOfflineArtworkDoesNotChangeLiveVideo() throws {
        let format = VideoFormat(width: 320, height: 180, frameRate: 30, pixelFormat: kCVPixelFormatType_32BGRA)
        let clean = try VideoFrameRenderer(format: format)
        let branded = try VideoFrameRenderer(format: format, waitingArtwork: makeArtwork())
        let input = try clean.testPattern(at: 1)
        XCTAssertEqual(rgba(try clean.normalize(input)), rgba(try branded.normalize(input)))
    }

    private func makeArtwork() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.7, green: 0, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        return try XCTUnwrap(context.makeImage())
    }

    private func rgba(_ buffer: CVPixelBuffer) -> [UInt8] {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext(options: [.useSoftwareRenderer: true]).render(CIImage(cvPixelBuffer: buffer), toBitmap: &bytes, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes
    }
}
