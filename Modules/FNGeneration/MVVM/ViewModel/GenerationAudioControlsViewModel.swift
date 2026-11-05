//
//  GenerationAudioControlsViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Factory

/// Projects microphone input selection into toolbar status without depending on generated audio activity.
@MainActor
final class GenerationAudioControlsViewModel {

    /// The presentation of the selected physical microphone input.
    enum MicrophoneStatus: CaseIterable {

        /// A selectable microphone is enabled for the current session.
        case ready

        /// The user has explicitly turned microphone input off.
        case disabled

        /// The SDK is applying an input change.
        case switching

        /// The selected input is absent from the available devices.
        case unavailable

        /// The localized status displayed beside the microphone selector.
        var title: String {
            switch self {
            case .ready: GenerationStrings.microphoneReady
            case .disabled: GenerationStrings.microphoneDisabled
            case .switching: GenerationStrings.microphoneSwitching
            case .unavailable: GenerationStrings.microphoneUnavailable
            }
        }
    }

    /// Owns the selection, input discovery, and runtime switch operation.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    /// Derives input readiness from the selected device and explicit capture intent.
    var microphoneStatus: MicrophoneStatus {
        if generationRepo.microphoneSwitching { return .switching }
        let id = generationRepo.microphoneID
        if id == GenerationRepository.disabledMicrophoneID { return .disabled }
        let available = generationRepo.microphones.contains { $0.id == id }
        return available ? .ready : .unavailable
    }

    /// Keeps adjustments available during generation while rejecting teardown.
    var canAdjust: Bool {
        generationRepo.sessionActive && !generationRepo.isClosing
    }
}
