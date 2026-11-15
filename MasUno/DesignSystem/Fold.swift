import SwiftUI

// The fold of a partially open iPhone Duo. SwiftUI reports it as a `.division` reserved region
// (iOS 27.1 SDK, Xcode 27). GitHub's runners still have Xcode 26, so CI builds without it and
// `activeFold` is always nil there; see `BarLayoutReader` for the same split.

extension GeometryProxy {
    /// The active fold's frame in this proxy's own space, or nil when the screen is flat (fully
    /// open, folded, or any other iPhone). Read it inside a `GeometryReader` or `onGeometryChange`.
    nonisolated var activeFold: CGRect? {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .division).first(where: \.isActive)?.frame
        }
        #endif
        return nil
    }
}

extension CGRect {
    /// The part of this rect on one side of `fold`: the larger side, or the leading one when they
    /// match, the way system sheets move off the fold. A crease running top to bottom splits it
    /// left and right; one running side to side splits it top and bottom. Returns `self` when the
    /// fold doesn't cross it.
    nonisolated func pane(avoiding fold: CGRect) -> CGRect {
        guard intersects(fold) else { return self }
        if fold.height >= fold.width {
            let leading = CGRect(x: minX, y: minY, width: max(0, fold.minX - minX), height: height)
            let trailing = CGRect(x: fold.maxX, y: minY, width: max(0, maxX - fold.maxX), height: height)
            return leading.width >= trailing.width ? leading : trailing
        } else {
            let top = CGRect(x: minX, y: minY, width: width, height: max(0, fold.minY - minY))
            let bottom = CGRect(x: minX, y: fold.maxY, width: width, height: max(0, maxY - fold.maxY))
            return top.height >= bottom.height ? top : bottom
        }
    }
}
