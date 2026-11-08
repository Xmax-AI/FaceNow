//
//  GenerationReferenceLayout.swift
//  FaceNow
//

import AppKit

/// Centers incomplete rows using the same dimensions as the Web reference grid.
final class GenerationReferenceLayout: NSCollectionViewLayout {

    /// The precomputed frames for the current collection width and item count.
    private var attributes: [NSCollectionViewLayoutAttributes] = []

    /// The complete reference-grid content size for the current preparation pass.
    private var size = NSSize.zero

    /// The grid size produced by the latest layout preparation.
    override var collectionViewContentSize: NSSize { size }

    /// Computes centered rows for the current reference count and available width.
    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let width = collectionView.bounds.width
        let count = collectionView.numberOfItems(inSection: 0)
        let columns = max(1, Int((width + 14) / 90))
        let rows = (count + columns - 1) / columns
        size = NSSize(
            width: width,
            height: max(1, CGFloat(rows) * 98 - 14)
        )
        attributes = (0..<count).map { index in
            let row = index / columns, rowCount = min(columns, count - row * columns)
            let rowWidth = CGFloat(rowCount) * 90 - 14
            let item = NSCollectionViewLayoutAttributes(
                forItemWith: IndexPath(
                    item: index,
                    section: 0
                )
            )
            item.frame = NSRect(
                x: (width - rowWidth) / 2 + CGFloat(index % columns) * 90,
                y: CGFloat(row) * 98,
                width: 76,
                height: 84
            )
            return item
        }
    }

    /// Requests new item frames when the collection width changes.
    override func shouldInvalidateLayout(
        forBoundsChange newBounds: NSRect
    ) -> Bool { newBounds.width != size.width }

    /// Returns the prepared reference cells intersecting the requested rectangle.
    override func layoutAttributesForElements(
        in rect: NSRect
    ) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter { $0.frame.intersects(rect) }
    }

    /// Returns one prepared cell frame when its index remains valid.
    override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
    }
}
