import AppKit
import AVFoundation
import Speech

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlay = OverlayWindow()
    let islandWin = IslandWindow()
    let sidebar = SidebarWindow()
    let inlineBar = InlineBar()
    let speech = AVSpeechSynthesizer()
    let voice = SpeechManager()
    var statusItem: NSStatusItem!
    var monitor: Any?
    var activityTimer: Timer?
    var lastSig = ""
    var typeBuffer = ""
    var typeApp = ""
    var typeFlushTimer: Timer?
    var lastTyped = ""

    func log(_ s: String) {
        let line = "\(Date()) \(s)\n"
        if let h = FileHandle(forWritingAtPath: "/tmp/clicky-debug.log") {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            try? line.write(toFile: "/tmp/clicky-debug.log", atomically: true, encoding: .utf8)
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        log("didFinishLaunching start")
        Theme.shared.apply()   // restore saved light/dark theme app-wide (menus included)
        log("accessibility granted: \(Inspector.ensureAccessibility())")

        // Menu bar FIRST, so the icon shows even if the overlay has issues.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "▲"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🎙 Start / Stop Voice Command", action: #selector(toggleVoiceMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⌨️ Ask Clicky (type)…", action: #selector(ask), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "✦ Inline at cursor (⌃⌥K)…", action: #selector(askInline), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "⏹ Stop running task (⌃⌥S)", action: #selector(stopRunMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "🌗 Toggle light / dark theme", action: #selector(toggleThemeMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Voice hotkey: ⌃⌥Space (needs Accessibility)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        log("status item created")

        // standard Edit menu so Cmd+C/V/X/A work in the input + log (an accessory app has none by default)
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu

        // track the most-recent real app (for chat-initiated tasks, since we're frontmost while chatting)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.localizedName != "ClickyMine" {
                self?.lastFrontmostPID = app.processIdentifier
            }
        }
        // island Chat tab → unified agent
        islandWin.island.onChatSend = { [weak self] m, imgs in
            self?.runAgent(m, images: imgs, step: { k, s in self?.islandWin.island.chatStep(k, s) },
                              reply: { self?.islandWin.island.chatReply($0) })
        }
        // sidebar chat → same unified agent
        sidebar.chat.onSend = { [weak self] m, imgs in
            self?.runAgent(m, images: imgs, step: { k, s in self?.sidebar.chat.agentStep(k, s) },
                              reply: { self?.sidebar.chat.agentReply($0) })
        }
        // Stop button in either chat surface cancels the running task
        islandWin.island.onChatStop = { [weak self] in self?.stopRun() }
        sidebar.chat.onStop = { [weak self] in self?.stopRun() }
        // left expand button on the island opens / hides the draggable sidebar
        islandWin.island.onExpandSidebar = { [weak self] in self?.sidebar.toggle() }
        islandWin.island.onTeachToggle = { [weak self] in self?.toggleTeaching() }
        islandWin.island.onTeachName = { [weak self] name, desc in self?.beginTeaching(name, desc) }
        islandWin.island.onTeachPauseToggle = { [weak self] in
            let r = SkillRecorder.shared
            if r.paused { r.resume() } else { r.pause() }
            self?.islandWin.island.setStatus(r.paused ? "⏸ Paused" : "🔴 Teaching: \(r.name)")
        }

        // when the active chat session changes (new / switched / history), reload BOTH chat surfaces
        ChatStore.shared.onChange = { [weak self] in
            self?.islandWin.island.reloadChat()
            self?.sidebar.chat.reloadCurrent()
        }

        // inline cursor bar → unified agent, acting in-place at the cursor
        inlineBar.onSubmit = { [weak self] instruction in self?.runInline(instruction) }

        // Overlay AFTER the run loop is alive — defer one tick so the render server is ready.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlay.orderFrontRegardless()
            self.log("overlay ordered front")
            (self.overlay.contentView as? CursorView)?.startFollowing()
            self.islandWin.orderFrontRegardless()
            self.startActivityFeed()
            self.log("island + activity feed started")
        }

        // Global hotkey: Control + Option + Space → typed command box → screenshot → AI → cursor acts
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.modifierFlags.contains([.control, .option]) {
                if e.keyCode == 49 { self?.ask() }              // ⌃⌥Space → notch command bar
                else if e.keyCode == 40 { self?.askInline() }   // ⌃⌥K → inline cursor bar
                else if e.keyCode == 1 { self?.stopRun() }      // ⌃⌥S → STOP the running task
            }
        }

        // Monitor every real click — deterministic, no AI: log what the user clicked.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            self?.flushTyping()
            let c = Inspector.current()
            if c.app == "ClickyMine" { return }                 // ignore our own UI
            let what = c.label.isEmpty ? c.role : "\(c.role) “\(c.label)”"
            let line = "🖱 CLICK  \(c.app) › \(what)  @\(Int(c.mouse.x)),\(Int(c.mouse.y))"
            self?.log(line)
            self?.islandWin.island.appendActivity("🖱 CLICK  \(c.app) › \(what)")
            SkillRecorder.shared.capture(line)              // tee into the demonstration if teaching
        }

        // Capture what the user TYPES (keystrokes), buffered into words/lines.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleTyping(e)
        }
        // also local (when our own window is focused)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.modifierFlags.contains([.control, .option]) {
                if e.keyCode == 49 { self?.ask(); return nil }
                if e.keyCode == 40 { self?.askInline(); return nil }
                if e.keyCode == 1 { self?.stopRun(); return nil }
            }
            return e
        }
    }

    @objc func toggleVoiceMenu() { toggleVoice() }
    @objc func toggleThemeMenu() { Theme.shared.toggle() }

    /// Notch 🎓 button: if idle, open the notch input to name the task; if recording, stop & save.
    @objc func toggleTeaching() {
        if SkillRecorder.shared.active { stopTeaching() }
        else { islandWin.island.enterTeachName() }       // opens the notch input (no modal alert)
        islandWin.island.refreshTeach()
    }

    /// Called when the user submits the task name + description in the notch → start capturing the demo.
    func beginTeaching(_ name: String, _ description: String) {
        SkillRecorder.shared.start(name: name, description: description)
        islandWin.island.setStatus("🔴 Teaching: \(name)")
        islandWin.island.appendActivity("🎓 TEACH started · \(name) — perform the task now, then tap ⏹")
        islandWin.island.refreshTeach()
    }

    @objc func stopTeaching() {
        guard let trace = SkillRecorder.shared.stop() else {
            islandWin.island.setStatus("Not teaching"); return
        }
        islandWin.island.refreshTeach()
        islandWin.island.appendActivity("🎓 TEACH stopped · turning \(trace.lines.count) actions into a skill…")
        islandWin.island.setStatus("🎓 Saving skill…")
        Task { @MainActor in
            let plan = (try? await Claude.summarizeSkill(name: trace.name, description: trace.description, activity: trace.lines)) ?? ""
            let skill = Skill(name: trace.name, description: trace.description,
                              plan: plan.isEmpty ? trace.lines.joined(separator: "\n") : plan,
                              rawActivity: trace.lines, createdAt: Date())
            SkillStore.save(skill)
            islandWin.island.appendActivity("🎓 Saved skill · “\(trace.name)”. Ask the chat to do it any time.")
            islandWin.island.setStatus("🎓 Saved: \(trace.name)")
            // clear the status back to normal so it doesn't stick on the pill forever
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !SkillRecorder.shared.active { islandWin.island.setStatus("Clicky") }
        }
    }

    /// Push-to-talk: first ⌃⌥Space starts listening, second stops and runs the command.
    func toggleVoice() {
        log("toggleVoice: listening=\(voice.isListening)")
        if voice.isListening {
            voice.stop { [weak self] transcript in
                guard let self else { return }
                self.islandWin.island.setStatus("Clicky")
                let q = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { self.speak("I didn't catch that."); return }
                self.islandWin.island.appendActivity("🎙 VOICE → “\(q)”")
                self.run(question: q)
            }
            return
        }
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        log("voice auth status: speech=\(speechStatus.rawValue) mic=\(micStatus.rawValue)")

        // If mic isn't already granted, DON'T trigger the in-app prompt (it SIGKILLs this app).
        // Tell the user to grant it in System Settings instead, and open the pane.
        guard micStatus == .authorized, speechStatus == .authorized else {
            speak("Please enable Clicky Mine under Microphone in System Settings, then try again.")
            islandWin.island.setStatus("⚠️ Enable Mic in Settings")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            return
        }

        do {
            voice.onPartial = { [weak self] t in self?.islandWin.island.setStatus("🎙 " + String(t.suffix(24))) }
            try voice.start()
            log("voice.start() OK")
            islandWin.island.setStatus("🎙 Listening…")
            speak("Listening")
        } catch {
            speak("Microphone unavailable.")
            log("voice start error: \(error.localizedDescription)")
        }
    }

    /// Poll deterministic context ~1×/sec; log to Activity tab when app/window/element changes.
    func startActivityFeed() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // what the user is typing, read live from the focused text field
            if let t = Inspector.focusedTyping(), t.app != "ClickyMine", t.text != self.lastTyped {
                self.lastTyped = t.text
                let line = "⌨️ TYPING  \(t.app) › “\(t.text)”"
                self.log(line)
                self.islandWin.island.appendActivity(line)
            }

            let c = Inspector.current()
            if c.app == "ClickyMine" { return }                 // ignore hovering our own UI
            let where_ = c.label.isEmpty ? c.role : "\(c.role): \(c.label)"
            let sig = "\(c.app)|\(c.window)|\(where_)"
            if sig != self.lastSig {
                self.lastSig = sig
                self.islandWin.island.appendActivity("👁 \(c.app) › \(c.window.isEmpty ? "—" : c.window) › \(where_)")
                self.islandWin.island.setStatus(c.app)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        activityTimer = t
    }

    func handleTyping(_ e: NSEvent) {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        if app == "ClickyMine" { return }                       // don't log typing into our own chat
        if typeApp != app { flushTyping(); typeApp = app }

        if e.keyCode == 36 || e.keyCode == 76 {                  // Return / Enter
            flushTyping(); return
        } else if e.keyCode == 51 {                              // Delete
            if !typeBuffer.isEmpty { typeBuffer.removeLast() }
        } else if let ch = e.characters, !ch.isEmpty,
                  ch.rangeOfCharacter(from: .controlCharacters) == nil {
            typeBuffer += ch
        }
        if typeBuffer.count >= 60 { flushTyping() }

        typeFlushTimer?.invalidate()
        typeFlushTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flushTyping() }
        }
    }

    func flushTyping() {
        let text = typeBuffer.trimmingCharacters(in: .whitespaces)
        typeBuffer = ""
        guard !text.isEmpty else { return }
        let line = "⌨️ TYPE  \(typeApp) › “\(text)”"
        log(line)
        islandWin.island.appendActivity(line)
        SkillRecorder.shared.capture(line)                  // tee into the demonstration if teaching
    }

    var targetPID: pid_t = 0          // the app that was frontmost when a command was invoked
    var lastFrontmostPID: pid_t = 0   // most recent non-ClickyMine app (for chat-initiated tasks)
    var runTask: Task<Void, Never>?   // the in-flight agent run, so Stop can cancel it

    /// Cancel the running agent task (Stop button / ⌃⌥S). The agent loop checks Task.isCancelled.
    func stopRun() { runTask?.cancel() }
    @objc func stopRunMenu() { stopRun() }

    @objc func ask() {
        // capture the app the user actually wants to control, BEFORE we steal focus
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        ChatStore.shared.startNew()                       // ⌃⌥Space begins a fresh session
        islandWin.island.onCommand = { [weak self] q in self?.run(question: q) }
        islandWin.island.enterCommand()
    }

    var inlinePID: pid_t = 0          // app focused when the inline bar was opened
    var inlineContext = ""            // focused field's text at that moment (for "complete this line")

    /// Open the inline bar right at the mouse cursor, capturing context BEFORE we steal focus.
    @objc func askInline() {
        inlinePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        inlineContext = Inspector.focusedTyping()?.text ?? ""
        inlineBar.show(near: NSEvent.mouseLocation)
    }

    /// While the agent runs, make ALL our panels click-through so a synthetic click that happens to
    /// overlap our UI passes straight to the app underneath (instead of hitting/closing our panel).
    /// The overlay is already always click-through.
    func setOursClickThrough(_ on: Bool) {
        islandWin.ignoresMouseEvents = on
        sidebar.ignoresMouseEvents = on
        inlineBar.ignoresMouseEvents = on
    }

    /// Run the unified agent from the inline bar: act in-place at the cursor, using the focused
    /// field's current text as context so "complete this line" continues where the user left off.
    func runInline(_ instruction: String) {
        inlineBar.setBusy(true)
        let ctx = inlineContext.isEmpty ? "" :
            "\nThe text field the user is in currently contains: \"\(inlineContext)\". " +
            "If they ask to complete or continue it, TYPE only the new text that should follow — " +
            "do not retype what's already there."
        let command =
            "The user invoked you inline, right at their cursor, while working in another app. " +
            "Their text cursor is ALREADY placed in the field they want — do NOT click anything " +
            "first, clicking would move focus away. Just use the `type` tool to write at the " +
            "current cursor (and only press_return if they explicitly ask to send/submit). " +
            "Do exactly this, in place: \(instruction).\(ctx)"
        // let synthetic input pass through to the target app (no panel can intercept a click)
        setOursClickThrough(true)
        if inlinePID != 0 { NSRunningApplication(processIdentifier: inlinePID)?.activate(options: []) }
        Task { @MainActor in
            await Agent.run(
                command: command,
                initialPID: inlinePID,
                model: Claude.inlineModel,                   // inline bar uses its own (fast) model
                step: { [weak self] _, s in self?.islandWin.island.appendStep(s) },
                onFinish: { [weak self] s in self?.islandWin.island.appendStep("✓ " + s) },
                moveCursor: { [weak self] pt in (self?.overlay.contentView as? CursorView)?.point(toTopLeft: pt) }
            )
            self.inlineBar.dismiss()
            self.setOursClickThrough(false)
        }
    }

    func run(question: String) {
        log("agent command: \(question)")
        let prior = ChatStore.shared.current.turns
        ChatStore.shared.addTurn(role: "You", text: question)
        // keep the panel OPEN to stream steps, but let it pass clicks/keys through to the target app:
        // - ignoresMouseEvents so the agent's synthetic clicks land on the app underneath
        // - resign key + activate the target app so typed keystrokes go there, not our input box
        setOursClickThrough(true)
        islandWin.resignKey()
        if targetPID != 0 { NSRunningApplication(processIdentifier: targetPID)?.activate(options: []) }
        runTask = Task { @MainActor in
            await Agent.run(
                command: question,
                initialPID: targetPID,
                priorTurns: prior,
                step: { [weak self] _, s in self?.islandWin.island.appendStep(s) },
                onFinish: { [weak self] s in
                    ChatStore.shared.addTurn(role: "Clicky", text: s)
                    self?.islandWin.island.setCommandResult(s)
                },   // no TTS
                moveCursor: { [weak self] pt in (self?.overlay.contentView as? CursorView)?.point(toTopLeft: pt) }
            )
            self.islandWin.island.commandDone()
            self.setOursClickThrough(false)
        }
    }

    /// Run the unified agent from a chat surface (island Chat tab or the sidebar), streaming results
    /// to that surface's `step` / `reply` callbacks. Works for both conversation and Mac control.
    /// Records the turn into the shared session so follow-ups keep context.
    func runAgent(_ message: String, images: [String] = [], step: @escaping (Agent.StepKind, String) -> Void, reply: @escaping (String) -> Void) {
        let pid = lastFrontmostPID
        let prior = ChatStore.shared.current.turns
        ChatStore.shared.addTurn(role: "You", text: message)
        let command = message     // the agent itself decides whether a learned skill applies (via use_skill)
        setOursClickThrough(true)
        // hand focus to the target app so synthetic keystrokes/clicks land there, not in our chat box
        islandWin.resignKey(); sidebar.resignKey()
        if pid != 0 { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
        runTask = Task { @MainActor in
            await Agent.run(
                command: command,
                initialPID: pid,
                priorTurns: prior,
                attachedImages: images,
                step: step,
                onFinish: { s in reply(s) },   // ChatPane.agentReply persists the turn (with steps)
                moveCursor: { [weak self] pt in (self?.overlay.contentView as? CursorView)?.point(toTopLeft: pt) }
            )
            self.setOursClickThrough(false)
        }
    }

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.52
        speech.speak(u)
    }
}

log("===== main() reached, launching =====")   // append (don't wipe prior run's log)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar app, no dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
