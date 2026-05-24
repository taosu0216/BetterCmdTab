//
//  GitHubUpdater.swift
//  BetterCmdTab
//
//  Custom updater using GitHub Releases API.
//  No external dependencies — pure Swift implementation.
//

import Foundation
import AppKit
import Combine
import Security

enum GitHubUpdaterConfig {
    static let owner = "rokartur"
    static let repo = "BetterCmdTab"
    static let apiBaseURL = "https://api.github.com"
    static let apiVersion = "2022-11-28"
    static let userAgent = "BetterCmdTab-Updater/\(AppInfo.appVersion) (\(AppInfo.appBuildNumber))"

    /// Minimum interval between manual checks (in seconds).
    static let minManualCheckInterval: TimeInterval = 60

    /// Retry delay after a failed silent check.
    static let errorRetryInterval: TimeInterval = 15 * 60

    static let defaultCheckInterval: UpdateCheckInterval = .automatic
}

struct ParsedVersion: Equatable, Comparable {
    let core: [Int]
    let prerelease: [String]

    init(_ raw: String) {
        let trimmed = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreStr = String(parts.first ?? "")
        self.core = coreStr.split(separator: ".").compactMap { Int($0) }
        if parts.count > 1 {
            self.prerelease = parts[1].split(separator: ".").map(String.init)
        } else {
            self.prerelease = []
        }
    }

    static func < (lhs: ParsedVersion, rhs: ParsedVersion) -> Bool {
        let maxCount = max(lhs.core.count, rhs.core.count)
        let l = lhs.core + Array(repeating: 0, count: maxCount - lhs.core.count)
        let r = rhs.core + Array(repeating: 0, count: maxCount - rhs.core.count)
        for componentIndex in 0..<maxCount {
            if l[componentIndex] != r[componentIndex] {
                return l[componentIndex] < r[componentIndex]
            }
        }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false):
            let minCount = min(lhs.prerelease.count, rhs.prerelease.count)
            for prereleaseIndex in 0..<minCount {
                let a = lhs.prerelease[prereleaseIndex]
                let b = rhs.prerelease[prereleaseIndex]
                if a == b { continue }
                if let ai = Int(a), let bi = Int(b) {
                    return ai < bi
                }
                return a < b
            }
            return lhs.prerelease.count < rhs.prerelease.count
        }
    }
}

struct GitHubUpdateDecision: Equatable {
    let isUpdateAvailable: Bool
    let isNewerBuild: Bool

    struct Input {
        let currentVersion: String
        let latestVersion: String
        let currentBuildNumber: Int
        let remoteBuildNumber: Int?
    }

    static func evaluate(_ input: Input) -> GitHubUpdateDecision {
        let current = ParsedVersion(input.currentVersion)
        let latest = ParsedVersion(input.latestVersion)

        // Build-number fallback fires when both releases share the same semantic
        // core (e.g. 1.0.0 vs 1.0.0-beta.2). MARKETING_VERSION drops the -beta.N
        // suffix, so betas of the same core can only be told apart by the
        // timestamp-based CURRENT_PROJECT_VERSION.
        let coresMatch = current.core == latest.core
        let newerBuild: Bool = {
            guard coresMatch, let remoteBuild = input.remoteBuildNumber else {
                return false
            }
            return remoteBuild > input.currentBuildNumber
        }()

        let updateAvailable = current < latest || newerBuild

        return GitHubUpdateDecision(
            isUpdateAvailable: updateAvailable,
            isNewerBuild: newerBuild
        )
    }

    static func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        ParsedVersion(version2) < ParsedVersion(version1)
    }
}

// MARK: - LastInstallAttempt breadcrumb

/// Diagnostic record of the most recent install handoff. Surface this in the
/// update window so a silent helper failure on the previous launch is visible
/// instead of repeating the popup forever.
struct LastInstallAttempt: Codable, Equatable {
    enum Stage: String, Codable {
        case handoffSpawned
        case handoffFailed
        case helperExited
        case succeeded
    }

    let version: String
    let attemptedAt: Date
    var stage: Stage
    var errorMessage: String?
    var helperLogTail: String?
}

@MainActor
final class GitHubUpdater: ObservableObject {

