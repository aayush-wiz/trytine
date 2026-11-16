import AppKit

// Faithful port of Lakr233/NotchDrop's approach: one fixed, full-width transparent window
// hanging from the top; the black notch shape is drawn and animated INSIDE it (the window
// never resizes). Exact notch sizing + corner radii from NotchDrop.

extension NSScreen {
    var clickyNotchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let h = safeAreaInsets.top
        let full = frame.width
        let l = auxiliaryTopLeftArea?.width ?? 0
        let r = auxiliaryTopRightArea?.width ?? 0
        guard l > 0, r > 0 else { return .zero }
        return CGSize(width: full - l - r, height: h)
    }
}

enum IslandState { case compact, opened, command }

@MainActor
final class IslandWindow: NSPanel {
    let island = IslandView()

    /// Centered-at-top frame just large enough for a panel of the given outer width/height.
    /// Sizing the window to the panel (instead of a full-screen overlay) means it physically
    /// cannot cover — or block clicks on — anything else on screen.
    static func frame(outerWidth w: CGFloat, height h: CGFloat) -> NSRect {
        let s = NSScreen.main ?? NSScreen.screens.first!
        let winW = max(w + 60, 200), winH = h + 24
        // notched Macs: hug the very top (merge with the notch). Non-notched: sit just below the menu bar.
        let topY = s.clickyNotchSize == .zero ? s.visibleFrame.maxY - 4 : s.frame.maxY
        return NSRect(x: s.frame.midX - winW / 2, y: topY - winH, width: winW, height: winH)
    }

    init() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let n0 = screen.clickyNotchSize
        let nw = n0 == .zero ? 200 : n0.width, nh = n0 == .zero ? 32 : n0.height
        let rect = Self.frame(outerWidth: nw + 70 + 32, height: nh + 28)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        RecordMode.shared.register(self)       // sharingType per record-mode (.none hidden / .readOnly visible)
        level = .statusBar + 8                 // sit above the menu bar (NotchDrop trick)
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        contentView = island
        let n = screen.clickyNotchSize
        island.notch = n == .zero ? CGSize(width: 200, height: 32) : n
        island.hasRealNotch = n != .zero
        island.window_ = self
        let line = "NOTCH detect: size=\(n) safeTop=\(screen.safeAreaInsets.top) auxL=\(screen.auxiliaryTopLeftArea?.width ?? -1) auxR=\(screen.auxiliaryTopRightArea?.width ?? -1)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/clicky-debug.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        island.go(.compact)
    }
    override var canBecomeKey: Bool { true }
}

@MainActor
final class IslandView: NSView {
    weak var window_: IslandWindow?
    var notch: CGSize = .init(width: 200, height: 32)
    var hasRealNotch = true
    private var topInset: CGFloat { hasRealNotch ? notch.height : 0 }   // no reserved gap without a notch
    private(set) var state: IslandState = .compact

    // animated geometry
    private var animTimer: Timer?
    private var p: CGFloat = 0          // 0 = compact, 1 = opened
    private var pTarget: CGFloat = 0

    private let pillDot = NSView()
    private let pillLabel = NSTextField(labelWithString: "Clicky")
    private let expandBtn = NSButton()
    private let themeBtn = NSButton()
    private let teachBtn = NSButton()
    var onExpandSidebar: (() -> Void)?
    var onTeachToggle: (() -> Void)?
    var onTeachPauseToggle: (() -> Void)?
    var onTeachName: ((String, String) -> Void)?   // (name, description) submitted in the notch teach input
    private var teachNaming = false
    // recording controls shown on the MINIMIZED notch while teaching
    private let recDot = NSView()
    private let recLabel = NSTextField(labelWithString: "REC")
    private let recPauseBtn = NSButton()
    private let recStopBtn = NSButton()
    private var blinkTimer: Timer?
    private let tabs = NSSegmentedControl(labels: ["Activity", "Chat"], trackingMode: .selectOne, target: nil, action: nil)
    private let activity = ActivityPane()
    private let chat = ChatPane()
    private var tracking: NSTrackingArea?

