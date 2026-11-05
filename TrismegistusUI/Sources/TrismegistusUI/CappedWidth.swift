import SwiftUI

/// Its content at its own width up to `max`, wrapped to that width beyond it, and as tall as it then is.
///
/// `.frame(maxWidth:)` under a nil width proposal (a horizontal `ScrollView`, a `Grid` measuring ideal sizes) caps the
/// width but reports the height of the unwrapped line, so a wrapped cell spills into the next row. This measures the
/// height at the capped width.
public struct CappedWidth: Layout {
    let max: CGFloat

    public init(max: CGFloat) { self.max = max }

    private func width(_ subview: LayoutSubview, proposal: ProposedViewSize) -> CGFloat {
        Swift.min(subview.sizeThatFits(.unspecified).width, max, proposal.width ?? .infinity)
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let w = width(subview, proposal: proposal)
        return CGSize(width: w, height: subview.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}
