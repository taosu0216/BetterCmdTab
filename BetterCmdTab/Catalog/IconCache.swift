import AppKit

@MainActor
enum IconCache {
    private static let capacity = 64
    /// Edge length (px) of the flattened raster we cache. Comfortably exceeds
    /// the largest on-screen icon — the grid tile at max scale on a 2x Mac is
    /// ~280px — so the image view only ever downscales, staying crisp.
    private static let renderEdge = 384

    private static var cache: [pid_t: NSImage] = [:]
    private static var order: [pid_t] = []

    static func icon(for row: SwitcherRow) -> NSImage? {
        // Launchable rows have no pid to key on — fetch their icon directly.
        guard let pid = row.pid else { return row.icon }
        if let cached = cache[pid] {
            touch(pid)
            return cached
        }
        guard let source = row.app?.icon else { return row.icon }
        let flat = flattened(source) ?? source
        cache[pid] = flat
        order.append(pid)
        evictIfNeeded()
        return flat
    }

    static func evict(_ pid: pid_t) {
        if cache.removeValue(forKey: pid) != nil {
            if let idx = order.firstIndex(of: pid) {
                order.remove(at: idx)
            }
        }
    }

    static func clear() {
        cache.removeAll()
        order.removeAll()
    }

    /// Eagerly populate icons for the given pids so the first reveal pays no
    /// `NSRunningApplication.icon` decode/flatten latency on the main thread.
    /// Safe to call repeatedly; existing entries are touched, missing entries
    /// fetched and flattened.
    static func prewarm(pids: [pid_t]) {
        let apps = NSWorkspace.shared.runningApplications
        let byPid = Dictionary(uniqueKeysWithValues: apps.map { ($0.processIdentifier, $0) })
        for pid in pids {
            guard cache[pid] == nil, let app = byPid[pid], let source = app.icon else { continue }
            cache[pid] = flattened(source) ?? source
            order.append(pid)
        }
        evictIfNeeded()
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
    private static func flattened(_ image: NSImage) -> NSImage? {
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

    private static func touch(_ pid: pid_t) {
        if let idx = order.firstIndex(of: pid) {
            order.remove(at: idx)
            order.append(pid)
        }
    }

    private static func evictIfNeeded() {
        while order.count > capacity {
            let victim = order.removeFirst()
            cache.removeValue(forKey: victim)
        }
    }
}
