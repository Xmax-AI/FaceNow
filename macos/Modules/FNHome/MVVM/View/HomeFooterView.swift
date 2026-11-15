//
//  HomeFooterView.swift
//  FaceNow
//

import AppKit
import Factory
import SnapKit

/// Displays the app version and project links at the bottom of the home page.
@MainActor
final class HomeFooterView: Canvas {

    private static let itemSpacing: CGFloat = 40

    @Injected(\.homeRepo) private var homeRepo: HomeRepository

    /// Opens the platform for the current edition.
    private lazy var platform: Button = {
        let view = Button(
            HomeStrings.homeAPIPlatform,
            style: .plain
        )
        view.onClick = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.homeRepo.platformURL)
        }
        return view
    }()

    /// Opens the public FaceNow repository.
    private lazy var github: Button = {
        let view = Button(
            "GitHub",
            style: .plain
        )
        view.onClick = { NSWorkspace.shared.open(NetworkEnvironment.sourceRepositoryURL) }
        return view
    }()

    /// Uses the native system font for the public version.
    private lazy var version: NSTextField = {
        let view = makeLabel(
            HomeStrings.version(homeRepo.appVersion),
            color: Palette.secondary
        )
        view.font = .systemFont(
            ofSize: platform.font?.pointSize ?? 13,
            weight: .regular
        )
        return view
    }()

    /// Composes the trailing row.
    init() {
        super.init()
        [version, github, platform].forEach(addSubview)
        configureLayout()
    }

    /// Storyboard decoding is unsupported for this programmatic view.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Aligns the controls in reading order along the trailing edge.
    private func configureLayout() {
        platform.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(56)
            make.width.equalTo(platform.preferredWidth)
            make.height.equalTo(26)
        }
        github.snp.makeConstraints { make in
            make.trailing.equalTo(platform.snp.leading).offset(-Self.itemSpacing)
            make.centerY.height.equalTo(platform)
            make.width.equalTo(github.preferredWidth)
        }
        version.snp.makeConstraints { make in
            make.trailing.equalTo(github.snp.leading).offset(-Self.itemSpacing)
            make.centerY.equalTo(platform)
        }
    }
}
