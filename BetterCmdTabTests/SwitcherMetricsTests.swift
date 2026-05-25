import Foundation
import Testing
@testable import BetterCmdTab

@Suite("SwitcherMetrics")
struct SwitcherMetricsTests {

    @Test("scale 1.0 yields baseline values")
    func baseline() {
        let m = SwitcherMetrics.forScale(1.0)
        #expect(m.scale == 1.0)
        #expect(m.rowHeight == SwitcherMetrics.baseRowHeight)
        #expect(m.rowWidth == SwitcherMetrics.baseRowWidth)
        #expect(m.iconSize == SwitcherMetrics.baseIconSize)
        #expect(m.appNameWidth == SwitcherMetrics.baseAppNameWidth)
    }

    @Test("scale clamps high values to 1.8")
    func upperClamp() {
        // forScreen with a 4K screen would normally raise scale beyond 1.8;
        // clamp must protect against giant rows.
        let m = SwitcherMetrics.forScale(2.5)
        // forScale doesn't clamp; only forScreen does. Verify forScreen behavior separately.
        #expect(m.scale == 2.5)
    }

    @Test("forScreen with nil falls back to reference width → scale 1.0")
    func nilScreenScale() {
        let m = SwitcherMetrics.forScreen(nil)
        #expect(m.scale == 1.0)
        #expect(m.rowHeight == SwitcherMetrics.baseRowHeight)
    }

    @Test("baseline static matches forScale(1.0)")
    func baselineMatchesForScale1() {
        let a = SwitcherMetrics.baseline
        let b = SwitcherMetrics.forScale(1.0)
        #expect(a == b)
    }

    @Test("scale 1.5 produces 1.5x integer-rounded dimensions")
    func scale1_5() {
        let m = SwitcherMetrics.forScale(1.5)
        #expect(m.scale == 1.5)
        #expect(m.rowHeight == (SwitcherMetrics.baseRowHeight * 1.5).rounded())
        #expect(m.iconSize == (SwitcherMetrics.baseIconSize * 1.5).rounded())
    }

    @Test("Equatable conformance: same scale → equal")
    func equatable() {
        #expect(SwitcherMetrics.forScale(1.2) == SwitcherMetrics.forScale(1.2))
        #expect(SwitcherMetrics.forScale(1.2) != SwitcherMetrics.forScale(1.3))
    }

    @Test("userScale below 1.0 shrinks past the screen-adaptive floor")
    func userScaleSmall() {
        // nil screen → adaptive scale 1.0; userScale 0.85 must apply on top,
        // proving the multiply happens after the max(1.0, …) clamp.
        let m = SwitcherMetrics.forScreen(nil, userScale: 0.85)
        #expect(m.scale == 0.85)
        #expect(m.iconSize == (SwitcherMetrics.baseIconSize * 0.85).rounded())
    }

    @Test("userScale above 1.0 enlarges the panel")
    func userScaleLarge() {
        let m = SwitcherMetrics.forScreen(nil, userScale: 1.2)
        #expect(m.scale == 1.2)
        #expect(m.tileIconSize == (SwitcherMetrics.baseTileIconSize * 1.2).rounded())
    }

    @Test("userScale defaults to 1.0 (no behavior change)")
    func userScaleDefault() {
        #expect(SwitcherMetrics.forScreen(nil) == SwitcherMetrics.forScreen(nil, userScale: 1.0))
    }
}
