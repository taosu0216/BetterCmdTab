import CoreGraphics
import Foundation

/// Pure screen-picking geometry, split out from `NSScreen` so it is unit
/// testable without a live WindowServer. All rects share one coordinate space
/// (Cocoa, bottom-left origin) supplied by the caller.
enum ScreenSelection {

    /// Index of the screen frame with the greatest area of overlap with `rect`.
    /// Returns nil when `screenFrames` is empty or nothing overlaps `rect`.
    static func indexOfMaxOverlap(rect: CGRect, screenFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (i, frame) in screenFrames.enumerated() {
            let inter = frame.intersection(rect)
            guard !inter.isNull else { continue }
            let area = max(0, inter.width) * max(0, inter.height)
            guard area > 0 else { continue }
            if best == nil || area > best!.area { best = (i, area) }
        }
        return best?.index
    }

    /// Index of the "Main display" — the screen whose frame origin is (0, 0),
    /// matching System Settings → Displays. Returns nil when none is at origin.
    static func mainDisplayIndex(screenFrames: [CGRect]) -> Int? {
        screenFrames.firstIndex { $0.origin == .zero }
    }

    /// Flip a rect from Accessibility coordinates (top-left origin of the primary
    /// display, y-down) into Cocoa coordinates (bottom-left origin, y-up).
    /// `primaryMaxY` is the primary ("Main display") height — pass the origin-zero
    /// screen's `frame.maxY`, which equals its height since its `minY` is 0. Both
    /// spaces are anchored to that screen's corner, so this one flip is correct
    /// for windows on every display — including secondaries above/below (Cocoa y
    /// past the primary's range) or to the left (negative x, carried unchanged).
    static func cocoaRect(forAXBounds ax: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: ax.minX,
            y: primaryMaxY - ax.minY - ax.height,
            width: ax.width,
            height: ax.height
        )
    }
}
