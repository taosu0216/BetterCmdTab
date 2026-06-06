import CoreGraphics
import Foundation
import Testing
@testable import BetterCmdTab

@Suite("ScreenSelection")
struct ScreenSelectionTests {

    // Two side-by-side 1000x1000 displays: A at origin, B to its right.
    private let screenA = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    private let screenB = CGRect(x: 1000, y: 0, width: 1000, height: 1000)

    @Test("window fully on the second screen picks that screen")
    func fullyOnSecond() {
        let win = CGRect(x: 1200, y: 200, width: 400, height: 300)
        #expect(ScreenSelection.indexOfMaxOverlap(rect: win, screenFrames: [screenA, screenB]) == 1)
    }

    @Test("straddling window picks the screen with the larger overlap")
    func straddlePicksLargerOverlap() {
        // 600 wide window from x=800: 200pt on A (800..1000), 400pt on B (1000..1400).
        let win = CGRect(x: 800, y: 200, width: 600, height: 300)
        #expect(ScreenSelection.indexOfMaxOverlap(rect: win, screenFrames: [screenA, screenB]) == 1)
    }

    @Test("window matching no screen returns nil")
    func noOverlapIsNil() {
        let win = CGRect(x: 5000, y: 5000, width: 100, height: 100)
        #expect(ScreenSelection.indexOfMaxOverlap(rect: win, screenFrames: [screenA, screenB]) == nil)
    }

    @Test("empty screen list returns nil")
    func emptyScreensIsNil() {
        #expect(ScreenSelection.indexOfMaxOverlap(rect: screenA, screenFrames: []) == nil)
    }

    @Test("main display is the origin-zero screen regardless of array order")
    func mainDisplayIsOriginZero() {
        // B (non-zero origin) listed first; A (origin zero) second.
        #expect(ScreenSelection.mainDisplayIndex(screenFrames: [screenB, screenA]) == 1)
    }

    @Test("main display nil when no screen sits at the origin")
    func mainDisplayNilWhenNoOrigin() {
        let offset = CGRect(x: 10, y: 10, width: 1000, height: 1000)
        #expect(ScreenSelection.mainDisplayIndex(screenFrames: [screenB, offset]) == nil)
    }
}