    static let shared = GitHubUpdater()

    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var latestRelease: GitHubRelease?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var checkInterval: UpdateCheckInterval = GitHubUpdaterConfig.defaultCheckInterval
    @Published private(set) var isNewerBuild: Bool = false
    @Published var automaticDownloadEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticDownloadEnabled, forKey: "GitHubUpdater.automaticDownloadEnabled")
        }
    }
    @Published var automaticInstallEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticInstallEnabled, forKey: "GitHubUpdater.automaticInstallEnabled")
        }
    }
    @Published var includePreReleases: Bool {
        didSet {
            UserDefaults.standard.set(includePreReleases, forKey: "GitHubUpdater.includePreReleases")
        }
    }
    @Published var skippedVersion: String? {
        didSet {
            if let v = skippedVersion {
                UserDefaults.standard.set(v, forKey: "GitHubUpdater.skippedVersion")
            } else {
                UserDefaults.standard.removeObject(forKey: "GitHubUpdater.skippedVersion")
            }
        }
    }
    @Published private(set) var lastInstallAttempt: LastInstallAttempt? = nil

    func setCheckInterval(_ interval: UpdateCheckInterval) {
        guard interval != checkInterval else { return }
        checkInterval = interval
        UserDefaults.standard.set(interval.rawValue, forKey: "GitHubUpdater.checkInterval")
        rescheduleAutomaticCheck()
    }

    private var downloadTask: URLSessionDownloadTask?
    private var downloadProgressObservation: NSKeyValueObservation?
    private var automaticCheckTask: Task<Void, Never>?
    private let urlSession: URLSession
    private var downloadedFileURL: URL?
    private var lastFailureDate: Date?

    var automaticChecksEnabled: Bool {
        checkInterval != .manual
    }

    private init() {
        self.checkInterval = .automatic
        UserDefaults.standard.set(UpdateCheckInterval.automatic.rawValue, forKey: "GitHubUpdater.checkInterval")
        self.automaticDownloadEnabled = UserDefaults.standard.object(forKey: "GitHubUpdater.automaticDownloadEnabled") as? Bool ?? false
        self.automaticInstallEnabled = UserDefaults.standard.object(forKey: "GitHubUpdater.automaticInstallEnabled") as? Bool ?? true
        self.includePreReleases = UserDefaults.standard.object(forKey: "GitHubUpdater.includePreReleases") as? Bool ?? false
        // Clear skipped version on each launch — "Skip" means "not now", not "never".
        self.skippedVersion = nil

        let storedTimestamp = UserDefaults.standard.double(forKey: "GitHubUpdater.lastCheckDate")
        self.lastCheckDate = storedTimestamp > 0 ? Date(timeIntervalSince1970: storedTimestamp) : nil

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": GitHubUpdaterConfig.apiVersion,
            "User-Agent": GitHubUpdaterConfig.userAgent
        ]
        self.urlSession = URLSession(configuration: config)

        BCTLog.updater.info("GitHubUpdater initialized with check interval: \(checkInterval.rawValue)")

        rescheduleAutomaticCheck()
    }

    deinit {
        downloadProgressObservation?.invalidate()
        downloadTask?.cancel()
    }

    func checkForUpdates(force: Bool = false) async {
        if !force, let lastCheck = lastCheckDate {
            let elapsed = Date().timeIntervalSince(lastCheck)
            if elapsed < GitHubUpdaterConfig.minManualCheckInterval {
                BCTLog.updater.debug("Skipping update check - last check was \(Int(elapsed))s ago")
                return
            }
        }

        let isSilent = !force && automaticChecksEnabled

        state = .checking
        BCTLog.updater.info("Checking for updates... (silent: \(isSilent))")

        do {
            let release = try await fetchLatestRelease()
            latestRelease = release
            lastCheckDate = Date()
            lastFailureDate = nil
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "GitHubUpdater.lastCheckDate")

            let currentVersion = AppInfo.appVersion
            let latestVersion = release.version

            BCTLog.updater.info("Current version: \(currentVersion) (\(AppInfo.appBuildNumber)), Latest version: \(latestVersion) (\(release.macOSAsset?.buildNumber.map(String.init) ?? "?"))")

            let decision = GitHubUpdateDecision.evaluate(GitHubUpdateDecision.Input(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                currentBuildNumber: Int(AppInfo.appBuildNumber) ?? 0,
                remoteBuildNumber: release.macOSAsset?.buildNumber
            ))

            if decision.isUpdateAvailable {
                if !force, !decision.isNewerBuild, let skipped = skippedVersion, skipped == latestVersion {
                    BCTLog.updater.info("Skipping version \(latestVersion) (user skipped)")
                    state = .idle
                    return
                }

                isNewerBuild = decision.isNewerBuild

                if decision.isNewerBuild {
                    BCTLog.updater.notice("Newer build available for version \(latestVersion) (same version, newer build number)")
                } else {
                    BCTLog.updater.notice("Update available: \(latestVersion)")
                }
                state = .available(version: latestVersion, releaseNotes: release.body)

                UpdateWindowPresenter.shared.show()
            } else {
                isNewerBuild = false
                BCTLog.updater.info("App is up to date")
                state = .upToDate
            }
        } catch {
            let errorMessage = (error as? UpdateError)?.localizedDescription ?? error.localizedDescription
            BCTLog.updater.error("Update check failed: \(errorMessage)")
            lastFailureDate = Date()
            if !isSilent {
                state = .error(errorMessage)
            } else {
                state = .idle
            }
        }

        rescheduleAutomaticCheck()
    }

    func downloadUpdate() async {
        guard let release = latestRelease,
              let asset = release.macOSAsset else {
            state = .error("No downloadable asset found")
            BCTLog.updater.error("No macOS asset found in release")
            return
        }

        guard let url = URL(string: asset.browserDownloadUrl) else {
            state = .error("Invalid download URL")
            return
        }

        state = .downloading(progress: 0)
        BCTLog.updater.info("Downloading update from: \(url.absoluteString)")

        do {
            let localURL = try await downloadFile(from: url, fileName: asset.name)
            downloadedFileURL = localURL
            state = .readyToInstall(localURL: localURL)
            BCTLog.updater.notice("Download complete: \(localURL.path)")
        } catch {
            let errorMessage = (error as? UpdateError)?.localizedDescription ?? error.localizedDescription
            BCTLog.updater.error("Download failed: \(errorMessage)")
            state = .error(errorMessage)
        }
    }

    func downloadAndInstall() async {
        await downloadUpdate()
        if case .readyToInstall = state {
            await installUpdate()
        }
    }

    func installUpdate() async {
        guard case .readyToInstall(let localURL) = state else {
            BCTLog.updater.warn("No update ready to install")
            return
        }

        state = .installing(progress: 0.0, step: "Starting installation…")
        BCTLog.updater.info("Installing update from: \(localURL.path)")

        do {
            try await performInstallation(from: localURL)
        } catch {
            let errorMessage = (error as? UpdateError)?.localizedDescription ?? error.localizedDescription
            BCTLog.updater.error("Installation failed: \(errorMessage)")
            state = .error(errorMessage)
        }
    }

    func openReleasesPage() {
        let url = URL(string: "https://github.com/\(GitHubUpdaterConfig.owner)/\(GitHubUpdaterConfig.repo)/releases")!
        NSWorkspace.shared.open(url)
    }

    func openLatestReleasePage() {
        if let release = latestRelease, let url = URL(string: release.htmlUrl) {
            NSWorkspace.shared.open(url)
        } else {
            openReleasesPage()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadProgressObservation?.invalidate()
        downloadProgressObservation = nil

        if case .available(let version, let notes) = state {
            state = .available(version: version, releaseNotes: notes)
        } else {
            state = .idle
        }

        BCTLog.updater.info("Download cancelled")
    }

    func resetToIdle() {
        state = .idle
    }

    func reset() {
        cancelDownload()
        state = .idle
        isNewerBuild = false

        if let url = downloadedFileURL {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                BCTLog.updater.warn("Failed to remove downloaded update file at \(url.path): \(error.localizedDescription)")
            }
            downloadedFileURL = nil
        }
    }

    func skipCurrentUpdate() {
        if let version = latestRelease?.version {
            skippedVersion = version
            BCTLog.updater.info("User skipped version \(version)")
        }
        state = .idle
    }

    func remindLater() {
        BCTLog.updater.info("User chose 'Remind Me Later'")
        UpdateWindowPresenter.shared.hide()
        state = .idle
    }

    // MARK: - Private

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let endpoint: String
        if includePreReleases {
            endpoint = "\(GitHubUpdaterConfig.apiBaseURL)/repos/\(GitHubUpdaterConfig.owner)/\(GitHubUpdaterConfig.repo)/releases?per_page=1"
        } else {
            endpoint = "\(GitHubUpdaterConfig.apiBaseURL)/repos/\(GitHubUpdaterConfig.owner)/\(GitHubUpdaterConfig.repo)/releases/latest"
        }

        guard let url = URL(string: endpoint) else {
            throw UpdateError.networkError("Invalid URL")
        }

        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw UpdateError.noReleasesFound
            }
            throw UpdateError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if includePreReleases {
            let releases = try decoder.decode([GitHubRelease].self, from: data)
            guard let firstRelease = releases.first else {
                throw UpdateError.noReleasesFound
            }
            return firstRelease
        } else {
            return try decoder.decode(GitHubRelease.self, from: data)
        }
    }

    private func downloadFile(from url: URL, fileName: String) async throws -> URL {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: UpdateError.downloadFailed("Updater deallocated"))
                return
            }

            let task = self.urlSession.downloadTask(with: url) { tempURL, response, error in
                if let error = error {
                    if (error as NSError).code == NSURLErrorCancelled {
                        continuation.resume(throwing: UpdateError.userCancelled)
                    } else {
                        continuation.resume(throwing: UpdateError.downloadFailed(error.localizedDescription))
                    }
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(throwing: UpdateError.downloadFailed("No file downloaded"))
                    return
                }

                let destinationDir: URL
                do {
                    destinationDir = try GitHubUpdater.updaterDownloadDirectoryURL()
                } catch {
                    continuation.resume(throwing: UpdateError.downloadFailed("Failed to prepare updater directory: \(error.localizedDescription)"))
                    return
                }

                let destinationURL = destinationDir.appendingPathComponent(fileName)
                let fileManager = FileManager.default

                do {
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.moveItem(at: tempURL, to: destinationURL)
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: UpdateError.downloadFailed("Failed to save file: \(error.localizedDescription)"))
                }
            }

            Task { @MainActor [weak self] in
                self?.downloadProgressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        self?.state = .downloading(progress: fraction)
                    }
                }
            }

            self.downloadTask = task
            task.resume()
        }
    }

    private func performInstallation(from url: URL) async throws {
        switch url.pathExtension.lowercased() {
        case "zip":
            try await installFromZip(at: url)
        case "dmg":
            try await installFromDmg(at: url)
        default:
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            await showInstallationInstructions(manual: true)
        }
    }

    private func updateInstallProgress(_ progress: Double, step: String) async {
        state = .installing(progress: progress, step: step)
        try? await Task.sleep(for: .milliseconds(300))
    }

    private func installFromZip(at url: URL) async throws {
        let fileManager = FileManager.default

        defer {
            removeDownloadedArchiveIfNeeded(at: url)
        }

        await updateInstallProgress(0.05, step: "Preparing installation…")

        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("BetterCmdTab_Update_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        await updateInstallProgress(0.15, step: "Extracting archive…")

        let unzipStatus = try await runProcessAndWait(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-q", url.path, "-d", tempDir.path]
        )

        guard unzipStatus == 0 else {
            throw UpdateError.installationFailed("Failed to unzip update")
        }

        await updateInstallProgress(0.35, step: "Verifying contents…")

        let appBundle = try await findFirstAppBundle(in: tempDir)

        // Helper consumes `appBundle` via `mv` after we exit — do NOT remove tempDir here.
        try await installApp(from: appBundle)
    }

    private func installFromDmg(at url: URL) async throws {
        let fileManager = FileManager.default

        defer {
            removeDownloadedArchiveIfNeeded(at: url)
        }

        await updateInstallProgress(0.05, step: "Preparing installation…")

        let mountpoint = fileManager.temporaryDirectory
            .appendingPathComponent("BetterCmdTab_DMG_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: mountpoint, withIntermediateDirectories: true)

        await updateInstallProgress(0.15, step: "Mounting disk image…")

        let attachStatus = try await runProcessAndWait(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: [
                "attach",
                "-nobrowse",
                "-quiet",
                "-noverify",
                "-readonly",
                "-mountpoint", mountpoint.path,
                url.path
            ]
        )

        guard attachStatus == 0 else {
            try? await removeItemIfExists(at: mountpoint)
            throw UpdateError.installationFailed("Failed to mount disk image")
        }

        @Sendable func detach() async {
            let status = (try? await self.runProcessAndWait(
                executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", "-quiet", mountpoint.path]
            )) ?? -1
            if status != 0 {
                _ = try? await self.runProcessAndWait(
                    executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                    arguments: ["detach", "-quiet", "-force", mountpoint.path]
                )
            }
        }

        let stagingDir = fileManager.temporaryDirectory
            .appendingPathComponent("BetterCmdTab_DmgStage_\(UUID().uuidString)", isDirectory: true)

        do {
            await updateInstallProgress(0.30, step: "Verifying contents…")

            let mountedApp = try await findFirstAppBundle(in: mountpoint)

            try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let stagedApp = stagingDir.appendingPathComponent(mountedApp.lastPathComponent)

            await updateInstallProgress(0.45, step: "Extracting archive…")

            let dittoStatus = try await runProcessAndWait(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: [mountedApp.path, stagedApp.path]
            )
            guard dittoStatus == 0 else {
                throw UpdateError.installationFailed("Failed to extract app from disk image")
            }

            await detach()

            // Helper consumes `stagedApp` after we exit — do NOT clean stagingDir here.
            try await installApp(from: stagedApp)
        } catch {
            await detach()
            try? await removeItemIfExists(at: stagingDir)
            try? await removeItemIfExists(at: mountpoint)
            throw error
        }
    }

    private func removeDownloadedArchiveIfNeeded(at url: URL) {
        let fileManager = FileManager.default
        let ext = url.pathExtension.lowercased()
        guard ext == "zip" || ext == "dmg" else { return }

        guard let trackedDownloadedURL = downloadedFileURL,
              trackedDownloadedURL.standardizedFileURL == url.standardizedFileURL else {
            BCTLog.updater.debug("Skipping archive cleanup for untracked zip: \(url.path)")
            return
        }

        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                BCTLog.updater.debug("Removed downloaded archive: \(url.path)")
            } catch {
                BCTLog.updater.warn("Failed to remove downloaded archive at \(url.path): \(error.localizedDescription)")
            }
        }

        if downloadedFileURL == url {
            downloadedFileURL = nil
        }
    }

    nonisolated private static func updaterDownloadDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupportDir = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let updaterDir = appSupportDir
            .appendingPathComponent("BetterCmdTab", isDirectory: true)
            .appendingPathComponent("UpdaterDownloads", isDirectory: true)

        if !fileManager.fileExists(atPath: updaterDir.path) {
            try fileManager.createDirectory(at: updaterDir, withIntermediateDirectories: true)
        }

        return updaterDir
    }

    private func installApp(from sourceApp: URL) async throws {
        let currentAppURL = Bundle.main.bundleURL
        let applicationsDir = URL(fileURLWithPath: "/Applications")

        let targetAppURL: URL
        if currentAppURL.path.hasPrefix("/Applications/") {
            targetAppURL = applicationsDir.appendingPathComponent(currentAppURL.lastPathComponent)
        } else if automaticInstallEnabled {
            targetAppURL = applicationsDir.appendingPathComponent(sourceApp.lastPathComponent)
        } else {
            targetAppURL = currentAppURL.deletingLastPathComponent()
                .appendingPathComponent(sourceApp.lastPathComponent)
        }

        BCTLog.updater.info("Installing app from \(sourceApp.path) to \(targetAppURL.path)")

        try await validateDownloadedAppBundle(at: sourceApp)

        await updateInstallProgress(0.55, step: "Preparing installer…")

        do {
            try await UpdateInstallerHelper.handoffSwap(
                stagedAppURL: sourceApp,
                targetAppURL: targetAppURL,
                removeSource: true
            )
        } catch UpdateInstallerHelper.HandoffError.authorizationDenied {
            BCTLog.updater.notice("User cancelled installer authorization — falling back to manual install")
            NSWorkspace.shared.selectFile(sourceApp.path, inFileViewerRootedAtPath: sourceApp.deletingLastPathComponent().path)
            await showInstallationInstructions(manual: true)
            return
        } catch {
            BCTLog.updater.error("Installer handoff failed: \(error.localizedDescription) — falling back to manual install")
            NSWorkspace.shared.selectFile(sourceApp.path, inFileViewerRootedAtPath: sourceApp.deletingLastPathComponent().path)
            await showInstallationInstructions(manual: true)
            return
        }

        await updateInstallProgress(0.95, step: "Restarting BetterCmdTab…")
        try? await Task.sleep(for: .milliseconds(200))

        BCTLog.updater.notice("Quitting to allow installer helper to finish")
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    @MainActor
    private func showInstallationInstructions(manual: Bool) async {
        let alert = NSAlert()
        alert.messageText = "Update Downloaded"
        alert.informativeText = "The update has been downloaded. Please drag the new BetterCmdTab app to your Applications folder to complete the installation.\n\nAfter installation, restart BetterCmdTab."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Applications Folder")

        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            if let applicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first {
                NSWorkspace.shared.open(applicationsURL)
            }
        }

        state = .idle
    }

    private func runProcessAndWait(executableURL: URL, arguments: [String]) async throws -> Int32 {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    private func findFirstAppBundle(in directory: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.installationFailed("No app bundle found in archive")
            }
            return appBundle
        }.value
    }

    private func removeItemIfExists(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }.value
    }

    private func validateDownloadedAppBundle(at appURL: URL) async throws {
        let expectedBundleIdentifier = Bundle.main.bundleIdentifier
        let expectedTeamIdentifier = Self.currentTeamIdentifier()

        try await Task.detached(priority: .userInitiated) {
            try Self.validateAppBundleSignature(
                at: appURL,
                expectedBundleIdentifier: expectedBundleIdentifier,
                expectedTeamIdentifier: expectedTeamIdentifier
            )
        }.value
    }

    nonisolated private static func validateAppBundleSignature(
        at appURL: URL,
        expectedBundleIdentifier: String?,
        expectedTeamIdentifier: String?
    ) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            throw UpdateError.installationFailed("Invalid app bundle signature")
        }

        var requirementParts: [String] = ["anchor apple generic"]
        if let expectedBundleIdentifier, !expectedBundleIdentifier.isEmpty {
            requirementParts.append("identifier \"\(escapedRequirementValue(expectedBundleIdentifier))\"")
        }
        if let expectedTeamIdentifier, !expectedTeamIdentifier.isEmpty {
            requirementParts.append("certificate leaf[subject.OU] = \"\(escapedRequirementValue(expectedTeamIdentifier))\"")
        }

        var requirement: SecRequirement?
        let requirementString = requirementParts.joined(separator: " and ")
        guard SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else {
            throw UpdateError.installationFailed("Invalid update signing requirement")
        }

        let status = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            requirement
        )
        guard status == errSecSuccess else {
            throw UpdateError.installationFailed("Update signature verification failed")
        }
    }

    nonisolated private static func currentTeamIdentifier() -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(), &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any] else {
            return nil
        }

        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    nonisolated private static func escapedRequirementValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func rescheduleAutomaticCheck() {
        cancelAutomaticCheck()

        guard let interval = checkInterval.interval else {
            BCTLog.updater.debug("Automatic update checks disabled (manual mode)")
            return
        }

        automaticCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                let nextDate = self.computeNextCheckDate(interval: interval)
                let delay = nextDate.timeIntervalSinceNow

                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }

                guard !Task.isCancelled else { break }

                await self.checkForUpdates(force: false)

                // checkForUpdates calls rescheduleAutomaticCheck which cancels this task.
                break
            }
        }

        BCTLog.updater.debug("Automatic update checks scheduled: \(checkInterval.title)")
    }

    private func computeNextCheckDate(interval: TimeInterval) -> Date {
        let now = Date()
        let rawAnchor = lastCheckDate ?? now
        let safeAnchor = rawAnchor > now ? now : rawAnchor
        let successNext = safeAnchor.addingTimeInterval(interval)

        guard let failure = lastFailureDate,
              failure > (lastCheckDate ?? .distantPast) else {
            return successNext
        }

        let safeFailure = failure > now ? now : failure
        let retryNext = safeFailure.addingTimeInterval(GitHubUpdaterConfig.errorRetryInterval)
        return min(successNext, retryNext)
    }

    private func cancelAutomaticCheck() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }
}

extension GitHubUpdater {

    var lastCheckDescription: String {
        guard let date = lastCheckDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var updateAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    var currentVersion: String { AppInfo.appVersion }

    var latestVersion: String? { latestRelease?.version }
}
