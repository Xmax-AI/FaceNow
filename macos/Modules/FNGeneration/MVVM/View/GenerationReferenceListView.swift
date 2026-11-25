//
//  GenerationReferenceListView.swift
//  FaceNow
//

import AppKit
import QuartzCore
import SnapKit

/// Only changes to item identity reload the collection; toolbar and statistics updates preserve cells.
final class GenerationReferenceListView: Canvas, NSCollectionViewDataSource, NSCollectionViewDelegate {

    /// The diameter of a home reference avatar in points.
    static let singleRowAvatarSize: CGFloat = 52

    /// The strip height in points, including vertical padding.
    static let singleRowHeight = singleRowAvatarSize + 4

    /// The collection cell bounds used to measure a complete avatar.
    private static let rowItemSize = NSSize(width: singleRowHeight, height: singleRowAvatarSize)

    /// The horizontal space between adjacent collection cells, in points.
    private static let rowSpacing: CGFloat = 8

    /// Whether the list uses the horizontal home layout.
    private let singleRow: Bool

    /// Indicates when more references can be reached by scrolling.
    private lazy var scrollEdgeMask: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }()

    /// The reference-grid scroll container retained across session statistics updates.
    private lazy var scroll: NSScrollView = {
        let view: NSScrollView = singleRow ? ReferenceStripScrollView() : NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = !singleRow
        view.scrollerStyle = .overlay
        return view
    }()

    /// The reusable reference grid whose identity remains stable while scrolling.
    private lazy var collection: NSCollectionView = {
        let view = NSCollectionView()
        view.backgroundColors = [.clear]
        if singleRow {
            let layout = NSCollectionViewFlowLayout()
            layout.scrollDirection = .horizontal
            layout.itemSize = Self.rowItemSize
            layout.minimumLineSpacing = Self.rowSpacing
            layout.sectionInset = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
            view.collectionViewLayout = layout
        } else {
            view.collectionViewLayout = GenerationReferenceLayout()
        }
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

    /// The number of cells, including the grid's upload control.
    private var itemCount: Int { references.count + (singleRow ? 0 : 1) }

    /// The identity of the currently selected reference, when one exists.
    private var selectedID: String?

    /// Whether reference selection and upload actions are currently permitted.
    private var enabled = true

    /// Requests the host workspace's native reference-image importer.
    var onUpload: (() -> Void)?

    /// Requests generation with the selected existing reference.
    var onSelect: ((GenerationReference) -> Void)?

    /// Lets a hosting modal keep keyboard navigation inside its currently visible reference controls.
    var focusControls: [NSView] {
        collection.indexPathsForVisibleItems().sorted { $0.item < $1.item }.compactMap {
            (collection.item(at: $0) as? GenerationReferenceItem)?.button
        }
    }

    /// Measures the strip width for a whole number of cells.
    static func singleRowWidth(
        itemCount: Int
    ) -> CGFloat {
        CGFloat(itemCount) * rowItemSize.width + CGFloat(max(0, itemCount - 1)) * rowSpacing
    }

    /// Creates the reference grid or the compact strip used on the homepage.
    init(
        singleRow: Bool = false
    ) {
        self.singleRow = singleRow
        super.init()
        scroll.documentView = collection
        addSubview(scroll)
        scroll.snp.makeConstraints { make in make.edges.equalToSuperview() }
        collection.snp.makeConstraints { make in
            make.leading.top.equalTo(scroll.contentView)
            if singleRow {
                make.width.greaterThanOrEqualTo(scroll.contentView)
                make.width.equalTo(0).priority(490)
                make.height.equalTo(scroll.contentView)
            } else {
                make.width.equalTo(scroll.contentView)
                make.height.equalTo(0).priority(490)
            }
        }
        if singleRow {
            let clipView = scroll.contentView
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateScrollEdgeFade),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
    }

    /// Storyboard decoding is unsupported for this programmatic component.
    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Places the current reference content within the host-provided bounds.
    override func layout() {
        super.layout()
        if singleRow {
            updateScrollEdgeFade()
            return
        }
        let width = scroll.contentSize.width
        let columns = max(1, Int((width + 14) / 90))
        let rows = (itemCount + columns - 1) / columns
        let size = NSSize(
            width: width,
            height: max(scroll.contentSize.height, CGFloat(rows) * 98 - 14)
        )
        if collection.frame.size != size {
            collection.snp.updateConstraints { make in make.height.equalTo(size.height).priority(490) }
            collection.collectionViewLayout?.invalidateLayout()
        }
    }

    /// Fades only the edges that have more avatars outside the viewport.
    @objc private func updateScrollEdgeFade() {
        let visible = scroll.contentView.bounds
        guard visible.width > 0, let layer else { return }
        let fadeLeading = visible.minX > 0.5
        let fadeTrailing = visible.maxX < Self.singleRowWidth(itemCount: itemCount) - 0.5
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if fadeLeading || fadeTrailing {
            let fraction = min(0.5, 50 / visible.width)
            let fadedEdge = NSColor.black.withAlphaComponent(0.2).cgColor
            scrollEdgeMask.frame = bounds
            scrollEdgeMask.locations = [0, NSNumber(value: Double(fraction)), NSNumber(value: Double(1 - fraction)), 1]
            scrollEdgeMask.colors = [
                fadeLeading ? fadedEdge : NSColor.black.cgColor,
                NSColor.black.cgColor,
                NSColor.black.cgColor,
                fadeTrailing ? fadedEdge : NSColor.black.cgColor,
            ]
            layer.mask = scrollEdgeMask
        } else {
            layer.mask = nil
        }
        CATransaction.commit()
    }

    /// Applies item identities and selection state while preserving cells when possible.
    func update(
        references: [GenerationReference],
        selectedID: String?,
        enabled: Bool,
        dimmed: Bool,
        resetScroll: Bool = false
    ) {
        let changed = self.references.map(\.id) != references.map(\.id)
        self.references = references
        self.selectedID = selectedID
        self.enabled = enabled
        ControlMotion.setOpacity(
            dimmed ? 0.35 : 1,
            on: self
        )
        if changed {
            if singleRow {
                collection.snp.updateConstraints { make in
                    make.width.equalTo(Self.singleRowWidth(itemCount: itemCount)).priority(490)
                }
            }
            collection.reloadData()
            needsLayout = true
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
        if changed || resetScroll {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// Cancels pending requests for currently visible reference thumbnails.
    func suspendImages() {
        for item in collection.visibleItems() { (item as? GenerationReferenceItem)?.button.thumbnail.cancel() }
    }

    /// Includes the upload cell in the workspace grid.
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int { itemCount }

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
        let referenceIndex = path.item - (singleRow ? 0 : 1)
        let reference = referenceIndex >= 0 ? references[referenceIndex] : nil
        item.button.compactThumbnailSize = singleRow ? Self.singleRowAvatarSize : nil
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

/// Supports horizontal scrolling without displaying a scroller over the avatars.
private final class ReferenceStripScrollView: NSScrollView, NSGestureRecognizerDelegate {

    /// Whether references extend past the current viewport.
    private var canScrollHorizontally: Bool {
        (documentView?.frame.width ?? 0) > contentView.bounds.width
    }

    /// Prevents the collection view from enabling a scroller when it lays out its items.
    override var hasHorizontalScroller: Bool {
        get { super.hasHorizontalScroller }
        set { super.hasHorizontalScroller = false }
    }

    override init(
        frame frameRect: NSRect
    ) {
        super.init(frame: frameRect)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(scrollByDragging(_:)))
        pan.delegate = self
        pan.delaysPrimaryMouseButtonEvents = true
        addGestureRecognizer(pan)
    }

    required init?(
        coder: NSCoder
    ) { fatalError("init(coder:) has not been implemented") }

    /// Routes empty space between avatars to the scroll view's drag gesture.
    override func hitTest(
        _ point: NSPoint
    ) -> NSView? {
        guard let target = super.hitTest(point) else { return nil }
        return target === documentView ? self : target
    }

    /// Accepts a drag on an inactive window's reference strip.
    override func acceptsFirstMouse(
        for event: NSEvent?
    ) -> Bool { true }

    /// Handles horizontal scrolling and forwards other wheel events to AppKit.
    override func scrollWheel(
        with event: NSEvent
    ) {
        let horizontalDelta = event.scrollingDeltaX
        guard horizontalDelta != 0, abs(horizontalDelta) >= abs(event.scrollingDeltaY), canScrollHorizontally
        else {
            super.scrollWheel(with: event)
            return
        }
        let distance = event.hasPreciseScrollingDeltas ? horizontalDelta : horizontalDelta * horizontalLineScroll
        scrollHorizontally(by: distance)
    }

    /// Keeps native click tracking when the list has no overflow to drag through.
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: NSGestureRecognizer
    ) -> Bool { canScrollHorizontally }

    /// Pans the strip while the primary mouse button is held.
    @objc private func scrollByDragging(
        _ pan: NSPanGestureRecognizer
    ) {
        guard pan.state == .began || pan.state == .changed || pan.state == .ended else { return }
        scrollHorizontally(by: pan.translation(in: self).x)
        pan.setTranslation(.zero, in: self)
    }

    /// Clamps the horizontal offset and refreshes the clip view.
    private func scrollHorizontally(
        by distance: CGFloat
    ) {
        let visible = contentView.bounds.offsetBy(dx: -distance, dy: 0)
        contentView.scroll(to: contentView.constrainBoundsRect(visible).origin)
        reflectScrolledClipView(contentView)
    }
}
