import AppKit

/// Tab 1 — live, deterministic activity log (no AI).
@MainActor
final class ActivityPane: NSView {
    private let scroll = NSScrollView()
    private let text = NSTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        text.isEditable = false
        text.drawsBackground = false
        text.textColor = Theme.shared.inkDim
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = text
        addSubview(scroll)
        Theme.shared.observe(self) { [weak self] in self?.text.textColor = Theme.shared.inkDim }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); scroll.frame = bounds }

    func append(_ s: String) {
        let stamp = Self.fmt.string(from: Date())
        text.string += "\(stamp)  \(s)\n"
        text.scrollToEndOfDocument(nil)
        // cap length so it doesn't grow forever
        if text.string.count > 20000 { text.string = String(text.string.suffix(14000)) }
    }
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
}

/// Tab 2 — Grammarly-style AI chat. Header (title + new-chat + history), a transcript,
/// a greeting when empty, and a rounded composer with "+" and an up-arrow send button.
/// Backed by the shared `ChatStore` so conversations persist and carry context.
@MainActor
final class ChatPane: NSView {
    private let header = NSView()
    private let titleLabel = NSTextField(labelWithString: "AI Chat")
    private let newBtn = NSButton()
    private let historyBtn = NSButton()
    private let themeBtn = NSButton()
    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private let listStack = NSStackView()
    private var currentWork: WorkGroupView?
    private let greeting = NSTextField(labelWithString: "How can I help?")
    private let composer = NSView()
    private let input = NSTextField()
    private let sendBtn = NSButton()
    private let plusBtn = NSButton()
    private let chipsRow = NSView()

