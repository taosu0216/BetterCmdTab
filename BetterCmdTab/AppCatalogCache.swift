import AppKit

@MainActor
final class AppCatalogCache {
    struct AppCacheEntry {
        let app: NSRunningApplication
        let windows: [WindowInfo]
    }

    private(set) var entries: [pid_t: AppCacheEntry] = [:]
    private var pendingRefresh = false
    private weak var mru: MRUTracker?
    private var observers: [NSObjectProtocol] = []
    private var periodicTimer: Timer?
    private let snapshotQueue = DispatchQueue(label: "BetterCmdTab.snapshot", qos: .userInteractive)

    func start(mru: MRUTracker) {
        self.mru = mru
        installObservers()
        scheduleFullRefresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleFullRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    func rows(orderedBy mru: [pid_t]) -> [SwitcherRow] {
        var ordered: [AppCacheEntry] = []
        ordered.reserveCapacity(entries.count)
        var seen = Set<pid_t>()
        for pid in mru {
            if let entry = entries[pid] {
                ordered.append(entry)
                seen.insert(pid)
            }
        }
        for entry in entries.values where !seen.contains(entry.app.processIdentifier) {
            ordered.append(entry)
        }

        var result: [SwitcherRow] = []
        result.reserveCapacity(ordered.count * 2)
        for entry in ordered {
            if entry.windows.isEmpty {
                if entry.app.activationPolicy == .regular {
                    result.append(SwitcherRow(
                        app: entry.app,
                        window: nil,
                        windowTitle: "",
                        isMinimized: false
                    ))
                }
            } else {
                for window in entry.windows {
                    result.append(SwitcherRow(
                        app: entry.app,
                        window: window.ref,
                        windowTitle: window.title,
                        isMinimized: window.isMinimized,
                        tabRef: window.tabRef
                    ))
                }
            }
        }
        return result.enumerated().sorted { lhs, rhs in
            let pa = Self.statusPriority(lhs.element)
            let pb = Self.statusPriority(rhs.element)
            if pa != pb { return pa < pb }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    private static func statusPriority(_ row: SwitcherRow) -> Int {
        if row.app.isHidden { return 2 }
        if row.isMinimized { return 1 }
        return 0
    }

    func scheduleFullRefresh() {
        guard !pendingRefresh else { return }
        pendingRefresh = true
        snapshotQueue.async { [weak self] in
            let fresh = Self.computeEntries()
            DispatchQueue.main.async {
                guard let self else { return }
                self.entries = fresh
                self.pendingRefresh = false
            }
        }
    }

    func refreshNow() {
        snapshotQueue.sync {
            let fresh = Self.computeEntries()
            DispatchQueue.main.sync {
                self.entries = fresh
            }
        }
    }

    private static func computeEntries() -> [pid_t: AppCacheEntry] {
        let selfPid = getpid()
        let candidates = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != selfPid else { return false }
            return app.activationPolicy == .regular || app.activationPolicy == .accessory
        }
        let count = candidates.count
        guard count > 0 else { return [:] }

        var windowsBuffer: [[WindowInfo]] = Array(repeating: [], count: count)
        windowsBuffer.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: count) { i in
                let app = candidates[i]
                buffer[i] = WindowEnumerator.windows(forPid: app.processIdentifier)
            }
        }

        var dict: [pid_t: AppCacheEntry] = [:]
        dict.reserveCapacity(count)
        for i in 0..<count {
            let app = candidates[i]
            let windows = windowsBuffer[i]
            if app.activationPolicy == .regular {
                dict[app.processIdentifier] = AppCacheEntry(app: app, windows: windows)
            } else if app.activationPolicy == .accessory, !windows.isEmpty {
                dict[app.processIdentifier] = AppCacheEntry(app: app, windows: windows)
            }
        }
        return dict
    }

    private func installObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        let perAppNames: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in perAppNames {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor [weak self] in
                    self?.bumpApp(pid: pid)
                }
            }
            observers.append(obs)
        }
        let terminateObs = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.entries.removeValue(forKey: pid)
            }
        }
        observers.append(terminateObs)
        let launchObs = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                self?.bumpApp(pid: pid)
            }
        }
        observers.append(launchObs)
    }

    func bumpApp(pid: pid_t) {
        guard pid != getpid() else { return }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) else {
            entries.removeValue(forKey: pid)
            return
        }
        let policy = app.activationPolicy
        guard policy == .regular || policy == .accessory else {
            entries.removeValue(forKey: pid)
            return
        }
        snapshotQueue.async { [weak self] in
            let windows = WindowEnumerator.windows(forPid: pid)
            DispatchQueue.main.async {
                guard let self else { return }
                if policy == .regular {
                    self.entries[pid] = AppCacheEntry(app: app, windows: windows)
                } else if policy == .accessory, !windows.isEmpty {
                    self.entries[pid] = AppCacheEntry(app: app, windows: windows)
                } else {
                    self.entries.removeValue(forKey: pid)
                }
            }
        }
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for obs in observers {
            nc.removeObserver(obs)
        }
        periodicTimer?.invalidate()
    }
}
