//
//  GenerationReference.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
#if canImport(FNNetwork)
    import FNNetwork
#endif

/// Presets and uploaded reference images share the selection and generation flow.
struct GenerationReference: Identifiable, Sendable {

    /// The identity used to associate this value with its displayed or pending state.
    let id: String

    /// The generation mode that owns this reference.
    let mode: GenerationMode

    /// The user-visible name of the selected device or reference.
    let name: String

    /// The preview image URL, independently of the generation reference URL.
    let thumbnailURL: URL?

    /// The original image location sent to generation after upload or preset selection.
    var referencePath: String

    /// The locally retained original image data for upload and thumbnail presentation.
    var thumbnailData: Data? = nil

    /// The default generation prompt, or a per-reference override when present.
    var prompt: String? = nil

    /// The current reference upload or retry state.
    var uploadState: UploadState = .ready

    /// The completed upload fraction used by the reference overlay.
    var uploadProgress: Double = 0

    /// The last upload failure displayed by this reference's retry control.
    var uploadError: String? = nil

    /// The upload states shared by reference selection and progress presentation.
    enum UploadState: Sendable {

        /// The reference can be submitted to generation.
        case ready

        /// The reference is waiting for its upload to complete.
        case uploading

        /// The previous upload failed and the reference can be retried.
        case error
    }

    /// Keeps prompt-only presets selectable without inventing an image URL or an upload state.
    static func promptPreset(
        _ mode: GenerationMode,
        id: String,
        name: String,
        prompt: String
    ) -> Self {
        Self(
            id: "preset:\(id)",
            mode: mode,
            name: name,
            thumbnailURL: nil,
            referencePath: "",
            prompt: prompt
        )
    }

    /// Uses a Retina-sized center crop of the Playground image while retaining the original for generation.
    static func preset(
        _ mode: GenerationMode,
        version: String,
        name: String,
        reference: String,
        prompt: String
    ) -> Self {
        let base = NetworkEnvironment.current.assetBaseURL.absoluteString
        let path = "\(base)/images/playground/\(mode.rawValue)/\(reference)?v=32&presetVersion=\(version)"
        let thumbnail = "\(path)&imageMogr2/crop/256x256/gravity/center/format/webp/quality/90"
        return Self(
            id: path,
            mode: mode,
            name: name,
            thumbnailURL: URL(string: thumbnail)!,
            referencePath: path,
            prompt: prompt
        )
    }
}