    // multiple image attachments (name + base64 JPEG), shown as removable chips above the input
    private var attachments: [(name: String, base64: String)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // header: title + new-chat + history
        addSubview(header)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        header.addSubview(titleLabel)
        configIcon(newBtn, "square.and.pencil", #selector(newChat))
        configIcon(historyBtn, "clock.arrow.circlepath", #selector(showHistory))
        configIcon(themeBtn, Theme.shared.toggleSymbol, #selector(toggleThemeTap))
        header.addSubview(newBtn); header.addSubview(historyBtn); header.addSubview(themeBtn)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 4
        listStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(listStack)
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            listStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 4),
            listStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4),
            listStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 8),
            listStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8),
        ])
        addSubview(scroll)

        // greeting shown when the conversation is empty
        let name = NSFullUserName().components(separatedBy: " ").first ?? ""
        greeting.stringValue = name.isEmpty ? "How can I help?" : "\(name), how can I help?"
        greeting.font = .systemFont(ofSize: 20, weight: .semibold)
        greeting.textColor = NSColor(white: 0.95, alpha: 1)
        addSubview(greeting)

        // rounded composer (taller, Grammarly style)
        composer.wantsLayer = true
        composer.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        composer.layer?.cornerRadius = 16
        composer.layer?.borderWidth = 1
        composer.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        addSubview(composer)

        input.placeholderString = "Ask AI"
        input.font = .systemFont(ofSize: 14)
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.textColor = .white
        input.target = self; input.action = #selector(send)
        composer.addSubview(input)

        // "+" attach/screenshot menu (bottom-left)
        plusBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        plusBtn.imagePosition = .imageOnly; plusBtn.isBordered = false
        plusBtn.contentTintColor = NSColor(white: 0.7, alpha: 1)
        plusBtn.target = self; plusBtn.action = #selector(showPlusMenu)
        composer.addSubview(plusBtn)

        // accent send button (arrow.up, bottom-right)
        sendBtn.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")
        sendBtn.imagePosition = .imageOnly
        sendBtn.isBordered = false
        sendBtn.contentTintColor = .white
        sendBtn.wantsLayer = true
        sendBtn.layer?.backgroundColor = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1).cgColor
        sendBtn.layer?.cornerRadius = 14
        sendBtn.target = self; sendBtn.action = #selector(sendOrStop)
        composer.addSubview(sendBtn)

        // row of removable attachment chips, above the input
        composer.addSubview(chipsRow)

        // also accept image files dragged onto the composer
        registerForDraggedTypes([.fileURL])

        applyTheme()
        Theme.shared.observe(self) { [weak self] in self?.applyTheme() }
        refreshEmptyState()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyTheme() {
        let t = Theme.shared
        titleLabel.textColor = t.ink
        greeting.textColor = t.ink
        input.textColor = t.ink
        composer.layer?.backgroundColor = t.well.cgColor
        composer.layer?.borderColor = t.hairline.cgColor
        plusBtn.contentTintColor = t.inkFaint
        newBtn.contentTintColor = t.inkFaint
        historyBtn.contentTintColor = t.inkFaint
        themeBtn.contentTintColor = t.inkFaint
        themeBtn.image = NSImage(systemSymbolName: t.toggleSymbol, accessibilityDescription: "Toggle theme")
        if !sending { reloadCurrent() }   // rebuild message views with the new palette
    }

    @objc private func toggleThemeTap() { Theme.shared.toggle() }

    private func configIcon(_ b: NSButton, _ symbol: String, _ action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageOnly
        b.isBordered = false
        b.contentTintColor = NSColor(white: 0.7, alpha: 1)
        b.target = self; b.action = action
    }

    override func layout() {
        super.layout()
        let w = bounds.width, pad: CGFloat = 8
        let headerH: CGFloat = 34
        header.frame = NSRect(x: 0, y: bounds.height - headerH, width: w, height: headerH)
        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(x: 4, y: (headerH - titleLabel.frame.height)/2, width: 160, height: titleLabel.frame.height)
        historyBtn.frame = NSRect(x: w - 28, y: (headerH - 22)/2, width: 22, height: 22)
        newBtn.frame = NSRect(x: w - 56, y: (headerH - 22)/2, width: 22, height: 22)
        themeBtn.frame = NSRect(x: w - 84, y: (headerH - 22)/2, width: 22, height: 22)

        let chipsH: CGFloat = attachments.isEmpty ? 0 : 34
        let composerH: CGFloat = 82 + chipsH
        composer.frame = NSRect(x: 0, y: pad, width: w, height: composerH)
        // bottom row: + (left) and send (right); input above it; chips row at the very top
        plusBtn.frame = NSRect(x: 10, y: 8, width: 26, height: 26)
        sendBtn.frame = NSRect(x: w - 38, y: 8, width: 28, height: 28)
        input.frame = NSRect(x: 14, y: 44, width: w - 28, height: 24)
        chipsRow.frame = NSRect(x: 8, y: 44 + 24 + 2, width: w - 16, height: chipsH)
        layoutChips()

        greeting.sizeToFit()
        greeting.frame = NSRect(x: 6, y: pad + composerH + 10, width: w - 12, height: greeting.frame.height)

        let top = pad + composerH + 8
        scroll.frame = NSRect(x: 0, y: top, width: w, height: bounds.height - top - headerH)
    }

    // MARK: sessions

    /// Clear and re-render the active session's turns (called when a session is started/switched).
    func reloadCurrent() {
        if sending { return }                 // don't wipe a live, in-progress run
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        currentWork = nil
        for t in ChatStore.shared.current.turns {
            if t.role == "You" {
                addUserRow(t.text)
            } else {
                if let saved = t.steps, !saved.isEmpty {   // restore the collapsed "Worked" group
                    let work = WorkGroupView()
                    addListRow(work)
                    work.loadSaved(saved)
                }
                addAssistantRow(t.text)
            }
        }
        refreshEmptyState()
        scrollToBottom()
    }

    private func refreshEmptyState() {
        greeting.isHidden = !ChatStore.shared.current.turns.isEmpty
    }

    @objc private func newChat() { ChatStore.shared.startNew() }

    @objc private func showHistory() {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)   // match the app's dark theme
        let sessions = ChatStore.shared.sessions
        if sessions.isEmpty { menu.addItem(withTitle: "No history", action: nil, keyEquivalent: "") }
        for s in sessions {
            let short = s.title.count > 28 ? String(s.title.prefix(27)) + "…" : s.title
            let item = NSMenuItem(title: short, action: #selector(pickSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.id.uuidString
            item.state = (s.id == ChatStore.shared.currentID) ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: historyBtn.frame.minX, y: historyBtn.frame.minY), in: header)
    }

    @objc private func pickSession(_ item: NSMenuItem) {
        guard let s = item.representedObject as? String, let id = UUID(uuidString: s) else { return }
        ChatStore.shared.switchTo(id)
    }

    @objc private func showPlusMenu() {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)   // match the app's dark theme
        let a = NSMenuItem(title: "Attach image…", action: #selector(attach), keyEquivalent: ""); a.target = self
        let b = NSMenuItem(title: "Attach current screen", action: #selector(captureScreen), keyEquivalent: ""); b.target = self
        menu.addItem(a); menu.addItem(b)
        menu.popUp(positioning: nil, at: NSPoint(x: plusBtn.frame.minX, y: plusBtn.frame.maxY), in: composer)
    }

    @objc private func attach() {
        // NSOpenPanel renders INSIDE our app, which (with the topmost transparent overlay) deadlocks.
        // So we present the file chooser from a SEPARATE process via osascript `choose file` — the
        // dialog belongs to osascript, not us, so our window/modal issues can't freeze it.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = """
            set theFiles to choose file with prompt "Choose image(s)" of type {"public.image"} with multiple selections allowed
            set out to ""
            repeat with f in theFiles
                set out to out & POSIX path of f & linefeed
            end repeat
            return out
            """
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let paths = out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            DispatchQueue.main.async {
                guard let self else { return }
                for p in paths {
                    if let img = NSImage(contentsOfFile: p), let b64 = self.jpegBase64(img) {
                        self.attachments.append(((p as NSString).lastPathComponent, b64))
                    }
                }
                self.needsLayout = true
            }
        }
    }

    @objc private func captureScreen() {
        guard let shot = ScreenCapture.grab() else { return }
        attachments.append(("current screen", shot.base64))
        needsLayout = true
    }

    // MARK: drag-and-drop image attach

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURL(from: sender) != nil ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = imageURL(from: sender), let img = NSImage(contentsOf: url),
              let b64 = jpegBase64(img) else { return false }
        attachments.append((url.lastPathComponent, b64))
        needsLayout = true
        return true
    }
    private func imageURL(from sender: NSDraggingInfo) -> URL? {
        guard let url = NSURL(from: sender.draggingPasteboard) as URL? else { return nil }
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp"].contains(ext) ? url : nil
    }

    // MARK: attachment chips

    private func layoutChips() {
        chipsRow.subviews.forEach { $0.removeFromSuperview() }
        guard !attachments.isEmpty else { return }
        var x: CGFloat = 0
        let h: CGFloat = 26
        for (i, att) in attachments.enumerated() {
            let name = att.name.count > 18 ? String(att.name.prefix(16)) + "…" : att.name
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 11)
            label.textColor = NSColor(white: 0.9, alpha: 1)
            label.sizeToFit()
            let lw = min(label.frame.width, 140)
            let chipW = 8 + 14 + 4 + lw + 6 + 16 + 8    // pad + 📎 + gap + label + gap + × + pad
            let chip = NSView(frame: NSRect(x: x, y: 2, width: chipW, height: h))
            chip.wantsLayer = true
            chip.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
            chip.layer?.cornerRadius = 8

            let icon = NSTextField(labelWithString: "📎")
            icon.font = .systemFont(ofSize: 10); icon.frame = NSRect(x: 8, y: (h-14)/2, width: 14, height: 14)
            chip.addSubview(icon)
            label.frame = NSRect(x: 26, y: (h - label.frame.height)/2, width: lw, height: label.frame.height)
            chip.addSubview(label)

            let x_ = NSButton(frame: NSRect(x: chipW - 22, y: (h-16)/2, width: 16, height: 16))
            x_.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")
            x_.imagePosition = .imageOnly; x_.isBordered = false
            x_.contentTintColor = NSColor(white: 0.6, alpha: 1)
            x_.tag = i; x_.target = self; x_.action = #selector(removeAttachment(_:))
            chip.addSubview(x_)

            chipsRow.addSubview(chip)
            x += chipW + 6
        }
    }

    @objc private func removeAttachment(_ sender: NSButton) {
        guard sender.tag < attachments.count else { return }
        attachments.remove(at: sender.tag)
        needsLayout = true
    }

    private var sending = false

    /// The Chat tab routes to the unified agent (chat or act). Set by the app.
    /// Second arg is the list of attached images (base64 JPEG) for extra visual context.
    var onSend: ((String, [String]) -> Void)?
    /// Called when the user taps Stop while a run is in progress.
    var onStop: (() -> Void)?

    /// The send button doubles as a Stop button while a run is in progress.
    @objc private func sendOrStop() { sending ? onStop?() : send() }

    private func setSending(_ on: Bool) {
        sending = on
        sendBtn.image = NSImage(systemSymbolName: on ? "stop.fill" : "arrow.up", accessibilityDescription: on ? "Stop" : "Send")
        sendBtn.layer?.backgroundColor = (on ? NSColor.systemRed : NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1)).cgColor
    }

    @objc private func send() {
        guard !sending else { return }                 // ignore double-trigger (Enter + default button)
        let q = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        setSending(true)
        input.stringValue = ""
        greeting.isHidden = true
        let imgs = attachments.map { $0.base64 }
        let suffix = attachments.isEmpty ? "" : "\n📎 _\(attachments.count) image\(attachments.count == 1 ? "" : "s") attached_"
        addUserRow(q + suffix)
        // start a fresh Working dropdown for this turn's reasoning + tool steps
        let work = WorkGroupView()
        work.onLayoutChange = { [weak self] in self?.scrollToBottom() }
        currentWork = work
        addListRow(work)
        attachments.removeAll()
        needsLayout = true
        onSend?(q, imgs)
    }

    /// One streamed step — the model's own reasoning prose, or a tool call (real name).
    /// Both go INSIDE the current Working dropdown.
    func agentStep(_ kind: Agent.StepKind, _ s: String) {
        switch kind {
        case .reasoning: currentWork?.addReasoning(s)
        case .tool:      currentWork?.addTool(s)
        }
    }

    /// Final agent answer (markdown), ends the turn: collapse the Working group, show the answer,
    /// and PERSIST the turn (with its work steps) so it survives reloads / relaunch.
    func agentReply(_ s: String) {
        currentWork?.finish()
        let savedSteps = currentWork?.steps
        currentWork = nil
        addAssistantRow(s)
        ChatStore.shared.addTurn(role: "Clicky", text: s, steps: savedSteps)
        setSending(false)
    }

    // MARK: view-based rows — right-aligned user bubble, plain left assistant

    private func addUserRow(_ text: String) {
        let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
        let bubble = NSView(); bubble.wantsLayer = true
        bubble.layer?.backgroundColor = (Theme.shared.isDark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.07)).cgColor
        bubble.layer?.cornerRadius = 13
        bubble.translatesAutoresizingMaskIntoConstraints = false
        let l = NSTextField(wrappingLabelWithString: "")
        l.attributedStringValue = renderMarkdown(text)
        l.textColor = Theme.shared.ink
        l.isSelectable = true; l.isEditable = false; l.drawsBackground = false; l.isBordered = false
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        bubble.addSubview(l); row.addSubview(bubble)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            l.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            l.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            l.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 48),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.78),
        ])
        addListRow(row)
    }

    private func addAssistantRow(_ md: String) {
        let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
        let l = NSTextField(wrappingLabelWithString: "")
        l.attributedStringValue = renderMarkdown(md)
        l.isSelectable = true; l.isEditable = false; l.drawsBackground = false; l.isBordered = false
        l.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            l.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -22),
            l.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            l.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        addListRow(row)
    }

    private func addListRow(_ v: NSView) {
        listStack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        scrollToBottom()
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scroll.layoutSubtreeIfNeeded()
            let h = self.doc.frame.height, vh = self.scroll.contentView.bounds.height
            self.scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, h - vh)))
            self.scroll.reflectScrolledClipView(self.scroll.contentView)
        }
    }

    /// Render markdown (bold, italic, inline code, links, lists) into styled attributed text.
    private func renderMarkdown(_ md: String) -> NSAttributedString {
        let base = Theme.shared.ink
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attr = try? AttributedString(markdown: md, options: opts) else {
            return NSAttributedString(string: md, attributes: [.font: bodyFont, .foregroundColor: base])
        }
        let ms = NSMutableAttributedString(attr)
        let full = NSRange(location: 0, length: ms.length)
        ms.addAttribute(.foregroundColor, value: base, range: full)
        // apply a base font everywhere a font isn't already set, and style code/bold
        ms.enumerateAttribute(.font, in: full) { value, range, _ in
            let existing = value as? NSFont
            var f = bodyFont
            if let e = existing {
                // preserve bold/italic traits the markdown parser applied
                let traits = e.fontDescriptor.symbolicTraits
                var d = bodyFont.fontDescriptor
                if traits.contains(.bold) || traits.contains(.italic) {
                    d = d.withSymbolicTraits(traits)
                }
                f = NSFont(descriptor: d, size: 13) ?? bodyFont
            }
            ms.addAttribute(.font, value: f, range: range)
        }
        // inline code → monospaced + subtle bg
        ms.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            if let v = value as? UInt,
               InlinePresentationIntent(rawValue: v).contains(.code) {
                ms.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: range)
                ms.addAttribute(.foregroundColor, value: NSColor(red: 0.55, green: 0.8, blue: 1, alpha: 1), range: range)
            }
        }
        return ms
    }

    private func jpegBase64(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return jpeg.base64EncodedString()
    }
}
