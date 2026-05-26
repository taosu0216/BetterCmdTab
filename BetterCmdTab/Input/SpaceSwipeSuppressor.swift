import AppKit
import CoreGraphics
import os

/// Experimental companion to `SwipeTrigger`: while the three-finger switcher
/// swipe is enabled, this swallows the system's horizontal "swipe between
/// Spaces" gesture so a three-finger slide drives only the switcher and never
/// also slides Spaces underneath it.
///
/// A session-level `CGEventTap` (the same public mechanism as the hotkey tap)
/// watches the private CGS gesture event stream and returns `nil` for the
/// horizontal dock-swipe (`kIOHIDEventTypeDockSwipe`), which suppresses it
/// before the Dock acts. Vertical dock swipes (Mission Control / App Exposé)
/// are left untouched. The event types and field ids are undocumented — that's
/// why this lives behind the off-by-default Experimental swipe toggle.
final class SpaceSwipeSuppressor {

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    /// Undocumented CGS gesture event types and fields (from the IOHID/CGS
    /// private headers; same constants InstantSpaceSwitcher uses).
    private enum CGS {
        static let eventGesture: UInt32 = 29        // kCGSEventGesture
        static let eventDockControl: UInt32 = 30    // kCGSEventDockControl
        static let fieldHIDType: UInt32 = 110       // kCGEventGestureHIDType
        static let fieldSwipeMotion: UInt32 = 123   // kCGEventGestureSwipeMotion
        static let hidDockSwipe: Int64 = 23         // kIOHIDEventTypeDockSwipe
        static let motionHorizontal: Int64 = 1      // kCGGestureMotionHorizontal
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { install() } else { uninstall() }
    }

    private func install() {
        guard tap == nil else { return }

        let mask: CGEventMask =
            (1 << UInt64(CGS.eventGesture)) | (1 << UInt64(CGS.eventDockControl))
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<SpaceSwipeSuppressor>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: opaqueSelf
        ) else {
            Log.priv.error("Space-swipe suppressor tap failed to create")
            return
        }

        let src = CFMachPortCreateRunLoopSource(nil, port, 0)
        tap = port
        runLoopSource = src
        CGEvent.tapEnable(tap: port, enable: true)

        // Run on a dedicated thread so main-thread stalls can't trip the tap's
        // watchdog (same rationale as HotkeyTap).
        let started = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, src, .commonModes)
            self?.tapRunLoop = loop
            started.signal()
            CFRunLoopRun()
        }
        thread.name = "pro.bettercmdtab.SpaceSwipeSuppressor"
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
        tapThread = thread
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if the watchdog or a user-input burst disabled the tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let hidType = event.getIntegerValueField(field(CGS.fieldHIDType))
        guard hidType == CGS.hidDockSwipe else { return Unmanaged.passUnretained(event) }

        // Suppress only *real* trackpad swipes (posted by the HID kernel, source
        // pid 0). Our own instant-Space-switch synthetic swipe carries this
        // process's pid — let it through, or this tap would eat it and the
        // jump-to-Space would silently fail whenever the swipe trigger is on.
        if event.getIntegerValueField(.eventSourceUnixProcessID) != 0 {
            return Unmanaged.passUnretained(event)
        }

        // Suppress only the horizontal Space swipe; pass vertical dock swipes
        // (Mission Control / App Exposé) through untouched.
        let motion = event.getIntegerValueField(field(CGS.fieldSwipeMotion))
        if motion == CGS.motionHorizontal {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// `CGEventField` is a `uint32_t`-backed enum; the gesture field ids aren't
    /// declared cases, so bit-cast the raw value to address them.
    private func field(_ raw: UInt32) -> CGEventField {
        unsafeBitCast(raw, to: CGEventField.self)
    }

    func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop = tapRunLoop {
            if let runLoopSource {
                CFRunLoopRemoveSource(loop, runLoopSource, .commonModes)
            }
            CFRunLoopStop(loop)
        }
        tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
    }

    deinit {
        uninstall()
    }
}
