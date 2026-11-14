//
//  GenerationStatisticsViewModel.swift
//  FaceNow
//

import Factory
import Foundation
import XmaxSDK

/// Formats the repository's live metrics for native statistics panels.
@MainActor
final class GenerationStatisticsViewModel {

    /// The shared generation data; formatted values are derived rather than cached.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// The SDK startup, uplink video, and uplink network metric groups.
    var localStatisticsPanels: [GenerationStatisticsGroup] {
        [
            .init(
                id: "Launch timing",
                rows: [
                    .init(
                        id: "Session creation",
                        value: milliseconds(generationRepo.launchTiming.sessionMs),
                        help: GenerationStrings.statisticsTimeSpentCreatingTheServerSideGenerationSession
                    ),
                    .init(
                        id: "RTC connection",
                        value: milliseconds(generationRepo.launchTiming.rtcJoinMs),
                        help: GenerationStrings.statisticsFromJoiningTheRTCChannelUntilTheConnectionSucceeds
                    ),
                    .init(
                        id: "Stream publication",
                        value: milliseconds(generationRepo.launchTiming.publishMs),
                        help: GenerationStrings.statisticsTimeSpentPublishingTheLocalMediaStreamToThe
                    ),
                    .init(
                        id: "First frame latency",
                        value: milliseconds(generationRepo.launchTiming.firstFrameMs),
                        help: GenerationStrings.statisticsFromGenerationSignalSubmissionToTheFirstDisplayReady
                    ),
                    .init(
                        id: "Total startup",
                        value: milliseconds(generationRepo.launchTiming.totalMs),
                        help:
                            GenerationStrings.statisticsFromStartingGenerationAfterCameraReadinessToTheFirst,
                        total: true
                    ),
                ]
            ),
            .init(
                id: "Uplink video statistics",
                rows: [
                    .init(
                        id: "Uplink resolution",
                        value: resolution(
                            generationRepo.uplinkStatistics?.width,
                            generationRepo.uplinkStatistics?.height
                        )
                    ),
                    .init(
                        id: "Uplink frame rate",
                        value: metric(
                            generationRepo.uplinkStatistics?.sendFrameRate,
                            "fps"
                        )
                    ),
                    .init(
                        id: "Uplink bitrate",
                        value: metric(
                            generationRepo.uplinkStatistics?.bitrateKbps,
                            "kbps"
                        )
                    ),
                ]
            ),
            .init(
                id: "Uplink network and latency",
                rows: [
                    .init(
                        id: "Uplink packet loss",
                        value: metric(
                            generationRepo.uplinkStatistics?.packetLossPercent,
                            "%"
                        ),
                        help: GenerationStrings.statisticsPacketLossFromThisSDKToTheRTCCloud
                    ),
                    .init(
                        id: "Uplink network quality",
                        value: quality(generationRepo.networkQuality?.uplink)
                    ),
                    .init(
                        id: "Uplink RTT",
                        help: GenerationStrings.statisticsNotExposedByTheMacOSSDK
                    ),
                ]
            ),
        ]
    }

    /// The downlink video and network metric groups shown over generated output.
    var remoteStatisticsPanels: [GenerationStatisticsGroup] {
        [
            .init(
                id: "Downlink video statistics",
                rows: [
                    .init(
                        id: "Downlink resolution",
                        value: resolution(
                            generationRepo.downlinkStatistics?.width,
                            generationRepo.downlinkStatistics?.height
                        )
                    ),
                    .init(
                        id: "Downlink frame rate",
                        value: metric(
                            generationRepo.downlinkStatistics?.renderFrameRate,
                            "fps"
                        )
                    ),
                    .init(
                        id: "Downlink bitrate",
                        value: metric(
                            generationRepo.downlinkStatistics?.bitrateKbps,
                            "kbps"
                        )
                    ),
                ]
            ),
            .init(
                id: "Downlink network and latency",
                rows: [
                    .init(
                        id: "Playback buffer delay",
                        help: GenerationStrings.statisticsNotExposedByTheMacOSSDK
                    ),
                    .init(
                        id: "Downlink packet loss",
                        value: metric(
                            generationRepo.downlinkStatistics?.packetLossPercent,
                            "%"
                        )
                    ),
                    .init(
                        id: "Downlink network quality",
                        value: quality(generationRepo.networkQuality?.downlink)
                    ),
                    .init(
                        id: "RTT (cloud)",
                        help: GenerationStrings.statisticsNotExposedByTheMacOSSDK
                    ),
                    .init(
                        id: "E2E (RTC estimate)",
                        value: metric(
                            generationRepo.downlinkStatistics?.endToEndDelayMs,
                            "ms"
                        )
                    ),
                ]
            ),
        ]
    }

    /// Formats an available millisecond duration without inventing a missing measurement.
    private func milliseconds(
        _ value: Double?
    ) -> String {
        value.map { GenerationStrings.milliseconds(value: $0) } ?? "—"
    }

    /// Formats an available integer metric with its explicit display unit.
    private func metric(
        _ value: Int?,
        _ unit: String
    ) -> String { value.map { GenerationStrings.metric(value: $0, unit: unit) } ?? "—" }

    /// Formats a complete width and height pair without mixing partial values.
    private func resolution(
        _ width: Int?,
        _ height: Int?
    ) -> String {
        guard let width, let height else { return "—" }
        return GenerationStrings.resolution(width: width, height: height)
    }

    /// Formats the SDK network-quality level for the diagnostic panels.
    private func quality(
        _ level: RealtimeNetworkQualityLevel?
    ) -> String {
        guard let level else { return "—" }
        switch level {
        case .unknown: return GenerationStrings.qualityUnknown
        case .excellent: return GenerationStrings.qualityExcellent
        case .good: return GenerationStrings.qualityGood
        case .poor: return GenerationStrings.qualityPoor
        case .bad: return GenerationStrings.qualityBad
        case .veryBad: return GenerationStrings.statisticsVeryBad
        case .down: return GenerationStrings.qualityDown
        }
    }
}
