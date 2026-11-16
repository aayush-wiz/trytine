import AppKit

/// A full-screen, transparent, click-through window that draws our companion cursor on top of everything.
final class OverlayWindow: NSWindow {
    init() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        RecordMode.shared.registerAlwaysVisible(self)   // blue cursor stays visible in the agent's screenshot
        level = .screenSaver                 // float above everything
        ignoresMouseEvents = true            // CLICK-THROUGH: real cursor works underneath
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = CursorView(frame: frame)
    }
    override var canBecomeKey: Bool { false }
}

/// Draws the blue triangle "buddy" cursor and glides it to targets along an arced bézier path.
final class CursorView: NSView {
    private var pos: CGPoint = CGPoint(x: 200, y: 200)   // current position (view coords, origin bottom-left)
    private var angle: CGFloat = 0                        // facing direction (radians)
    private var visible = false
    private var timer: Timer?

    // animation state
    private var start = CGPoint.zero
    private var control = CGPoint.zero
    private var target = CGPoint.zero
    private var t: CGFloat = 1                            // progress 0..1 (1 == idle)
    private let duration: CGFloat = 0.9

    // follow mode: the buddy continuously trails the user's real cursor
    private var followMode = true
    private var lastMouse = CGPoint.zero

    // live HUD text (deterministic context, no AI)
    private var inspectCounter = 0

    override var isFlipped: Bool { false }

    func startFollowing() {
        followMode = true
        visible = true
        startLinkIfNeeded()
    }

    /// Point the buddy at a screen coordinate (top-left origin, as Claude/screenshots use).
    func point(toTopLeft p: CGPoint) {
        let h = bounds.height
        let dest = CGPoint(x: p.x, y: h - p.y)           // flip Y to AppKit bottom-left origin
        start = pos
        target = dest
        // lift the control point upward so the path arcs like a friendly gesture
        let mid = CGPoint(x: (start.x + target.x) / 2, y: (start.y + target.y) / 2)
        control = CGPoint(x: mid.x, y: mid.y + 160)
        t = 0
        followMode = false        // break away to point, then resume following
        visible = true
        startLinkIfNeeded()
    }

    func hide() {
        visible = false
        needsDisplay = true
    }

    private func startLinkIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        if followMode && t >= 1 {
            // sit just up-and-right of the real cursor, easing toward it so it feels alive
            let m = NSEvent.mouseLocation                 // global, bottom-left origin
            let screenH = NSScreen.main?.frame.height ?? bounds.height
            let local = CGPoint(x: m.x, y: m.y)           // overlay covers main screen at origin
            _ = screenH
            // sit EXACTLY on the real cursor (no offset) so the blue tip marks the precise cursor point
            let desired = CGPoint(x: local.x, y: local.y)
            let dx = desired.x - pos.x, dy = desired.y - pos.y
            if abs(dx) + abs(dy) > 0.3 { angle = atan2(dy, dx) }
            pos.x += dx * 0.18                            // smooth follow
            pos.y += dy * 0.18
            needsDisplay = true
            return
        }
        guard t < 1 else { return }
        t = min(1, t + (1.0 / 60.0) / duration)
        let e = easeInOut(t)
        // quadratic bézier: B(e) = (1-e)^2 P0 + 2(1-e)e C + e^2 P1
        let mt = 1 - e
        let x = mt * mt * start.x + 2 * mt * e * control.x + e * e * target.x
        let y = mt * mt * start.y + 2 * mt * e * control.y + e * e * target.y
        let newPos = CGPoint(x: x, y: y)
        let dx = newPos.x - pos.x, dy = newPos.y - pos.y
        if abs(dx) + abs(dy) > 0.01 { angle = atan2(dy, dx) }  // face direction of travel
        pos = newPos
        needsDisplay = true
        if t >= 1 { followMode = true }   // done pointing → resume trailing the cursor
    }

    private func easeInOut(_ x: CGFloat) -> CGFloat { x < 0.5 ? 2*x*x : 1 - pow(-2*x + 2, 2)/2 }

    override func draw(_ dirtyRect: NSRect) {
        guard visible, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: pos.x, y: pos.y)
        ctx.rotate(by: angle - .pi / 2)      // triangle points "up" by default
        // triangle with its TIP at the origin (= pos = the exact cursor/click point), body trailing behind
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))       // tip — sits exactly on the cursor point
        path.addLine(to: CGPoint(x: -7, y: -18))
        path.addLine(to: CGPoint(x: 0, y: -14))
        path.addLine(to: CGPoint(x: 7, y: -18))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setShadow(offset: .zero, blur: 5, color: NSColor.systemBlue.cgColor)
        ctx.setFillColor(NSColor.systemBlue.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