    // command mode (the input drops out of the notch itself)
    private var expandedState: IslandState = .opened   // which expanded variant p animates toward
    private let cmdPill = NSView()
    private let cmdInput = NSTextField()
    private let cmdSend = NSButton()
    private let teachDescPill = NSView()
    private let teachDescInput = NSTextField()
    private let teachStartBtn = NSButton()
    private let cmdLogScroll = NSScrollView()
    private let cmdLog = NSTextView()
    private var cmdDots: Timer?
    private var cmdDotFrame = 0
    var onCommand: ((String) -> Void)?

    override var isFlipped: Bool { true }   // top-down coords, like SwiftUI

    override init(frame f: NSRect) {
        super.init(frame: f)
        wantsLayer = true
        pillDot.wantsLayer = true
        pillDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        pillDot.layer?.cornerRadius = 4
        addSubview(pillDot)
        pillLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pillLabel.textColor = Theme.shared.ink
        addSubview(pillLabel)
        // expand-to-sidebar button (left end of the compact pill)
        expandBtn.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Open sidebar")
        expandBtn.imagePosition = .imageOnly; expandBtn.isBordered = false
        expandBtn.contentTintColor = Theme.shared.inkDim
        expandBtn.target = self; expandBtn.action = #selector(expandTapped)
        addSubview(expandBtn)
        // light/dark theme toggle (shown in the expanded header)
        themeBtn.image = NSImage(systemSymbolName: Theme.shared.toggleSymbol, accessibilityDescription: "Toggle theme")
        themeBtn.imagePosition = .imageOnly; themeBtn.isBordered = false
        themeBtn.contentTintColor = Theme.shared.inkDim
        themeBtn.target = self; themeBtn.action = #selector(toggleTheme)
        addSubview(themeBtn)
        // teach-by-demonstration toggle (record a task → save as a replayable skill)
        teachBtn.image = NSImage(systemSymbolName: "graduationcap", accessibilityDescription: "Teach a task")
        teachBtn.imagePosition = .imageOnly; teachBtn.isBordered = false
        teachBtn.contentTintColor = Theme.shared.inkDim
        teachBtn.target = self; teachBtn.action = #selector(teachTapped)
        addSubview(teachBtn)
        tabs.selectedSegment = 0
        tabs.selectedSegmentBezelColor = .systemBlue       // blue selected tab (not the system orange accent)
        tabs.target = self; tabs.action = #selector(switchTab)
        addSubview(tabs)
        addSubview(activity); addSubview(chat)

        // command input (lives inside the notch shape so it looks attached)
        cmdPill.wantsLayer = true
        cmdPill.layer?.backgroundColor = Theme.shared.well.cgColor
        cmdPill.layer?.cornerRadius = 16
        addSubview(cmdPill)
        cmdInput.placeholderString = "Tell Clicky what to do…  e.g. “click the search bar”"
        cmdInput.font = .systemFont(ofSize: 13)
        cmdInput.isBezeled = false; cmdInput.drawsBackground = false; cmdInput.focusRingType = .none
        cmdInput.textColor = Theme.shared.ink
        cmdInput.usesSingleLineMode = false
        cmdInput.cell?.wraps = true; cmdInput.cell?.isScrollable = false
        cmdInput.lineBreakMode = .byWordWrapping
        cmdInput.allowsEditingTextAttributes = false
        cmdInput.target = self; cmdInput.action = #selector(submitCommand)
        cmdPill.addSubview(cmdInput)
        cmdSend.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")
        cmdSend.imagePosition = .imageOnly; cmdSend.isBordered = false; cmdSend.contentTintColor = .white
        cmdSend.wantsLayer = true
        cmdSend.layer?.backgroundColor = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor
        cmdSend.layer?.cornerRadius = 14
        cmdSend.target = self; cmdSend.action = #selector(submitCommand)
        cmdPill.addSubview(cmdSend)
        // second box: task DESCRIPTION (only shown in teach-naming mode)
        teachDescPill.wantsLayer = true
        teachDescPill.layer?.backgroundColor = Theme.shared.well.cgColor
        teachDescPill.layer?.cornerRadius = 16
        addSubview(teachDescPill)
        teachDescInput.placeholderString = "Description — what should it learn? (so the AI understands the task)"
        teachDescInput.font = .systemFont(ofSize: 13)
        teachDescInput.isBezeled = false; teachDescInput.drawsBackground = false; teachDescInput.focusRingType = .none
        teachDescInput.textColor = Theme.shared.ink
        teachDescInput.usesSingleLineMode = false
        teachDescInput.cell?.wraps = true; teachDescInput.cell?.isScrollable = false
        teachDescInput.lineBreakMode = .byWordWrapping
        teachDescInput.target = self; teachDescInput.action = #selector(submitCommand)
        teachDescPill.addSubview(teachDescInput)
        // explicit "Start" button (clearer than the arrow for beginning a recording)
        teachStartBtn.isBordered = false
        teachStartBtn.wantsLayer = true
        teachStartBtn.layer?.backgroundColor = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor
        teachStartBtn.layer?.cornerRadius = 10
        teachStartBtn.attributedTitle = NSAttributedString(string: "Start",
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 13)])
        teachStartBtn.target = self; teachStartBtn.action = #selector(submitCommand)
        addSubview(teachStartBtn)
        // recording controls on the minimized notch (blinking dot + pause/resume + stop)
        recDot.wantsLayer = true
        recDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recDot.layer?.cornerRadius = 4
        addSubview(recDot)
        recLabel.font = .boldSystemFont(ofSize: 11); recLabel.textColor = .systemRed
        addSubview(recLabel)
        recPauseBtn.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        recPauseBtn.imagePosition = .imageOnly; recPauseBtn.isBordered = false
        recPauseBtn.contentTintColor = Theme.shared.ink
        recPauseBtn.target = self; recPauseBtn.action = #selector(recPauseTapped)
        addSubview(recPauseBtn)
        recStopBtn.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
        recStopBtn.imagePosition = .imageOnly; recStopBtn.isBordered = false
        recStopBtn.contentTintColor = .systemRed
        recStopBtn.target = self; recStopBtn.action = #selector(recStopTapped)
        addSubview(recStopBtn)
        // streaming step log (the agent's thinking + actions appear here live)
        cmdLogScroll.drawsBackground = false
        cmdLogScroll.hasVerticalScroller = true
        cmdLog.isEditable = false
        cmdLog.isSelectable = true       // allow selecting + copying the log
        cmdLog.drawsBackground = false
        cmdLog.textColor = Theme.shared.inkDim
        cmdLog.font = .systemFont(ofSize: 12)
        cmdLog.textContainerInset = NSSize(width: 4, height: 4)
        cmdLogScroll.documentView = cmdLog
        addSubview(cmdLogScroll)

        Theme.shared.observe(self) { [weak self] in self?.applyTheme() }
    }

    @objc private func toggleTheme() { Theme.shared.toggle() }
    @objc private func teachTapped() { onTeachToggle?() }
    @objc private func recPauseTapped() { onTeachPauseToggle?(); refreshTeach() }
    @objc private func recStopTapped() { onTeachToggle?() }   // toggle stops when recording is active

    /// Reflect recording state: expanded header teach icon, the minimized-notch controls, and the blink.
    func refreshTeach() {
        let on = SkillRecorder.shared.active
        let paused = SkillRecorder.shared.paused
        teachBtn.image = NSImage(systemSymbolName: on ? "stop.circle.fill" : "graduationcap",
                                 accessibilityDescription: "Teach a task")
        teachBtn.contentTintColor = on ? NSColor.systemRed : Theme.shared.inkDim
        recPauseBtn.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill",
                                    accessibilityDescription: paused ? "Resume" : "Pause")
        recPauseBtn.contentTintColor = Theme.shared.ink
        // blink the red dot only while actively recording (steady when paused)
        if on, !paused { startBlink() } else { stopBlink(); recDot.alphaValue = paused ? 1 : 0 }
        // the compact pill width depends on `active`, so resize the window to match (else the pill stays
        // wide after stop and the expand button looks shoved to the right).
        syncWindow()
        needsLayout = true; needsDisplay = true
    }

    private func startBlink() {
        guard blinkTimer == nil else { return }
        recDot.alphaValue = 1
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recDot.alphaValue = self.recDot.alphaValue > 0.5 ? 0.15 : 1
            }
        }
        RunLoop.main.add(t, forMode: .common); blinkTimer = t
    }
    private func stopBlink() { blinkTimer?.invalidate(); blinkTimer = nil }

    /// Restyle the themed sub-controls and redraw the notch surface.
    private func applyTheme() {
        let t = Theme.shared
        pillLabel.textColor = t.ink
        cmdInput.textColor = t.ink
        cmdLog.textColor = t.inkDim
        cmdPill.layer?.backgroundColor = t.well.cgColor
        expandBtn.contentTintColor = t.inkDim
        themeBtn.image = NSImage(systemSymbolName: t.toggleSymbol, accessibilityDescription: "Toggle theme")
        themeBtn.contentTintColor = t.inkDim
        needsDisplay = true; needsLayout = true
    }

    @objc private func expandTapped() { onExpandSidebar?() }

    func enterCommand() {
        teachNaming = false
        cmdInput.stringValue = ""
        cmdInput.placeholderString = "Ask Clicky to do something…"
        cmdLog.string = ""
        go(.command)
        window_?.makeFirstResponder(cmdInput)
    }

    /// Open the notch with TWO boxes — skill name + description — to define a task to learn.
    func enterTeachName() {
        teachNaming = true
        cmdInput.stringValue = ""; teachDescInput.stringValue = ""
        cmdInput.placeholderString = "Skill name — e.g. Filter spreadsheet by amount"
        cmdLog.string = ""
        go(.command)
        appendStepRaw("🎓 Name the skill + describe what to learn, then press return.", color: .systemBlue, bold: false)
        window_?.makeFirstResponder(cmdInput)
    }

    @objc private func submitCommand() {
        if teachNaming {
            let name = cmdInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = teachDescInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { window_?.makeFirstResponder(cmdInput); return }
            teachNaming = false
            cmdInput.stringValue = ""; teachDescInput.stringValue = ""
            appendStepRaw("🎓 Learning: \(name) — go ahead and do it. Tap ⏹ to stop.", color: .systemBlue, bold: true)
            onTeachName?(name, desc)
            go(.compact)              // get out of the way while the user demonstrates
            return
        }
        let q = cmdInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        cmdInput.stringValue = ""
        appendStepRaw("⌘ \(q)", color: .systemBlue, bold: true)
        startThinkingLine()
        onCommand?(q)
    }

    private func startThinkingLine() {
        cmdDots?.invalidate()
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cmdDotFrame = (self.cmdDotFrame + 1) % 4
                self.setThinkingDots(String(repeating: "● ", count: self.cmdDotFrame + 1))
            }
        }
        RunLoop.main.add(t, forMode: .common); cmdDots = t
    }
    private var thinkingLen = 0
    private func setThinkingDots(_ s: String) {
        guard let ts = cmdLog.textStorage else { return }
        if thinkingLen > 0 { ts.deleteCharacters(in: NSRange(location: ts.length - thinkingLen, length: thinkingLen)) }
        let line = "  \(s)\n"
        thinkingLen = (line as NSString).length
        ts.append(NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(white: 0.5, alpha: 1)]))
        cmdLog.scrollToEndOfDocument(nil)
    }
    private func clearThinkingDots() {
        cmdDots?.invalidate(); cmdDots = nil
        if thinkingLen > 0, let ts = cmdLog.textStorage {
            ts.deleteCharacters(in: NSRange(location: ts.length - thinkingLen, length: thinkingLen)); thinkingLen = 0
        }
    }

    private func appendStepRaw(_ s: String, color: NSColor, bold: Bool) {
        clearThinkingDots()
        let f = bold ? NSFont.boldSystemFont(ofSize: 12.5) : NSFont.systemFont(ofSize: 12)
        cmdLog.textStorage?.append(NSAttributedString(string: "\(s)\n", attributes: [.font: f, .foregroundColor: color]))
        cmdLog.scrollToEndOfDocument(nil)
        animateGrow()      // grow the panel toward the new content height
    }

    private func animateGrow() {
        // grow the window + shape toward the new content height as steps stream in.
        syncWindow(); needsLayout = true; needsDisplay = true
    }

    /// Append one live agent step, then resume the thinking indicator for the next step.
    func appendStep(_ s: String) {
        appendStepRaw("• \(s)", color: NSColor(white: 0.9, alpha: 1), bold: false)
        startThinkingLine()
    }

    func setCommandResult(_ s: String) {
        appendStepRaw("✓ \(s)", color: .systemGreen, bold: true)
    }

    func commandDone() { clearThinkingDots() }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func switchTab() {
        activity.isHidden = tabs.selectedSegment != 0
        chat.isHidden = tabs.selectedSegment != 1
        if tabs.selectedSegment == 1 { chat.reloadCurrent() }   // render the active session
        needsLayout = true
    }

    // MARK: geometry per state.  compact = a VISIBLE pill that hangs below the notch.
    private func geom(_ s: IslandState) -> (w: CGFloat, h: CGFloat, r: CGFloat) {
        switch s {
        case .compact:
            let w = SkillRecorder.shared.active ? notch.width + 150 : notch.width + 70   // wider for rec controls
            return (w, topInset + 28, 16)
        case .opened:  return (580, 540, 26)
        case .command:
            if teachNaming { return (560, topInset + 142, 24) }   // name box + description box + Start button
            // start small (just the input); grow with the step log up to a cap, then fix.
            var contentH: CGFloat = 0
            if let lm = cmdLog.layoutManager, let tc = cmdLog.textContainer {
                lm.ensureLayout(for: tc)
                contentH = lm.usedRect(for: tc).height
            }
            let logArea = contentH > 1 ? min(contentH + 18, 230) : 0
            return (560, topInset + 62 + logArea, 24)
        }
    }
    private var current: (w: CGFloat, h: CGFloat, r: CGFloat) {
        let c = geom(.compact), o = geom(expandedState)
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        return (lerp(c.w, o.w), lerp(c.h, o.h), lerp(c.r, o.r))
    }

    func go(_ s: IslandState) {
        state = s
        if s != .compact { expandedState = s }
        pTarget = (s == .compact) ? 0 : 1
        if s != .compact { window_?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        startAnim()
    }
    private func startAnim() {
        animTimer?.invalidate()
        let t = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if abs(self.p - self.pTarget) < 0.001 {
                    self.p = self.pTarget; self.animTimer?.invalidate(); self.animTimer = nil
                } else {
                    self.p += (self.pTarget - self.p) * 0.28
                }
                self.syncWindow()
                self.needsDisplay = true
                self.needsLayout = true
            }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    /// Resize the host window to exactly fit the current shape — so it never covers the rest of the screen.
    func syncWindow() {
        let g = current
        window_?.setFrame(IslandWindow.frame(outerWidth: g.w + g.r * 2, height: g.h), display: false)
    }

    // MARK: notch silhouette (concave top ears + convex rounded bottom)
    private func notchPath(cx: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat) -> NSBezierPath {
        let inner = w
        let ow = inner + r * 2
        let left = cx - ow/2, right = cx + ow/2
        let top: CGFloat = 0, bot = h
        let path = NSBezierPath()
        path.move(to: CGPoint(x: left, y: top))
        // top-left concave ear
        path.curve(to: CGPoint(x: left + r, y: top + r),
                   controlPoint1: CGPoint(x: left + r*0.55, y: top),
                   controlPoint2: CGPoint(x: left + r, y: top + r*0.45))
        path.line(to: CGPoint(x: left + r, y: bot - r))
        // bottom-left convex
        path.curve(to: CGPoint(x: left + r*2, y: bot),
                   controlPoint1: CGPoint(x: left + r, y: bot - r*0.45),
                   controlPoint2: CGPoint(x: left + r*1.45, y: bot))
        path.line(to: CGPoint(x: right - r*2, y: bot))
        // bottom-right convex
        path.curve(to: CGPoint(x: right - r, y: bot - r),
                   controlPoint1: CGPoint(x: right - r*1.45, y: bot),
                   controlPoint2: CGPoint(x: right - r, y: bot - r*0.45))
        path.line(to: CGPoint(x: right - r, y: top + r))
        // top-right concave ear
        path.curve(to: CGPoint(x: right, y: top),
                   controlPoint1: CGPoint(x: right - r, y: top + r*0.45),
                   controlPoint2: CGPoint(x: right - r*0.55, y: top))
        path.close()
        return path
    }

    override func draw(_ dirty: NSRect) {
        let g = current, cx = bounds.width/2
        let path: NSBezierPath
        if hasRealNotch {
            path = notchPath(cx: cx, w: g.w, h: g.h, r: g.r)
        } else {
            // no notch → a clean rounded panel (all corners), no fake ears
            let ow = g.w + g.r * 2
            path = NSBezierPath(roundedRect: NSRect(x: cx - ow/2, y: 0, width: ow, height: g.h), xRadius: g.r, yRadius: g.r)
        }
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.setShadow(offset: CGSize(width: 0, height: -2), blur: 22,
                       color: NSColor.black.withAlphaComponent(0.6).cgColor)
        // vertical charcoal gradient (professional, not flat black)
        path.addClip()
        let grad = NSGradient(colors: [Theme.shared.surfaceTop, Theme.shared.surfaceBot])
        grad?.draw(in: path, angle: -90)
        ctx?.setShadow(offset: .zero, blur: 0, color: nil)
        // subtle accent hairline along the bottom curve
        let accent = NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 0.0 + 0.7 * p)
        accent.setStroke(); path.lineWidth = 1; path.stroke()

        // chevron hint so users know it opens/closes (▼ compact = open, ▲ when open = close).
        // Hidden while the minimized recording HUD is up (its ⏸/⏹ controls occupy that side); it redraws
        // after stop because refreshTeach() sets needsDisplay.
        if SkillRecorder.shared.active && p < 0.5 { return }
        let down = p < 0.5
        let cw: CGFloat = 7
        let chx: CGFloat, chy: CGFloat
        if down {
            // resting: right side, aligned with the status text (kept off the curved edge)
            chx = cx + g.w/2 - 26
            chy = topInset + (g.h - topInset)/2
        } else {
            chx = cx; chy = g.h - 12
        }
        let chev = NSBezierPath()
        chev.move(to: CGPoint(x: chx - cw, y: down ? chy - 3 : chy + 3))
        chev.line(to: CGPoint(x: chx, y: down ? chy + 3 : chy - 3))
        chev.line(to: CGPoint(x: chx + cw, y: down ? chy - 3 : chy + 3))
        chev.lineWidth = 2
        chev.lineCapStyle = .round; chev.lineJoinStyle = .round
        Theme.shared.ink.withAlphaComponent(0.6).setStroke()
        chev.stroke()
    }

    // MARK: interaction (click-through outside the notch shape)
    override func mouseDown(with e: NSEvent) { go(state == .opened ? .compact : .opened) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let g = current, cx = bounds.width/2
        let local = convert(point, from: superview)
        let region = NSRect(x: cx - (g.w + g.r*2)/2, y: 0, width: g.w + g.r*2, height: g.h)
        return region.contains(local) ? super.hitTest(point) : nil
    }

    // MARK: content layout
    override func layout() {
        super.layout()
        let g = current, cx = bounds.width/2, inset = topInset
        let expanded = p > 0.5
        let isCmd = expandedState == .command
        let tabsOn = expanded && !isCmd
        tabs.isHidden = !tabsOn
        activity.isHidden = !tabsOn || tabs.selectedSegment != 0
        chat.isHidden = !tabsOn || tabs.selectedSegment != 1
        // command controls visible only in command expansion
        let cmdOn = expanded && isCmd
        cmdPill.isHidden = !cmdOn; cmdInput.isHidden = !cmdOn
        let descOn = cmdOn && teachNaming
        cmdSend.isHidden = !cmdOn || teachNaming             // arrow only for normal command mode
        teachDescPill.isHidden = !descOn; teachDescInput.isHidden = !descOn
        teachStartBtn.isHidden = !descOn                     // explicit Start button only while naming
        cmdLogScroll.isHidden = !cmdOn || teachNaming        // hide the step log while naming a skill
        let recOn = !expanded && SkillRecorder.shared.active     // minimized notch while recording
        recDot.isHidden = !recOn; recLabel.isHidden = !recOn
        recPauseBtn.isHidden = !recOn; recStopBtn.isHidden = !recOn
        pillDot.isHidden = cmdOn || recOn; pillLabel.isHidden = cmdOn || recOn
        expandBtn.isHidden = expanded || recOn   // hide the expand arrow while the rec HUD is showing
        themeBtn.isHidden = !tabsOn              // only in the expanded (non-command) header
        teachBtn.isHidden = !tabsOn              // shown alongside the theme toggle in the header

        pillLabel.sizeToFit()
        let lw = pillLabel.frame.width, lh = pillLabel.frame.height

        if cmdOn {
            // command bar drops out of the notch — one attached piece, with a live step log under it
            let m: CGFloat = 16
            cmdPill.frame = NSRect(x: cx - g.w/2 + m, y: inset + 14, width: g.w - m*2, height: 34)
            let pw = cmdPill.frame.width
            cmdInput.frame = NSRect(x: 14, y: 7, width: pw - 14 - 44, height: 20)
            cmdSend.frame = NSRect(x: pw - 36, y: 3, width: 28, height: 28)
            if teachNaming {
                // box 1 = name (above), box 2 = description (here), then a clear Start button
                teachDescPill.frame = NSRect(x: cx - g.w/2 + m, y: inset + 54, width: g.w - m*2, height: 34)
                teachDescInput.frame = NSRect(x: 14, y: 7, width: teachDescPill.frame.width - 28, height: 20)
                teachStartBtn.frame = NSRect(x: cx - g.w/2 + m, y: inset + 96, width: g.w - m*2, height: 30)
            }
            let logTop = inset + 58
            cmdLogScroll.frame = NSRect(x: cx - g.w/2 + m, y: logTop, width: g.w - m*2, height: g.h - logTop - 14)
        } else if expanded {
            let leftX = cx - g.w/2 + 20
            pillDot.frame = NSRect(x: leftX, y: inset + 8, width: 8, height: 8)
            pillLabel.frame = NSRect(x: leftX + 16, y: inset + 4, width: lw, height: lh)
            themeBtn.frame = NSRect(x: cx + g.w/2 - 48, y: inset + 4, width: 24, height: 24)
            teachBtn.frame = NSRect(x: cx + g.w/2 - 76, y: inset + 4, width: 24, height: 24)
            refreshTeach()
            tabs.frame = NSRect(x: cx - g.w/2 + 16, y: inset + 30, width: g.w - 32, height: 28)
            let top = inset + 30 + 28 + 10
            let rect = NSRect(x: cx - g.w/2 + 14, y: top, width: g.w - 28, height: g.h - top - 14)
            activity.frame = rect; chat.frame = rect
        } else if SkillRecorder.shared.active {
            // minimized recording HUD:   ● REC            ⏸  ⏹
            let cy = inset + (g.h - inset)/2
            recDot.frame = NSRect(x: cx - g.w/2 + 16, y: cy - 4, width: 8, height: 8)
            recLabel.sizeToFit()
            recLabel.frame = NSRect(x: cx - g.w/2 + 30, y: cy - recLabel.frame.height/2,
                                    width: recLabel.frame.width, height: recLabel.frame.height)
            // chevron is hidden while recording, so the controls take the right side cleanly
            recStopBtn.frame  = NSRect(x: cx + g.w/2 - 28, y: cy - 9, width: 18, height: 18)
            recPauseBtn.frame = NSRect(x: cx + g.w/2 - 54, y: cy - 9, width: 18, height: 18)
        } else {
            let total = 8 + 8 + lw
            let sx = cx - total/2
            let cy = inset + (g.h - inset)/2
            pillDot.frame = NSRect(x: sx, y: cy - 4, width: 8, height: 8)
            pillLabel.frame = NSRect(x: sx + 16, y: cy - lh/2, width: lw, height: lh)
            // expand button at the LEFT end of the pill
            expandBtn.frame = NSRect(x: cx - g.w/2 + 8, y: cy - 9, width: 18, height: 18)
        }
    }

    func appendActivity(_ s: String) { activity.append(s) }
    func setStatus(_ s: String) { pillLabel.stringValue = s; needsLayout = true }

    // Chat tab ⇄ unified agent
    var onChatSend: ((String, [String]) -> Void)? { didSet { chat.onSend = onChatSend } }
    var onChatStop: (() -> Void)? { didSet { chat.onStop = onChatStop } }
    func chatStep(_ kind: Agent.StepKind, _ s: String) { chat.agentStep(kind, s) }
    func chatReply(_ s: String) { chat.agentReply(s) }
    func reloadChat() { chat.reloadCurrent() }
}
