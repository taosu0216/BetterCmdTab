import Darwin
import Foundation

/// Best-effort restoration of the WindowServer symbolic hotkeys (⌘Tab, ⌘⇧Tab,
/// ⌘`) that we disable at runtime via `PrivateAPI.setSymbolicHotKey`.
///
/// That disable **persists after the process dies** (see `PrivateAPI`), so if we
/// crash or are signalled before `SwitcherController.shutdown()` runs, the user's
/// native ⌘Tab stays dead system-wide until reboot or our next launch. This
/// installs signal + `atexit` handlers that re-enable whatever we last disabled.
///
/// SIGKILL and a hard power loss cannot be caught — those are covered by the
/// unconditional startup self-heal in `SwitcherController.start()`, which clears
/// any stale disable on the next launch.
///
/// The handler path is deliberately minimal: it only reads a pre-allocated C
/// buffer and calls a dlsym'd C function pointer, so it allocates nothing and
/// touches no Swift runtime machinery that would be unsafe from a signal context.
enum SymbolicHotkeyGuard {
    /// Max managed keys: ⌘Tab, ⌘⇧Tab, ⌘`. A `0` slot means "empty".
    private static let capacity = 3

    /// Pre-allocated, never freed: the signal handler reads these slots without
    /// allocating. Initialized to all-zero.
    private static let slots: UnsafeMutablePointer<Int32> = {
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: capacity)
        p.initialize(repeating: 0, count: capacity)
        return p
    }()

    // dlsym'd `CGSSetSymbolicHotKeyEnabled` — resolved once up front so the
    // signal handler only does a plain C call (no dlopen/dlsym in-handler).
    private typealias SetEnabledFn = @convention(c) (Int32, Bool) -> Int32
    private static let setEnabledFn: SetEnabledFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let sym = dlsym(h, "CGSSetSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(sym, to: SetEnabledFn.self)
    }()

    private static var installed = false

    /// Record the raw symbolic-hotkey ids currently disabled, so the signal /
    /// atexit handlers know what to restore. Call on every change to the
    /// disabled set (disable *and* the empty set on clean re-enable).
    static func setDisabled(_ rawIds: [Int32]) {
        for i in 0..<capacity {
            slots[i] = i < rawIds.count ? rawIds[i] : 0
        }
    }

    /// Re-enable every recorded slot. Async-signal best-effort.
    private static func restore() {
        guard let fn = setEnabledFn else { return }
        for i in 0..<capacity where slots[i] != 0 {
            _ = fn(slots[i], true)
        }
    }

    /// Install the signal + `atexit` handlers once. Idempotent. Call early in
    /// app startup, before any symbolic hotkey gets disabled.
    static func install() {
        guard !installed else { return }
        installed = true
        // Force lazy init of the buffer + function pointer now, off the handler
        // path — neither may safely initialize inside a signal handler.
        _ = slots
        _ = setEnabledFn

        atexit { SymbolicHotkeyGuard.restore() }

        // Catch the terminations we can: graceful (TERM/INT/HUP) and the common
        // crash signals (ABRT/SEGV/...). Restore, then re-raise the default
        // action so the process still dies / dumps as it normally would.
        let sigs: [Int32] = [SIGTERM, SIGINT, SIGHUP, SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE]
        for s in sigs {
            signal(s) { sig in
                SymbolicHotkeyGuard.restore()
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
    }
}
