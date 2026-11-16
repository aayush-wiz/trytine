import AppKit

/// A tiny command popup that appears right next to the mouse cursor (its own shortcut).
/// The user types a quick instruction — e.g. "complete this line", "click this", "fix this
/// sentence" — and the same unified agent acts in-place, using the focused field's current
/// text + the screen as context. Think of it as an inline, cursor-anchored version of the
/// command bar (vs. the notch island, which is global).
///
/// The input auto-grows as the user types, up to a max height, then scrolls — like a
/// professional composer box. Enter submits; Shift+Enter inserts a newline.
@MainActor
final class InlineBar: NSPanel, NSTextViewDelegate {
    private let pill = NSView()
    private let scroll = NSScrollView()
    private let textView = NSTextView()
    private let hint = NSTextField(labelWithString: "⏎")
    private let spinner = NSProgressIndicator()
    private let closeBtn = NSButton()

    private let barWidth: CGFloat = 380
    private let minBarHeight: CGFloat = 46
    private let maxBarHeight: CGFloat = 180
    private let hPad: CGFloat = 16      // left inset
    private let rPad: CGFloat = 58      // right inset (room for ⏎ + × / spinner)
    private let vPad: CGFloat = 12      // top+bottom inset (per side ~ vPad)
    private var topY: CGFloat = 0       // fixed top edge so the box grows downward

    /// Called when the user submits an instruction. Receives the raw instruction text.
    var onSubmit: ((String) -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 46),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        RecordMode.shared.register(self)       // sharingType per record-mode (.none hidden / .readOnly visible)
        level = .statusBar + 9
        // NB: no .transient — that makes macOS hide the panel the moment we activate the
        // target app, which looked like it "auto-closed". We dismiss it ourselves instead.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: barWidth, height: minBarHeight))
        contentView = root

        pill.frame = root.bounds
        pill.autoresizingMask = [.width, .height]
        pill.wantsLayer = true
        pill.layer?.backgroundColor = Theme.shared.panelBg.cgColor
        pill.layer?.cornerRadius = 12
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.65).cgColor
        root.addSubview(pill)

        // scrollable, auto-growing text input
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        pill.addSubview(scroll)

        textView.drawsBackground = false
        textView.textColor = Theme.shared.ink
        textView.insertionPointColor = .systemBlue
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        scroll.documentView = textView

        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = Theme.shared.inkFaint
        pill.addSubview(hint)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        pill.addSubview(spinner)

        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.contentTintColor = Theme.shared.inkFaint
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        pill.addSubview(closeBtn)
    }

    @objc private func closeClicked() { dismiss() }

    override var canBecomeKey: Bool { true }

    private func layoutPieces() {
        let b = pill.bounds
        scroll.frame = NSRect(x: hPad, y: vPad / 2, width: b.width - hPad - rPad, height: b.height - vPad)
        textView.frame = NSRect(origin: .zero, size: NSSize(width: scroll.contentSize.width, height: scroll.contentSize.height))
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        // controls pinned to the first line (top of the box), so they don't drift as it grows
        let rowY = b.height - minBarHeight / 2
        hint.frame = NSRect(x: b.width - 52, y: rowY - 8, width: 18, height: 16)
        spinner.frame = NSRect(x: b.width - 52, y: rowY - 9, width: 18, height: 18)
        closeBtn.frame = NSRect(x: b.width - 28, y: rowY - 9, width: 18, height: 18)
    }

    /// Vertically center the text within the visible area (centered when one line, top-aligned as it grows).
    private func centerText() {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let visible = scroll.contentSize.height
        let inset = max(2, (visible - used) / 2)
        textView.textContainerInset = NSSize(width: 0, height: inset)
    }

    /// Recompute window height from the text content, growing downward, then scrolling past max.
    private func resizeToFit() {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let wanted = min(max(used + vPad + 4, minBarHeight), maxBarHeight)
        scroll.hasVerticalScroller = (used + vPad + 4) > maxBarHeight
        var f = frame
        f.size.height = wanted
        f.origin.y = topY - wanted          // keep the top edge anchored
        setFrame(f, display: true)
        layoutPieces()
        centerText()
    }

    /// Show the bar anchored just below-right of a screen point (bottom-left origin, like mouse coords).
    func show(near p: CGPoint) {
        var x = p.x + 6
        var top = p.y - 8                   // top edge sits just below the cursor
        if let vf = (NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main)?.visibleFrame {
            x = min(max(vf.minX + 4, x), vf.maxX - barWidth - 4)
            top = min(top, vf.maxY - 4)
        }
        topY = top
        setFrame(NSRect(x: x, y: top - minBarHeight, width: barWidth, height: minBarHeight), display: false)
        textView.string = ""
        spinner.stopAnimation(nil)
        hint.isHidden = false
        textView.isEditable = true
        layoutPieces()
        centerText()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(textView)
    }

    /// Switch to a "working…" state while the agent runs.
    func setBusy(_ busy: Bool) {
        textView.isEditable = !busy
        hint.isHidden = busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    func dismiss() { orderOut(nil) }

    private func submit() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { dismiss(); return }
        onSubmit?(text)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) { resizeToFit() }

    /// Enter submits; Shift+Enter inserts a newline; Esc dismisses.
    func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                tv.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            submit()
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
        return false
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
}
