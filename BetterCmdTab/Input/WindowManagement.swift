import AppKit
import BetterShortcuts

/// Wires the window-management hotkeys (#7) as global BetterShortcuts hotkeys so
/// they work whether or not the switcher is open:
///
/// - **Switcher closed:** these `onKeyDown` handlers fire and arrange the
///   *frontmost app's focused window*.
/// - **Switcher open:** the CGEvent tap in `HotkeyTap` matches the same chord
///   first (it intercepts keys while switching) and arranges the *highlighted*
///   window via `SwitcherController`, consuming the event so these global
///   handlers don't also fire. The tap's chord map is derived from the same
///   BetterShortcuts bindings (see `SwitcherController.pushWindowMgmtBindings`),
///   so there's a single source of truth.
///
/// Handlers are installed once at launch; they read the live binding through
/// BetterShortcuts, so changing a shortcut takes effect without re-registering.
@MainActor
enum WindowManagement {
    static func installHandlers() {
        for (name, arrangement) in arrangementByName {
            BetterShortcuts.onKeyDown(for: name) {
                MainActor.assumeIsolated {
                    Activator.arrangeFrontmostWindow(arrangement)
                }
            }
        }
    }

    /// Map each window-management shortcut name to the arrangement it performs.
    private static var arrangementByName: [(BetterShortcuts.Name, WindowArrangement)] {
        [
            (.windowTileLeft, .tileLeftHalf),
            (.windowTileRight, .tileRightHalf),
            (.windowMaximize, .maximize),
            (.windowCenter, .center),
        ]
    }
}
