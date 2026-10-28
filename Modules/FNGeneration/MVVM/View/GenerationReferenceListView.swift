//
//  GenerationReferenceListView.swift
//  XmaxCamera
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AppKit

/// Only changes to item identity reload the collection; toolbar and statistics updates preserve cells.
final class GenerationReferenceListView: Canvas, NSCollectionViewDataSource, NSCollectionViewDelegate {

    /// The reference-grid scroll container retained across session statistics updates.
    private lazy var scroll: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = true
        view.scrollerStyle = .overlay
        return view
    }()

    /// The reusable reference grid whose identity remains stable while scrolling.
    private lazy var collection: NSCollectionView = {
        let view = NSCollectionView()
        view.backgroundColors = [.clear]
        view.collectionViewLayout = GenerationReferenceLayout()
        view.dataSource = self
        view.delegate = self
        view.isSelectable = false
        view.register(
            GenerationReferenceItem.self,
            forItemWithIdentifier: itemID
        )
        return view
    }()

    /// The native reuse identifier for reference collection items.
    private let itemID = NSUserInterfaceItemIdentifier("FNGenerationReferenceItem")

    /// The uploaded and built-in references currently displayed by the grid.
    private var references: [GenerationReference] = []

    /// The identity of the currently selected reference, when one exists.
    private var selectedID: String?

    /// Whether reference selection and upload actions are currently permitted.
    private var enabled = true

    /// Requests the host workspace's native reference-image importer.
    var onUpload: (() -> Void)?

    /// Requests generation with the selected existing reference.
    var onSelect: ((GenerationReference) -> Void)?

    /// Creates the reusable native grid and its reference layout.
    override init(
        color: NSColor = .clear,
        radius: CGFloat = 0
    ) {
        super.init(
            color: color,
            radius: radius
        )
        scroll.documentView = collection
        addSubview(scroll)
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Places the current reference content within the host-provided bounds.
    override func layout() {
        super.layout()
        scroll.frame = bounds
        let width = scroll.contentSize.width
        let columns = max(1, Int((width + 14) / 90))
        let rows = (references.count + 1 + columns - 1) / columns
        let size = NSSize(
            width: width,
            height: max(scroll.contentSize.height, CGFloat(rows) * 98 - 14)
        )
        if collection.frame.size != size {
            collection.setFrameSize(size)
            collection.collectionViewLayout?.invalidateLayout()
        }
    }

    /// Applies item identities and selection state while preserving cells when possible.
    func update(
        references: [GenerationReference],
        selectedID: String?,
        enabled: Bool,
        dimmed: Bool
    ) {
        let changed = self.references.map(\.id) != references.map(\.id)
        self.references = references
        self.selectedID = selectedID
        self.enabled = enabled
        alphaValue = dimmed ? 0.35 : 1
        if changed {
            collection.reloadData()
            needsLayout = true
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        } else {
            for path in collection.indexPathsForVisibleItems() {
                if let item = collection.item(at: path) as? GenerationReferenceItem {
                    configure(
                        item,
                        at: path
                    )
                }
            }
        }
    }

    /// Cancels pending requests for currently visible reference thumbnails.
    func suspendImages() {
        for item in collection.visibleItems() { (item as? GenerationReferenceItem)?.button.thumbnail.cancel() }
    }

    /// Returns the reference count including the upload action.
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int { references.count + 1 }

    /// Dequeues and configures the reusable reference cell at the requested index.
    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item =
            collectionView.makeItem(
                withIdentifier: itemID,
                for: indexPath
            ) as! GenerationReferenceItem
        configure(
            item,
            at: indexPath
        )
        return item
    }

    /// Applies the current reference, selection, or availability without unnecessary image reloads.
    private func configure(
        _ item: GenerationReferenceItem,
        at path: IndexPath
    ) {
        let reference = path.item == 0 ? nil : references[path.item - 1]
        item.button.configure(
            reference,
            selected: reference?.id == selectedID && selectedID != nil,
            enabled: enabled
        )
        item.button.onClick = { [weak self] in
            guard let self, self.enabled else { return }
            if let reference { self.onSelect?(reference) } else { self.onUpload?() }
        }
    }
}
