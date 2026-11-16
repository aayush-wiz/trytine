import AppKit
import CoreGraphics

enum ScreenCapture {
    /// One screen grab plus everything needed to map model pixel-coordinates back onto the real screen.
    struct Shot {
        let base64: String      // JPEG, base64
        let imageW: Int         // EXACT pixel width of the image the model receives (after downscale)
        let imageH: Int         // EXACT pixel height
        let bounds: CGRect      // captured display bounds — POINTS, top-left global origin (CGEvent space)
    }

    /// Grab the main display, downscale to max 1280px on the long side, JPEG @ 80% — same recipe Clicky uses.
    /// Composites every on-screen window EXCEPT our own (filtered by owner PID), so the agent never sees
    /// (and thus never targets/clicks) Clicky's own UI — while our panels stay fully visible to the user
    /// AND to other screen-capture clients like Zoom / Cap (we no longer rely on `sharingType = .none`).
    ///
    /// `imageW/imageH` are the TRUE pixel size of the returned JPEG (we redraw into that size), and `bounds`
    /// is the captured display in points. A caller maps a model pixel (px,py) to a click point with:
    ///   gx = px * (bounds.width  / imageW) + bounds.origin.x
    ///   gy = py * (bounds.height / imageH) + bounds.origin.y    (both spaces are top-left, so no Y flip)
    @MainActor private static var shotCounter = 0

    @MainActor
    static func grab() -> Shot? {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        // Our panels are visible to screen recorders the whole time; hide them for JUST this capture so the
        // agent never sees its own UI, then restore. The grab itself is the same plain capture as always.
        RecordMode.shared.hideForCapture()
        let captured = CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
                       ?? CGDisplayCreateImage(CGMainDisplayID())
        RecordMode.shared.restoreAfterCapture()
        guard let image = captured else { return nil }
        // LOCK THE COORDINATE SPACE: resize to a fixed long-edge the provider won't shrink further, and
        // declare THAT exact size. Full-res fails because the API downsamples our 3024px image to ~1000px
        // before the model sees it, so the model answers in ~1000-space while we'd map from 3024 → 3× error.
        // Lossless PNG (no quality loss), real pixels (no fractions) — we only fix the scale the model uses.
        let w = image.width, h = image.height
        let maxEdge: CGFloat = 1280
        let scale = min(1.0, maxEdge / CGFloat(max(w, h)))
        let tw = max(1, Int(CGFloat(w) * scale)), th = max(1, Int(CGFloat(h) * scale))
        guard let dst = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        dst.size = NSSize(width: tw, height: th)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: dst)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: .zero).draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = dst.representation(using: .png, properties: [:]) else { return nil }
        let kb = png.count / 1024
        // Save the EXACT image we send to the model, so we can open it and verify what it saw.
        shotCounter += 1
        let dir = "/tmp/clicky-shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/shot-\(shotCounter).png"
        try? png.write(to: URL(fileURLWithPath: path))
        log("SHOT #\(shotCounter) src=\(w)x\(h) sent=\(tw)x\(th)px png=\(kb)KB saved=\(path) display=\(Int(bounds.width))x\(Int(bounds.height))pt @\(Int(bounds.origin.x)),\(Int(bounds.origin.y))")
        return Shot(base64: png.base64EncodedString(), imageW: tw, imageH: th, bounds: bounds)
    }

    /// A zoomed-in, sharp crop around a screen point — used to localize a tiny target precisely.
    struct Zoom {
        let base64: String
        let imageW: Int          // pixel size of the crop image the model sees
        let imageH: Int
        let originPt: CGPoint    // top-left of the crop region in screen POINTS (global, top-left)
        let sizePt: CGSize       // crop region size in screen POINTS
    }

    /// Capture a sharp crop centered on screen point `p` (points), `half`*2 pt wide/tall, upscaled to
    /// `out` px on the long edge so a ~15px icon becomes ~60px and is easy to localize exactly.
    @MainActor
    static func grabZoom(around p: CGPoint, half: CGFloat = 110, out: Int = 900) -> Zoom? {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        guard let full = CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
                ?? CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
        let sx = CGFloat(full.width) / bounds.width, sy = CGFloat(full.height) / bounds.height   // px per pt
        let ox = min(max(bounds.minX, p.x - half), bounds.maxX - 1)
        let oy = min(max(bounds.minY, p.y - half), bounds.maxY - 1)
        let rw = min(half * 2, bounds.maxX - ox), rh = min(half * 2, bounds.maxY - oy)
        let cropPx = CGRect(x: (ox - bounds.minX) * sx, y: (oy - bounds.minY) * sy, width: rw * sx, height: rh * sy)
        guard rw > 4, rh > 4, let cropped = full.cropping(to: cropPx) else { return nil }
        let ow = out, oh = max(1, Int(CGFloat(out) * rh / rw))
        guard let dst = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: ow, pixelsHigh: oh,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        dst.size = NSSize(width: ow, height: oh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: dst)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cropped, size: .zero).draw(in: NSRect(x: 0, y: 0, width: ow, height: oh))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = dst.representation(using: .png, properties: [:]) else { return nil }
        shotCounter += 1
        let path = "/tmp/clicky-shots/zoom-\(shotCounter).png"
        try? FileManager.default.createDirectory(atPath: "/tmp/clicky-shots", withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: path))
        log("ZOOM #\(shotCounter) region \(Int(rw))x\(Int(rh))pt @\(Int(ox)),\(Int(oy)) → \(ow)x\(oh)px saved=\(path)")
        return Zoom(base64: png.base64EncodedString(), imageW: ow, imageH: oh,
                    originPt: CGPoint(x: ox, y: oy), sizePt: CGSize(width: rw, height: rh))
    }

    /// Composite all on-screen windows whose owner is NOT us, front-to-back. Returns nil if the
    /// window list can't be read (caller falls back to a full-display capture).
    private static func grabExcludingOwnWindows(bounds: CGRect) -> CGImage? {
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        var ids: [CGWindowID] = []
        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let num = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            ids.append(num)
        }
        guard !ids.isEmpty else { return nil }
        let cfArray = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) } as CFArray
        return CGImage(windowListFromArrayScreenBounds: bounds, windowArray: cfArray, imageOption: [.bestResolution])
    }
}
