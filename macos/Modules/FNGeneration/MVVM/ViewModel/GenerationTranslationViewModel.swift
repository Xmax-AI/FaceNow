//
//  GenerationTranslationViewModel.swift
//  FaceNow
//

import Foundation

/// Projects live translation settings and status for the centered configuration dialog.
@MainActor
final class GenerationTranslationViewModel {

    /// A stable picker identity and its localized label.
    struct Choice: Equatable {
        let id: String
        let title: String
    }

    /// Pairs the single-line status with its guidance and indicator tone.
    struct Status {
        /// The meaning of the indicator beside the status text.
        enum Tone {
            case idle, pending, ready, blocked
        }

        let title: String
        let detail: String
        let tone: Tone

        /// Uses the visible title as guidance when it already fits on one line.
        init(
            _ title: String,
            detail: String? = nil,
            tone: Tone
        ) {
            self.title = title
            self.detail = detail ?? title
            self.tone = tone
        }
    }

    /// Presents a selected language and its system-reported installation state.
    struct ResourceRow {
        let language: String
        let status: MicrophoneTranslation.ResourceStatus?
        let statusTitle: String?
        let actionTitle: String?
        let isActionEnabled: Bool
    }

    /// The shared session and translation configuration owner.
    let repository: GenerationRepository

    /// The system's available speech and subtitle language choices.
    private var languages: (sources: [String], targets: [String])?

    /// The last result shown before a language change started a fresh check.
    private var lastKnownTranslationResourceStatus: MicrophoneTranslation.ResourceStatus?

    /// Binds the presentation to the current generation session.
    init(
        repository: GenerationRepository
    ) {
        self.repository = repository
    }

    /// Keeps the language pack message steady while the new selection is checked.
    var status: Status {
        if let availability = repository.translationResources[.translation] {
            lastKnownTranslationResourceStatus = availability
        }
        return Self.status(for: repository, previousAvailability: lastKnownTranslationResourceStatus)
    }

    /// Explains the current state consistently on the toolbar and inside the dialog.
    static func status(
        for repository: GenerationRepository,
        previousAvailability: MicrophoneTranslation.ResourceStatus? = nil
    ) -> Status {
        guard GenerationRepository.supportsTranslation else {
            return Status(GenerationStrings.translationRequiresMacOS, tone: .blocked)
        }
        switch repository.translationState {
        case .waitingForMicrophone: return Status(GenerationStrings.translationWaitingForMicrophone, tone: .pending)
        case .preparing: return Status(GenerationStrings.translationPreparing, tone: .pending)
        case .downloadingLanguages: return Status(GenerationStrings.translationDownloadingLanguages, tone: .pending)
        case .listening: return Status(GenerationStrings.translationListening, tone: .ready)
        case .off:
            if repository.translationFailed {
                return Status(
                    GenerationStrings.translationStatusInterrupted,
                    detail: GenerationStrings.translationUnavailable,
                    tone: .blocked
                )
            }
            let authorization = repository.microphoneAuthorization
            if authorization != .authorized {
                return Status(
                    GenerationStrings.translationStatusNeedsPermission,
                    detail: authorization == .notDetermined
                        ? GenerationStrings.translationMicrophoneAccess
                        : GenerationStrings.microphonePermissionRequired,
                    tone: .pending
                )
            }
            if repository.microphoneID.isEmpty || repository.microphoneID == GenerationRepository.disabledMicrophoneID {
                return Status(
                    GenerationStrings.translationStatusNeedsMicrophone,
                    detail: GenerationStrings.translationChooseMicrophone,
                    tone: .pending
                )
            }
            let availability = repository.translationResources[.translation] ?? previousAvailability
            if availability == .needsDownload {
                return Status(GenerationStrings.translationStatusNeedsLanguages, tone: .pending)
            }
            return Status(GenerationStrings.translationOff, tone: .idle)
        }
    }

    /// Keeps the chosen speech language visible even if system availability has changed.
    var sourceChoices: [Choice] {
        languageChoices(languages?.sources ?? [], selected: repository.translationLanguages.source)
    }

    /// Keeps the chosen subtitle language visible even if system availability has changed.
    var targetChoices: [Choice] {
        languageChoices(languages?.targets ?? [], selected: repository.translationLanguages.target)
    }

    /// Shows language configuration when a microphone is selected.
    var showsTranslationOptions: Bool {
        let id = repository.microphoneID
        return !id.isEmpty && id != GenerationRepository.disabledMicrophoneID
    }

    /// Prevents a language change from interrupting capture or a language download.
    var canChangeLanguages: Bool {
        languages != nil && repository.translationState == .off && !repository.isDownloadingTranslationResources
    }

    /// Leaves Stop available during capture and download, and verifies prerequisites for Start.
    var canToggle: Bool {
        repository.translationState != .off || repository.canStartTranslation
    }

    /// Lists the required languages and shows progress where macOS reports it.
    func resourceRow(
        for kind: MicrophoneTranslation.ResourceKind
    ) -> ResourceRow {
        let pair = repository.translationLanguages
        let isSpeech = kind == .recognition
        let source = languageName(pair.source)
        let language = isSpeech
            ? GenerationStrings.translationSpeechLanguage(source)
            : GenerationStrings.translationPackDirection(
                from: source,
                to: languageName(pair.target)
            )
        let status = repository.translationResources[kind]
        let statusTitle: String?
        switch status {
        case .installed: statusTitle = GenerationStrings.translationResourcesReady
        case .needsDownload: statusTitle = nil
        case .downloading(let percent):
            statusTitle = percent.map { GenerationStrings.translationResourceProgress(percent: $0) }
                ?? GenerationStrings.translationResourceDownloading
        case .failed: statusTitle = GenerationStrings.translationResourceFailed
        case .unavailable: statusTitle = GenerationStrings.translationResourcesUnavailable
        case nil: statusTitle = GenerationStrings.translationResourcesChecking
        }
        let actionTitle: String?
        switch status {
        case .needsDownload: actionTitle = GenerationStrings.translationDownloadResource
        case .failed: actionTitle = GenerationStrings.translationRetryDownload
        default: actionTitle = nil
        }
        return ResourceRow(
            language: language,
            status: status,
            statusTitle: statusTitle,
            actionTitle: actionTitle,
            isActionEnabled: repository.canDownloadTranslationResource(kind)
        )
    }

    /// Loads the picker choices once per presentation and reports when they change.
    func loadLanguagesIfNeeded() async -> Bool {
        guard languages == nil, GenerationRepository.supportsTranslation else { return false }
        let choices = await MicrophoneTranslation.availableLanguages()
        guard !Task.isCancelled else { return false }
        languages = choices
        return true
    }

    /// Uses the edition locale for both menu and language-pack names.
    private func languageName(
        _ identifier: String
    ) -> String {
        Localization.locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Gives language names in the edition's interface language.
    private func languageChoices(
        _ options: [String],
        selected: String
    ) -> [Choice] {
        Set(options + [selected]).map { id in
            Choice(id: id, title: languageName(id))
        }.sorted {
            let order = $0.title.compare($1.title, locale: Localization.locale)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
