import AppKit

@MainActor
enum IconCache {
    private static let capacity = 64
    /// Edge length (px) of the flattened raster we cache. Sized just above the
    /// largest on-screen icon — the grid tile at max scale (64pt × 1.8 screen
    /// clamp × 1.2 "Large") is ~138pt → ~276px on a 2x Mac, and macOS has no
    /// >2x backing scale — so the image view only ever downscales, staying
    /// crisp, while keeping the per-entry footprint as small as possible.
    nonisolated private static let renderEdge = 320
    /// Byte cost of one flattened entry (used as the NSCache cost). A 320² RGBA
    /// bitmap is ~410 KB, so the cap doubles as a real memory ceiling.
    nonisolated private static let bytesPerImage = renderEdge * renderEdge * 4

    /// `NSCache` rather than a hand-rolled LRU dict so the system can evict
    /// flattened icons automatically under memory pressure (and the count/cost
    /// limits bound steady-state footprint). Keyed by pid.
    private static let cache: NSCache<NSNumber, NSImage> = {
        let c = NSCache<NSNumber, NSImage>()
        c.countLimit = capacity
        c.totalCostLimit = capacity * bytesPerImage
        return c
    }()

    static func icon(for row: SwitcherRow) -> NSImage? {
        // Launchable rows have no pid to key on — fetch their icon directly.
        guard let pid = row.pid else { return row.icon }
        let key = NSNumber(value: pid)
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = row.app?.icon else { return row.icon }
        let flat = flattened(source) ?? source
        cache.setObject(flat, forKey: key, cost: bytesPerImage)
        return flat
    }

    static func evict(_ pid: pid_t) {
        cache.removeObject(forKey: NSNumber(value: pid))
    }

    static func clear() {
        cache.removeAllObjects()
    }

    /// Eagerly populate icons for the given pids so the first reveal pays no
    /// `NSRunningApplication.icon` decode/flatten latency on the main thread.
    /// Safe to call repeatedly; existing entries are kept, missing entries
    /// fetched and flattened on a background queue.
    static func prewarm(pids: [pid_t]) {
        let apps = NSWorkspace.shared.runningApplications
        let byPid = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        // Collect the source icons still missing from the cache. Reading
        // `app.icon` and touching `cache` must happen on the main actor; the
        // expensive part (flattening) is deferred to a background queue below.
        var pending: [(pid_t, NSImage)] = []
        for pid in pids {
            guard cache.object(forKey: NSNumber(value: pid)) == nil,
                  let app = byPid[pid], let source = app.icon else { continue }
            pending.append((pid, source))
        }
        guard !pending.isEmpty else { return }
        // Flattening rasterizes a renderEdge² RGBA bitmap per icon — pure pixel work
        // that has no business on the reveal-adjacent main thread when several
        // apps launch at once. Do it on a background queue (each draws into its
        // own bitmap rep, so there is no shared AppKit state) and hand the
        // finished, immutable images back to the main-actor cache.
        DispatchQueue.global(qos: .utility).async {
            let flattenedPairs: [(pid_t, NSImage)] = pending.map { pid, source in
                (pid, flattened(source) ?? source)
            }
            DispatchQueue.main.async {
                for (pid, image) in flattenedPairs {
                    let key = NSNumber(value: pid)
                    if cache.object(forKey: key) == nil {
                        cache.setObject(image, forKey: key, cost: bytesPerImage)
                    }
                }
            }
        }
    }

    /// Rasterize an app icon into a fixed-size, immutable bitmap.
    ///
    /// On macOS 26 (Tahoe) the system restyles legacy app icons on the fly
    /// (rounded-rect mask + Liquid Glass material). `NSRunningApplication.icon`
    /// hands back a *live* `NSImage` whose representations IconServices fills in
    /// lazily: the view paints the raw `.icns` rep first, then AppKit swaps in
    /// the styled rendition under the same object — a visible old→new flicker.
    /// Drawing once into our own bitmap resolves the styled rendition right
    /// here and yields an image AppKit won't mutate afterwards, so the swap
    /// (and its flicker) can't happen. The styling cost is also paid once
    /// rather than on every redraw.
    nonisolated private static func flattened(_ image: NSImage) -> NSImage? {
        let size = NSSize(width: renderEdge, height: renderEdge)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: renderEdge,
            pixelsHigh: renderEdge,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        ctx.flushGraphics()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}
