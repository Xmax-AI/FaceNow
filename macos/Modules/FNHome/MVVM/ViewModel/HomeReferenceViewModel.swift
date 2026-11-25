//
//  HomeReferenceViewModel.swift
//  FaceNow
//

import Combine
import Factory
import Foundation

/// Owns home appearance selection and drafts independently from the running generation session.
@MainActor
final class HomeReferenceViewModel: ObservableObject {

    @Injected(\.generationRepo) private var generationRepo: GenerationRepository

    private let presets = Array(GenerationMode.charx.presets.prefix(5))
    @Published private(set) var references: [GenerationReference]
    @Published private(set) var selected: GenerationReference
    @Published private(set) var uploaded: [GenerationReference] = []
    @Published private(set) var pending: GenerationReference?
    @Published private(set) var freeReference: GenerationReference?
    @Published private(set) var isImporting = false
    @Published private(set) var error: String?
    @Published var prompt = ""
    @Published var isStarting = false
    private var importID: UUID?

    var canEdit: Bool { !isStarting && !isImporting }
    var canSubmitPrompt: Bool { canEdit && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init() {
        let initial = Array(GenerationMode.charx.presets.prefix(5))
        references = initial
        selected = initial[0]
    }

    func catalog(
        for mode: GenerationMode
    ) -> [GenerationReference] {
        let pending = pending.map { $0.mode == mode ? [$0] : [] } ?? []
        return pending + uploaded.filter { $0.mode == mode } + mode.presets
    }

    /// Adds a catalog selection once, then preserves it alongside the five initial home choices.
    func select(
        _ reference: GenerationReference
    ) {
        guard canEdit, reference.uploadState == .ready else { return }
        if !references.contains(where: { $0.id == reference.id }) { references.insert(reference, at: 0) }
        selected = reference
        error = nil
        if reference.mode == .free {
            prompt = reference.prompt ?? ""
            freeReference = reference.referencePath.isEmpty ? nil : reference
        }
    }

    /// Keeps optional imagery separate from a prompt draft until the user submits it.
    func removeFreeReference() {
        guard canEdit else { return }
        freeReference = nil
    }

    func submitPrompt() -> Bool {
        guard canSubmitPrompt else { return false }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = freeReference?.referencePath ?? ""
        let existing = references.first { $0.mode == .free && $0.prompt == text && $0.referencePath == path }
        let reference =
            existing
            ?? GenerationReference(
                id: UUID().uuidString,
                mode: .free,
                name: freeReference == nil ? text : GenerationMode.free.title,
                thumbnailURL: freeReference?.thumbnailURL,
                referencePath: path,
                thumbnailData: freeReference?.thumbnailData,
                prompt: text
            )
        select(reference)
        return true
    }

    /// The caller owns cancellation; an identity also rejects late progress after an account reset.
    func importImage(
        at url: URL,
        mode: GenerationMode
    ) async -> Bool {
        guard canEdit else { return false }
        let identity = UUID()
        importID = identity
        isImporting = true
        error = nil
        defer {
            if importID == identity {
                importID = nil
                isImporting = false
                pending = nil
            }
        }
        do {
            let text = mode == .free ? prompt : mode.prompt
            var reference = try await Task.detached {
                try GenerationReference.localImage(at: url, mode: mode, prompt: text)
            }.value
            try Task.checkCancellation()
            guard importID == identity else { return false }
            reference.uploadState = .uploading
            pending = reference
            let approved = try await generationRepo.approveHomeReference(reference) { [weak self] progress in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    guard let self, self.importID == identity, var pending = self.pending else { return }
                    if fraction > pending.uploadProgress {
                        pending.uploadProgress = fraction
                        self.pending = pending
                    }
                }
            }
            try Task.checkCancellation()
            guard importID == identity else { return false }
            if mode == .free {
                freeReference = approved
            } else {
                uploaded.insert(approved, at: 0)
                // Selection is committed only after upload and safety approval have completed.
                isImporting = false
                select(approved)
            }
            return true
        } catch {
            if !Task.isCancelled, importID == identity { self.error = error.localizedDescription }
            return false
        }
    }

    func reset() {
        importID = nil
        pending = nil
        isImporting = false
        uploaded = []
        references = presets
        selected = presets[0]
        freeReference = nil
        prompt = ""
        error = nil
    }
}
