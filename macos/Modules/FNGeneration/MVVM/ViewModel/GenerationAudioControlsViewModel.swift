//
//  GenerationAudioControlsViewModel.swift
//  FaceNow
//

import Combine
import Factory

/// Supplies physical microphone readings and adjustment availability to the audio toolbar.
@MainActor
final class GenerationAudioControlsViewModel {

    /// Owns the selection, input discovery, and runtime switch operation.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Owns saved virtual microphone output settings across sessions.
    @Injected(\.virtualMicrophoneRepo) private var virtualMicrophoneRepo: VirtualMicrophoneRepository

    /// Owns the echo-cancellation setting and the playback reference route.
    var echoCancellation: PlaybackEchoCancellation { generationRepo.echoCancellation }

    /// The upper bound for the virtual microphone slider in percent.
    var maximumVirtualMicrophonePercentage: Double { Double(VirtualMicrophoneRepository.maximumVolume) * 100 }

    /// Publishes the saved linear output gain, with unity represented as 100% in the view.
    var virtualMicrophoneVolumes: AnyPublisher<Float, Never> {
        virtualMicrophoneRepo.$volume.eraseToAnyPublisher()
    }

    /// Observes existing capture without requesting permission or starting microphone input.
    var microphoneLevels: AnyPublisher<Float?, Never> {
        generationRepo.microphoneLevels
    }

    /// Hides the input indicator when physical microphone input is explicitly disabled or unresolved.
    var showsInputLevel: Bool {
        let id = generationRepo.microphoneID
        return !id.isEmpty && id != GenerationRepository.disabledMicrophoneID
    }

    /// Keeps adjustments available during generation while rejecting teardown.
    var canAdjust: Bool {
        generationRepo.sessionActive && !generationRepo.isClosing
    }

    /// The saved meeting-output offset, in milliseconds within minus 5000 through plus 5000.
    var audioSyncOffsetMilliseconds: Int { generationRepo.audioSyncOffsetMilliseconds }

    /// Keeps an open adjustment card synchronized with repository-owned settings.
    var audioSyncOffsets: AnyPublisher<Int, Never> {
        generationRepo.$audioSyncOffsetMilliseconds.eraseToAnyPublisher()
    }

    /// Applies virtual microphone volume independently from speaker monitoring.
    func setVirtualMicrophoneVolume(
        _ volume: Float
    ) {
        virtualMicrophoneRepo.setVolume(volume)
    }

    /// Changes relative meeting-output timing without changing local monitoring or input capture.
    func setAudioSyncOffset(
        _ milliseconds: Int
    ) {
        generationRepo.setAudioSyncOffset(milliseconds)
    }
}
