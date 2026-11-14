//
//  VideoFormat.swift
//  FaceNow
//

import CoreMedia
import CoreVideo

/// Describes a caller-selected video canvas without camera identity or application state.
public struct VideoFormat: Sendable {

    /// The output pixel width.
    public let width: Int

    /// The output pixel height.
    public let height: Int

    /// The nominal number of output samples per second.
    public let frameRate: Int

    /// The CoreVideo pixel format used by the output buffer pool.
    public let pixelFormat: OSType

    /// The duration of one output sample.
    public var frameDuration: CMTime {
        CMTime(
            value: 1,
            timescale: CMTimeScale(frameRate)
        )
    }

    /// Creates a positive video canvas and sample cadence.
    public init(
        width: Int,
        height: Int,
        frameRate: Int,
        pixelFormat: OSType
    ) {
        precondition(width > 0 && height > 0 && frameRate > 0 && frameRate <= Int(Int32.max))
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.pixelFormat = pixelFormat
    }
}
