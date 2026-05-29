import AppKit
import ApplicationServices
import Darwin
import Foundation

// Private SPI from libsystem: detaches the spawned child's TCC
// "responsibility" so it acts as its own client (osascript) instead of
// inheriting from us (BetterCmdTab). This is the documented escape hatch
// when an LSUIElement agent can't surface Apple Events TCC prompts — a known
// gap on macOS Tahoe (26). Same symbol that Witch, TabTab, and several other
// shipping switchers use.
@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(_ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32

/// Per-browser tab enumeration + activation via Apple Events. AX scraping is
/// unreliable across Safari/Chromium versions (the tab strip is deeply nested
/// and frequently restructured); the scripting dictionaries every major browser
/// ships are the only stable interface for "list tabs of window N" and "select
/// tab N of window N".
///
/// All three operations (raise window, list tabs, select tab) are bound to the
/// `AppleScript window 1` of the target app. Since we cannot map an AX window
/// to a stable AppleScript window index, we first force the row's window to be
/// the browser's frontmost via `AXRaiseAction` and a brief delay so subsequent
/// scripts read the right window.
enum BrowserTabs {

    /// Result of a tab-enumeration attempt. `failed` distinguishes a script
    /// error (Automation permission denied, timeout) from a browser that simply
    /// has too few tabs to drill — the caller surfaces a hint only for `failed`.
    enum TabsOutcome {
        case notSupported
        case failed
        case tabs([String])
    }

    enum Family {
        case chromium  // Chrome, Brave, Edge, Vivaldi, Opera, Arc, Dia
        case safari    // Safari, Safari Technology Preview

        static func from(bundleID: String?) -> Family? {
            guard let id = bundleID?.lowercased() else { return nil }
            // Chromium family: bundle IDs use a stable AppleScript dictionary
            // identical to Chrome's. Arc and Dia (The Browser Company) also
            // adopt the same dialect.
            let chromiumIDs: Set<String> = [
                "com.google.chrome",
                "com.google.chrome.canary",
                "com.google.chrome.beta",
                "com.google.chrome.dev",
                "com.brave.browser",
                "com.brave.browser.beta",
                "com.brave.browser.nightly",
                "com.brave.browser.dev",
                "com.microsoft.edgemac",
                "com.microsoft.edgemac.beta",
                "com.microsoft.edgemac.dev",
                "com.microsoft.edgemac.canary",
                "com.vivaldi.vivaldi",
                "com.operasoftware.opera",
                "com.operasoftware.operadeveloper",
                "company.thebrowser.browser",
                "company.thebrowser.dia",
                "net.imput.helium",
            ]
            if chromiumIDs.contains(id) { return .chromium }
            if id == "com.apple.safari" || id == "com.apple.safaritechnologypreview" { return .safari }
            return nil
        }
    }

    /// Quote a string for embedding inside an AppleScript string literal.
    /// AppleScript needs `\` and `"` escaped; everything else can stay as-is.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// AppleScript identifier prefix for an app — `application id "com.foo"`.
    /// Using the bundle ID instead of the name avoids localization issues and
    /// is rejected gracefully if the app isn't installed (returns an empty
    /// title list rather than failing the script).
    private static func appLiteral(_ bundleID: String) -> String {
        "application id \"\(escape(bundleID))\""
    }

    /// Force the row's window to be the browser's frontmost window so the
    /// subsequent `window 1` scripts target it. Synchronous AX call, runs on
    /// the caller's queue. Does NOT activate the process — keeps the panel
    /// visible. Skips entirely when the app has only one window: there's no
    /// "wrong window" to raise away from, and the AX call still costs ~10ms
    /// even for a no-op raise.
    private static func raiseInBrowser(_ window: AXUIElement, pid: pid_t) {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.05)
        var windowsValue: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        let windowCount = (windowsValue as? [AXUIElement])?.count ?? 0
        if windowCount <= 1 { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Run an AppleScript. In-process `NSAppleScript` fails silently with
    /// -1743 on LSUIElement agents under macOS Tahoe (no TCC prompt ever
    /// appears, no entry shows up in System Settings → Privacy → Automation).
    /// We sidestep this by spawning `/usr/bin/osascript` with the
    /// `responsibility_spawnattrs_setdisclaim` SPI, which makes the child
    /// process its own TCC responsibility — so the prompt either uses
    /// osascript's pre-existing permission or surfaces correctly under
    /// osascript's name. Stdout is the script's text result, one line per
    /// item separated by ", " (osascript's default list serialization).
    private static func runScript(_ source: String) -> String? {
        var attrs: posix_spawnattr_t?
        guard posix_spawnattr_init(&attrs) == 0 else { return nil }
        defer { posix_spawnattr_destroy(&attrs) }
        _ = responsibility_spawnattrs_setdisclaim(&attrs, 1)

        let outPipe = Pipe()
        let errPipe = Pipe()
        let outFd = outPipe.fileHandleForWriting.fileDescriptor
        let errFd = errPipe.fileHandleForWriting.fileDescriptor
        // Guarantee parent-side write descriptors are released even on the
        // failure paths below. `Pipe` deinit ultimately closes them, but
        // hanging on to them until ARC drains can stack up FDs across a burst
        // of failures (e.g. repeated TCC denials). Tracked by a flag so the
        // success path can close them at exactly the right moment (after
        // spawn, before reading the child's output).
        var parentWriteClosed = false
        func closeParentWriteEnds() {
            guard !parentWriteClosed else { return }
            parentWriteClosed = true
            outPipe.fileHandleForWriting.closeFile()
            errPipe.fileHandleForWriting.closeFile()
        }
        defer { closeParentWriteEnds() }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, outFd, 1)
        posix_spawn_file_actions_adddup2(&actions, errFd, 2)
        posix_spawn_file_actions_addclose(&actions, outFd)
        posix_spawn_file_actions_addclose(&actions, errFd)

        let path = "/usr/bin/osascript"
        let args: [String] = ["osascript", "-e", source]
        let cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { for a in cArgs where a != nil { free(a) } }

        var pid: pid_t = 0
        let status = path.withCString { cPath in
            posix_spawn(&pid, cPath, &actions, &attrs, cArgs, environ)
        }
        guard status == 0 else {
            NSLog("BrowserTabs: posix_spawn osascript failed \(status)")
            return nil
        }
        closeParentWriteEnds()

        var stat: Int32 = 0
        waitpid(pid, &stat, 0)
        let exitCode = (stat & 0xff00) >> 8
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        if exitCode != 0 || !stderr.isEmpty {
            NSLog("BrowserTabs: osascript exit=\(exitCode) stderr=\(stderr)")
        }
        if exitCode != 0 { return nil }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split osascript's list output into items. AppleScript's default text
    /// representation of a list separates items with ", " — split there.
    /// Returns the raw items in declaration order.
    private static func parseList(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: ", ")
    }

    /// Force the macOS TCC prompt for Apple Events to the target app. Returns
    /// true when permission is granted (now or previously). Without this the
    /// first script call fails with -1743 silently if TCC happens to suppress
    /// the prompt (already-denied / stale signature). Run off-main.
    /// Walk the running app list, pick every supported browser, and send a
    /// minimal Apple Event (`get name`) to each. On a fresh install this
    /// triggers the TCC consent prompt per browser. **Must be called while
    /// the app is foreground** — agents (`LSUIElement = YES`) without a
    /// presentable UI window don't get a prompt; TCC silently denies and the
    /// entry never appears in System Settings → Privacy → Automation. The
    /// caller is expected to be the Settings window's "Browser tab drill-in"
    /// toggle, which provides exactly that foreground context.
    @MainActor
    static func requestPermissionForRunningBrowsers() {
        // Force ourselves to the foreground so TCC has a window context.
        NSApp.activate(ignoringOtherApps: true)
        var prompted: Set<String> = []
        var bundleIDs: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier?.lowercased(),
                  Family.from(bundleID: bid) != nil,
                  prompted.insert(bid).inserted else { continue }
            bundleIDs.append(bid)
        }
        guard !bundleIDs.isEmpty else { return }
        // Each runScript is a blocking waitpid; doing this on the main thread
        // froze the UI for the full per-browser round-trip (multi-second on
        // installs with several browsers running).
        DispatchQueue.global(qos: .userInitiated).async {
            for bid in bundleIDs {
                let escaped = bid.replacingOccurrences(of: "\\", with: "\\\\")
                                 .replacingOccurrences(of: "\"", with: "\\\"")
                let source = """
                tell application id "\(escaped)"
                    with timeout of 3 seconds
                        return name
                    end timeout
                end tell
                """
                NSLog("BrowserTabs: requesting permission for \(bid)")
                _ = runScript(source)
            }
        }
    }

    @discardableResult
    static func ensurePermission(bundleID: String) -> Bool {
        guard let cString = bundleID.cString(using: .utf8) else { return false }
        var targetDesc = AEAddressDesc()
        let bidLen = bundleID.utf8.count
        let status = cString.withUnsafeBufferPointer { buf -> OSStatus in
            guard let base = buf.baseAddress else { return OSStatus(-108) /* memFullErr */ }
            return OSStatus(AECreateDesc(
                DescType(typeApplicationBundleID),
                base,
                bidLen,
                &targetDesc
            ))
        }
        guard status == noErr else { return false }
        defer { AEDisposeDesc(&targetDesc) }
        let permission = AEDeterminePermissionToAutomateTarget(
            &targetDesc,
            DescType(typeWildCard),
            DescType(typeWildCard),
            true  // askUserIfNeeded — surfaces the TCC prompt
        )
        if permission != noErr {
            NSLog("BrowserTabs: AEDeterminePermissionToAutomateTarget \(bundleID) → \(permission)")
        }
        return permission == noErr
    }

    /// Enumerate the row window's tabs. Returns nil if the app isn't a
    /// supported browser; returns [] if the browser has fewer than 2 tabs
    /// (drill-in is only meaningful past 1). Run off-main.
    ///
    /// `title` is the row window's AX title. When it uniquely identifies one of
    /// the browser's windows we read that window directly (`window <index>`) and
    /// never `AXRaise` — so listing tabs no longer reorders the user's windows.
    /// Only when the title is empty/ambiguous do we fall back to the legacy
    /// raise + `window 1` path.
    static func tabTitles(for app: NSRunningApplication, window: AXUIElement, title: String) -> TabsOutcome {
        guard let family = Family.from(bundleID: app.bundleIdentifier),
              let bid = app.bundleIdentifier else { return .notSupported }
        let appLit = appLiteral(bid)
        // The tab attribute (`title`/`name`) is also the window's title-ish
        // property in both dictionaries, so the same keyword matches windows.
        let attr: String = (family == .safari) ? "name" : "title"

        // Preferred path: locate the window by name, no raise.
        if !title.isEmpty {
            let lit = escape(title)
            let matchSource = """
            tell \(appLit)
                with timeout of 3 seconds
                    set wc to count of windows
                    if wc = 0 then return "NOWINDOWS"
                    set matchIdx to 0
                    set matchCount to 0
                    repeat with i from 1 to wc
                        ignoring white space
                            if (\(attr) of window i) is "\(lit)" then
                                set matchIdx to i
                                set matchCount to matchCount + 1
                            end if
                        end ignoring
                    end repeat
                    if matchCount is 1 then
                        set AppleScript's text item delimiters to (ASCII character 10)
                        return "MATCH" & (ASCII character 10) & ((\(attr) of every tab of window matchIdx) as text)
                    else
                        return "FALLBACK"
                    end if
                end timeout
            end tell
            """
            if let raw = runScript(matchSource) {
                if raw == "NOWINDOWS" { return .tabs([]) }
                if raw != "FALLBACK" {
                    let body = raw.hasPrefix("MATCH\n") ? String(raw.dropFirst("MATCH\n".count)) : raw
                    let titles = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    return .tabs(titles)
                }
                // "FALLBACK" → title didn't uniquely match; use the raise path.
            } else {
                // Script errored (permission/timeout) — don't double-spawn the
                // raise path, just report the failure.
                NSLog("BrowserTabs: tabTitles \(bid) match script failed (permission/timeout?)")
                return .failed
            }
        }

        // Fallback: force the row's window frontmost and read `window 1`. `as
        // text` joins with the current delimiter (default ""), so pin it to LF
        // for unambiguous parsing even when a title contains commas.
        raiseInBrowser(window, pid: app.processIdentifier)
        let source = """
        tell \(appLit)
            with timeout of 3 seconds
                if (count of windows) = 0 then return ""
                set theList to \(attr) of every tab of window 1
            end timeout
        end tell
        set AppleScript's text item delimiters to (ASCII character 10)
        return theList as text
        """
        guard let raw = runScript(source) else {
            NSLog("BrowserTabs: tabTitles \(bid) failed (permission/timeout?)")
            return .failed
        }
        let titles = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return .tabs(titles)
    }

    /// Switch the row window's browser tab to `tabIndex` (0-based here, 1-based
    /// for AppleScript) and bring the browser forward. Run off-main.
    ///
    /// Like `tabTitles`, prefers to resolve the window by `title` and operate on
    /// `window <index>` (no `AXRaise`); falls back to raise + `window 1` when the
    /// title is empty/ambiguous. The `activate` (bring the app forward) stays —
    /// this is the deliberate commit, so the window coming front is expected.
    static func activateTab(at tabIndex: Int, in app: NSRunningApplication, window: AXUIElement, title: String) -> Bool {
        guard let family = Family.from(bundleID: app.bundleIdentifier),
              let bid = app.bundleIdentifier else { return false }
        let appLit = appLiteral(bid)
        let attr: String = (family == .safari) ? "name" : "title"
        let oneBased = tabIndex + 1

        // Per-family "select tab N of <windowExpr>, raise it, activate" body.
        func selectBody(_ windowExpr: String) -> String {
            let setTab: String
            switch family {
            case .chromium:
                setTab = "set active tab index of \(windowExpr) to \(oneBased)"
            case .safari:
                setTab = "set current tab of \(windowExpr) to tab \(oneBased) of \(windowExpr)"
            }
            return """
                    set tabCount to count of tabs of \(windowExpr)
                    if \(oneBased) > tabCount then return "false"
                    \(setTab)
                    set index of \(windowExpr) to 1
                    activate
                    return "true"
            """
        }

        // Preferred path: select within the name-matched window, no raise.
        if !title.isEmpty {
            let lit = escape(title)
            let matchSource = """
            tell \(appLit)
                with timeout of 3 seconds
                    set wc to count of windows
                    if wc = 0 then return "false"
                    set matchIdx to 0
                    set matchCount to 0
                    repeat with i from 1 to wc
                        ignoring white space
                            if (\(attr) of window i) is "\(lit)" then
                                set matchIdx to i
                                set matchCount to matchCount + 1
                            end if
                        end ignoring
                    end repeat
                    if matchCount is 1 then
            \(selectBody("window matchIdx"))
                    else
                        return "FALLBACK"
                    end if
                end timeout
            end tell
            """
            if let raw = runScript(matchSource), raw != "FALLBACK" {
                return raw == "true"
            }
        }

        // Fallback: raise the row's window frontmost, operate on `window 1`.
        raiseInBrowser(window, pid: app.processIdentifier)
        let source = """
        tell \(appLit)
            with timeout of 3 seconds
                if (count of windows) = 0 then return "false"
        \(selectBody("window 1"))
            end timeout
        end tell
        """
        guard let raw = runScript(source) else { return false }
        return raw == "true"
    }
}
