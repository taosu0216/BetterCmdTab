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
}
