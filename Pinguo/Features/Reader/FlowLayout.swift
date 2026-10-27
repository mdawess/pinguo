import SwiftUI

/// Wraps word cells like running text. Punctuation never starts a line (kinsoku), it hangs on the previous one.
struct FlowLayout: Layout {
    var lineSpacing: CGFloat

    struct KeepsWithPrevious: LayoutValueKey {
        static let defaultValue = false
    }

    private struct Placement {
        var origin: CGPoint
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (placements, size) = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        _ = placements
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (placements, _) = arrange(subviews, maxWidth: bounds.width)
        for (subview, placement) in zip(subviews, placements) {
            subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> ([Placement], CGSize) {
        var placements: [Placement] = []
        placements.reserveCapacity(subviews.count)
        var rowStart = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        func finishRow(upTo end: Int) {
            for index in rowStart..<end {
                placements[index].origin.y = y + rowHeight - placements[index].size.height
            }
        }

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let keepsWithPrevious = subview[KeepsWithPrevious.self]
            if x > 0, x + size.width > maxWidth, !keepsWithPrevious {
                finishRow(upTo: index)
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
                rowStart = index
            }
            placements.append(Placement(origin: CGPoint(x: x, y: y), size: size))
            x += size.width
            widest = max(widest, x)
            rowHeight = max(rowHeight, size.height)
        }
        finishRow(upTo: subviews.count)
        return (placements, CGSize(width: widest, height: y + rowHeight))
    }
}
