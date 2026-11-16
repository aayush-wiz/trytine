import AppKit

/// A floating, draggable chat sidebar (like a Copilot panel) that docks on the right but can be
/// moved anywhere. Hosts a ChatPane wired to the same unified agent.
@MainActor
final class SidebarWindow: NSPanel, NSWindowDelegate {
    let chat = ChatPane()
    private let header = NSView()
    private let titleLabel = NSTextField(labelWithString: "Tine")
    private let closeBtn = NSButton()

    init() {
        let s = NSScreen.main ?? NSScreen.screens.first!
        let w: CGFloat = 440, h: CGFloat = 640
        let rect = NSRect(x: s.visibleFrame.maxX - w - 16, y: s.visibleFrame.midY - h/2, width: w, height: h)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        RecordMode.shared.register(self)       // sharingType per record-mode (.none hidden / .readOnly visible)
        level = .floating
        isMovableByWindowBackground = true          // drag from anywhere
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 320, height: 380)    // resizable by dragging edges
        delegate = self

        let root = NSView(frame: NSRect(origin: .zero, size: rect.size))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 1
        contentView = root

        // draggable header bar
        header.wantsLayer = true
        root.addSubview(header)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        header.addSubview(titleLabel)
        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeBtn.imagePosition = .imageOnly; closeBtn.isBordered = false
        closeBtn.target = self; closeBtn.action = #selector(hide)
        header.addSubview(closeBtn)

        root.addSubview(chat)
        applyTheme()
        Theme.shared.observe(self) { [weak self] in self?.applyTheme() }
        layoutPieces()
    }

    private func applyTheme() {
        let t = Theme.shared
        contentView?.layer?.backgroundColor = t.panelBg.cgColor
        contentView?.layer?.borderColor = t.hairline.cgColor
        header.layer?.backgroundColor = t.headerBg.cgColor
        titleLabel.textColor = t.ink
        closeBtn.contentTintColor = t.inkFaint
    }

    override var canBecomeKey: Bool { true }

    func windowDidResize(_ notification: Notification) { layoutPieces() }

    private func layoutPieces() {
        guard let root = contentView else { return }
        let b = root.bounds, hh: CGFloat = 40
        header.frame = NSRect(x: 0, y: b.height - hh, width: b.width, height: hh)
        titleLabel.frame = NSRect(x: 16, y: (hh-18)/2, width: 200, height: 18)
        closeBtn.frame = NSRect(x: b.width - 34, y: (hh-26)/2, width: 26, height: 26)
        chat.frame = NSRect(x: 8, y: 8, width: b.width - 16, height: b.height - hh - 12)
    }

    func toggle() { isVisible ? hide() : show() }
    func show() {
        layoutPieces()
        chat.reloadCurrent()                 // render the active session's messages on open
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
    @objc func hide() { orderOut(nil) }
}
