//
//  GenerationReferenceItem.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// A reusable collection item retaining one reference button and its image request.
final class GenerationReferenceItem: NSCollectionViewItem {

    /// The lazily created button reused with this collection item.
    lazy var button: GenerationReferenceButton = {
        let view = GenerationReferenceButton()
        return view
    }()

    /// Installs the reusable reference button as the item view.
    override func loadView() { view = button }

    /// Clears hover, cancels pending thumbnail work, and removes the previous selection action.
    override func prepareForReuse() {
        super.prepareForReuse()
        button.resetHoverForReuse()
        button.thumbnail.cancel()
        button.onClick = nil
    }
}
