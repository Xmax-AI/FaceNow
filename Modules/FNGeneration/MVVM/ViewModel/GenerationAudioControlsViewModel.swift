//
//  GenerationAudioControlsViewModel.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Combine
import Factory

/// Supplies physical microphone readings and adjustment availability to the audio toolbar.
@MainActor
final class GenerationAudioControlsViewModel {

    /// Owns the selection, input discovery, and runtime switch operation.
    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

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
}
