import CoreGraphics
import Testing
@testable import BetterCmdTab

/// Covers the pure decision core of the post-activation focus verify
/// (`Activator.focusSettled`): CGWindowID comparison when both sides resolved
/// one, AX element identity as the fallback when either id is unavailable.
@Suite("Activator focus-settled decision")
struct ActivatorFocusSettledTests {

    @Test("matching window ids settle")
    func matchingWidsSettle() {
        #expect(Activator.focusSettled(targetWid: 42, focusedWid: 42, sameElement: false))
    }

    @Test("differing window ids do not settle")
    func differingWidsDoNotSettle() {
        #expect(!Activator.focusSettled(targetWid: 42, focusedWid: 7, sameElement: false))
    }

    @Test("unresolved focused id falls back to element identity")
    func unresolvedFocusedIdUsesElement() {
        #expect(Activator.focusSettled(targetWid: 42, focusedWid: 0, sameElement: true))
        #expect(!Activator.focusSettled(targetWid: 42, focusedWid: 0, sameElement: false))
    }

    @Test("unresolved target id falls back to element identity")
    func unresolvedTargetIdUsesElement() {
        #expect(Activator.focusSettled(targetWid: 0, focusedWid: 7, sameElement: true))
        #expect(!Activator.focusSettled(targetWid: 0, focusedWid: 7, sameElement: false))
    }

    @Test("nothing resolved and no element match reads as not settled")
    func nothingResolvedNotSettled() {
        #expect(!Activator.focusSettled(targetWid: 0, focusedWid: 0, sameElement: false))
    }
}
