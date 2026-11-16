import AppKit

/// Native ReAct agent (same loop shape as the orpex Vercel-AI-SDK agent, but in-process):
///   REASON → ACT (one tool) → OBSERVE (fresh screen + elements) → repeat → finish.
/// Tools control the real Mac: open apps, click elements (incl. Dock), type, press Return.
@MainActor
enum Agent {
    static let maxSteps = 100

    /// A streamed step: the model's own `reasoning` prose, or a `tool` call (its real name + arg).
    enum StepKind { case reasoning, tool }

    struct Action: Decodable {
        let thought: String?
        let tool: String                 // open_app | click | click_at | type | press_return | hotkey | get_screen | finish
        let app: String?
        let index: Int?
        let x: Double?
        let y: Double?
        let text: String?
        let keys: String?
        let say: String?
        let at: String?                  // click_text: "right"|"left"|"center" — for trailing icons (filter funnels, dropdowns)
        let target: String?              // click_at/right_click/scroll/drag: a DESCRIPTION to locate via the grounding VLM
        let to: String?                  // drag: DESCRIPTION of the drag DESTINATION
        let toX: Double?                 // drag: destination pixel x (fallback to `to`)
        let toY: Double?                 // drag: destination pixel y
        let seconds: Double?             // wait: how long to pause
        let amount: Int?                 // scroll: how many notches (default 6)
    }

    /// Ground a description to a real SCREEN POINT: grab a fresh screenshot (hides our own panels),
    /// ask the grounding VLM for its pixel, map it to the display. Reused by click_at/scroll/right_click/drag.
    static func groundedScreenPoint(_ target: String) async -> CGPoint? {
        guard let shot = ScreenCapture.grab(),
              let (gx, gy) = await locateTarget(target, imageBase64: shot.base64) else { return nil }
        let cx = max(0, min(CGFloat(gx), CGFloat(shot.imageW)))
        let cy = max(0, min(CGFloat(gy), CGFloat(shot.imageH)))
        let pt = CGPoint(x: cx * (shot.bounds.width / CGFloat(shot.imageW)) + shot.bounds.origin.x,
                         y: cy * (shot.bounds.height / CGFloat(shot.imageH)) + shot.bounds.origin.y)
        log("GROUND \"\(target)\" → img=(\(Int(gx)),\(Int(gy))) of \(shot.imageW)x\(shot.imageH) → screen=(\(Int(pt.x)),\(Int(pt.y)))pt")
        return pt
    }

    /// Ask the grounding service (cua GTA1 algorithm) for the exact pixel of a described element.
    /// Returns (x,y) in the SAME pixel space as the screenshot we sent. nil if it can't locate it.
    static func locateTarget(_ instruction: String, imageBase64: String) async -> (Double, Double)? {
        guard let url = URL(string: "http://127.0.0.1:8799/locate") else { return nil }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        guard let data = try? JSONSerialization.data(withJSONObject: ["instruction": instruction, "image_b64": imageBase64]) else { return nil }
        req.httpBody = data
        do {
            let (respData, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
                  (json["ok"] as? Bool) == true,
                  let x = json["x"] as? NSNumber, let y = json["y"] as? NSNumber else {
                log("LOCATE failed: \(String(data: respData, encoding: .utf8) ?? "")"); return nil
            }
            return (x.doubleValue, y.doubleValue)
        } catch { log("LOCATE error: \(error.localizedDescription)"); return nil }
    }

    // ── STRUCTURED TOOL SCHEMAS (OpenAI/OpenRouter function-calling) ──────────────────────────────
    // The model is given these as real `tools` on the request and replies with a structured tool_call —
    // no more parsing free-text JSON out of the prose. The system prompt only carries BEHAVIORAL guidance.
    private static func strProp(_ d: String, _ e: [String]? = nil) -> [String: Any] {
        var p: [String: Any] = ["type": "string", "description": d]; if let e { p["enum"] = e }; return p
    }
    private static func intProp(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
    private static func numProp(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
    private static func fnTool(_ name: String, _ desc: String,
                               _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        var params: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { params["required"] = required }
        return ["type": "function", "function": ["name": name, "description": desc, "parameters": params]]
    }

    static let toolSchemas: [[String: Any]] = [
        fnTool("open_app", "Launch or focus a macOS application by name (Safari, Calendar, Comet, …).",
               ["app": strProp("The application name.")], required: ["app"]),
        fnTool("click_text", "PREFERRED for any LABELED native control in the elements list (Dock icon, menu, toolbar, sidebar, native button/tab/checkbox, labeled field). Clicks its exact detected location.",
               ["text": strProp("The visible label/text of the element."),
                "at": strProp("Hit a trailing/leading icon at that edge (e.g. a column filter funnel).", ["left", "right", "center"])],
               required: ["text"]),
        fnTool("click", "Click element #index from the numbered CLICKABLE ELEMENTS list.",
               ["index": intProp("The element index.")], required: ["index"]),
        fnTool("double_click", "Double-click an element to open it / enter edit or rename mode.",
               ["index": intProp("Element index."), "text": strProp("Or the element's label.")]),
        fnTool("click_at", "Click by DESCRIPTION — preferred for web-page content, tiny/unlabeled icons, or a sub-part such as the HOUR digits of a time field. A grounding model finds the exact pixel from your description. Use x,y only as a fallback.",
               ["target": strProp("Specific description of exactly what to click (which one and where)."),
                "x": numProp("Fallback pixel x."), "y": numProp("Fallback pixel y.")]),
        fnTool("right_click", "Open a context menu on an element (by description, index, or label).",
               ["target": strProp("Description of what to right-click."), "index": intProp("Or element index."), "text": strProp("Or label.")]),
        fnTool("drag", "Press-drag from one point to another (sliders, range handles, reordering). Endpoints are descriptions (target→to) or pixels (x,y→toX,toY).",
               ["target": strProp("Start description."), "to": strProp("End description."),
                "x": numProp("Start x."), "y": numProp("Start y."), "toX": numProp("End x."), "toY": numProp("End y.")]),
        fnTool("scroll", "Scroll up or down. Add 'target' to scroll INSIDE a specific dropdown/dialog/list to reveal off-screen items (a hidden menu option, or the OK/Apply button) instead of the whole page.",
               ["text": strProp("Direction.", ["up", "down"]),
                "target": strProp("Description of the area to scroll over."), "amount": intProp("Notches (default 6).")],
               required: ["text"]),
        fnTool("type", "Type literal text into the currently focused field.",
               ["text": strProp("The text to type.")], required: ["text"]),
        fnTool("press_return", "Press the Return/Enter key."),
        fnTool("hotkey", "Press a keyboard shortcut, e.g. 'cmd+l', 'cmd+t', 'cmd+a', 'left', 'right'.",
               ["keys": strProp("The key combination.")], required: ["keys"]),
        fnTool("wait", "Pause for the screen to load/settle before acting again.",
               ["seconds": numProp("Seconds to wait (0.2–10).")]),
        fnTool("get_screen", "Re-read the current screen (fresh screenshot + elements)."),
        fnTool("get_skill", "List skills the user has taught you (call before a task to see if one fits)."),
        fnTool("use_skill", "Load a learned skill's step-by-step plan and follow it.",
               ["text": strProp("The skill name.")], required: ["text"]),
        fnTool("finish", "Finish — ONLY when the user's goal is fully done AND visible on the current screenshot. Put the short result/answer in 'say'.",
               ["say": strProp("Short result or answer to the user.")], required: ["say"]),
    ]

    /// Build an Action from a structured tool_call (name + raw JSON arguments) by reusing Action's Codable.
    static func actionFrom(name: String, argsJSON: String) throws -> Action {
        var dict = (try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8))) as? [String: Any] ?? [:]
        dict["tool"] = name
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(Action.self, from: data)
    }

    private static let system = """
    You are Clicky, a helpful assistant that can both CHAT with the user and OPERATE their Mac to get
    things done — the way a person would: look at the screen, take one action, look again, adapt.

    DECIDE FIRST: if the user is just chatting or asking something you can answer directly (a question,
    advice, an explanation), DON'T touch the Mac — immediately call "finish" with your answer in "say".
    Only use the action tools when the request actually requires operating the Mac (open/click/type/search).

    HOW YOU WORK (ReAct loop): reason briefly about the SINGLE next step, call EXACTLY ONE tool, observe
    the fresh result, repeat — until the request is fully done, then finish with a short result/answer.

    CHECK SKILLS FIRST: before starting any real task — especially a multi-step, reasoning, or long-running
    one — call get_skill to see if the user already TAUGHT you a skill for it. If one matches, use_skill it
    and follow its steps. If none fit (or it's a trivial/one-off request), just proceed normally.

    PLAN THE TASK FIRST: before you act, break the user's request into the FULL ordered list of the concrete
    steps needed to ACTUALLY finish it — every step, end to end, not just the first one. Pull the real values
    out of the request (apps, sites, names, dates, queries) and list each action that must happen — including
    waiting for things to load and a final step that proves the goal is met. Write this numbered plan in your
    FIRST "thought", then work through EVERY step in order, tracking which step you're on. Do not skip steps,
    do not stop in the middle, and do not finish until the LAST step is done and verified on screen.

    WHAT YOU SEE EACH TURN
    - A BLUE TRIANGLE on the screenshot marks where your cursor currently is (right after a click it sits at
      that point). Use it as feedback: if it didn't land on what you meant, click again with a clearer
      click_text label or a more specific click_at "target" description.
    - A screenshot of the current screen — these are your eyes; trust what you see. You ALWAYS get this
      fresh screenshot every turn, INCLUDING right now. So if the user asks "what do you see" / "describe
      this" / anything answerable from the screen, just look and answer with "finish" — do NOT call
      get_screen first (you already see it). Any image the user attached is also already shown to you.
    - A numbered list of CLICKABLE ELEMENTS. This is your PRIMARY way to click — every item is a REAL thing on
      screen with its EXACT detected location, so use the list instead of guessing pixels. It combines:
      (1) macOS Accessibility — native controls, browser chrome, web links/buttons; and
      (2) OCR text boxes (role "Text") — EVERY piece of text currently visible, INCLUDING canvas content that
      Accessibility can't see (e.g. Google Sheets cell values and column headers).
      To click any item, name it with "click_text" or click its "index" — we click its EXACT detected spot, no
      guessing. For a SUB-PART that is not its own list item (e.g. the hour digit of a time), use click_at with
      a "target" description and a grounding model finds the exact pixel. If the thing you want IS in the list,
      click it by name/index — do NOT invent a pixel for it.

    TOOLS — these are provided to you as STRUCTURED function tools. Make exactly ONE tool call per turn using
    the real tool-call mechanism. Do NOT write tool JSON in your text and do NOT invent a "thought" field.
    ALWAYS write ONE short sentence of plain reasoning first (what you're about to do and why), THEN make the
    tool call in the same turn. What each tool does:
    - open_app — launch/focus an app by name.
    - click_text — click a LABELED element from the list by its visible text. Your DEFAULT for native/app UI.
      (set at="left"/"right" to hit a trailing/leading icon such as a column filter funnel.)
    - click — click element #index from the CLICKABLE ELEMENTS list.
    - double_click — open an event/file, or enter edit/rename mode (by index or text).
    - click_at — click by a natural-language "target" description; a grounding model returns the EXACT pixel.
      Use for web-page content, tiny/unlabeled icons, or a SUB-PART like the HOUR digits of a time field.
      Be precise about WHICH part. (x,y is a fallback only.)
    - right_click — open a context menu (by target description, index, or text).
    - drag — press-drag from one point to another (target→to descriptions, or x,y→toX,toY pixels).
    - scroll — scroll up/down; set target="<the dropdown/dialog/list>" to scroll INSIDE it and reveal an
      off-screen item or the OK/Apply button, instead of the whole page; amount sets distance.
    - type — type into the currently focused field.
    - press_return — press Return/Enter. (Note: in a dialog/filter this often does NOT apply the change —
      look for an OK/Apply/Done/Save button and click it.)
    - hotkey — a shortcut like cmd+l, cmd+a, left, right.
    - wait — pause for the screen to load/settle before acting again.
    - get_screen — re-read the screen.
    - get_skill / use_skill — list / load a skill the user taught you.
    - finish — ONLY when the goal is fully done AND visible on the current screenshot (put the result in "say").
      Opening an app/website, or being "ready to" do the thing, is NOT done — keep going.

    HOW TO CLICK — CHOOSE THE RIGHT METHOD (this decision matters a lot; get it right every time):

    There are TWO click families. Decide by WHAT you're clicking and WHERE it lives.

    ┌─ A) NATIVE / LABELED macOS UI that is IN THE CLICKABLE ELEMENTS LIST → use click_text (by label) or
    │     click (by index). This uses the element's EXACT accessibility location — most reliable, no vision,
    │     no guessing. This is your DEFAULT for the operating-system chrome and native app windows.
    │  Use it for: the DOCK, the MENU BAR, app TOOLBARS, SIDEBARS, native BUTTONS / MENUS / TABS / CHECKBOXES,
    │     list ROWS, and any form FIELD that has a visible label — i.e. anything that appears as a numbered
    │     element in the list.
    │  Scenarios:
    │    • Open an app from the Dock → call click_text with text "Calendar".
    │    • A menu/toolbar/sidebar/tab by name → click_text "File" (or "Inbox", "Today").
    │    • A native button → click_text "Add Event".
    │    • Open an event/file (enter edit mode) → double_click with text "Dentist Appointment".
    │  RULE: if it's a named control in the list, click it FROM the list. NEVER invent a pixel for it.
    │
    └─ B) INSIDE A BROWSER / WEB PAGE, or a SMALL / PRECISE / UNLABELED point, or a SUB-PART of a control →
          use click_at with a "target" DESCRIPTION. A grounding vision model looks at the screenshot and
          returns the EXACT pixel of what you described. You DESCRIBE it in words — you never guess numbers.
       Use it for:
         • ANY content INSIDE a browser web area (Chrome / Safari / Comet / Arc / Brave): links, buttons,
           search results, fields, icons, table cells RENDERED in the page. Browser page pixels are NOT
           reliable native elements, so DESCRIBE what to click instead of trusting the list.
         • A precise SUB-PART of a control: the HOUR digits of a "1:00 PM" time field; one cell in a canvas
           spreadsheet; a tiny gear / × / ＋ / chevron icon with no label; an exact point on an image/map/chart.
         • Anything you can clearly SEE but that is NOT a clean item in the element list.
       Write a SPECIFIC description (call click_at with "target" =) — say WHICH one and WHERE (color, text, row):
         • Browser link →   "the first search result link titled 'OpenAI'".
         • Browser button → "the blue 'Sign in' button in the top-right of the page".
         • Small icon →     "the X close button in the top-right corner of the dialog".
         • Sub-part →       "the hour digits (the '1') of the start time 1:00 PM".

    QUICK DECISION every time you click:
      1. Labeled native control in the list (Dock, menu, toolbar, native button/field)?  → click_text / click.
      2. Web-page content, a tiny/unlabeled icon, or a sub-part of a field?               → click_at with "target".
      3. Both failed?  → click_at with raw x,y as a last resort.

    SEGMENTED TIME / DATE FIELDS (macOS): a time like "9:00 PM" LOOKS like one box but is THREE segments —
    HOUR : MINUTES AM/PM. Clicking its CENTER always selects the MINUTES (the #1 mistake). To set the HOUR,
    use method B: click_at target "the hour digits of the start time 9:00 PM", then type the hour.
    Move between segments with hotkey "left"/"right"; type "P"/"A" on the AM/PM segment. NEVER click_text a
    time/date field — it hits the minutes.

    TYPING: focus the field first (click_text for a labeled field, or click_at target for a web/precise field),
    then type, then press_return if it submits. In a FORM or POPOVER (e.g. a new-event editor), once one field
    is focused, move between fields with TAB (hotkey "tab") instead of clicking blank canvas — Tab lands you ON
    the next real field (title → date → time). If "type" reports NO field is focused, you clicked a blank area:
    click the actual field (or Tab to it) before typing again. Never keep typing into nothing.
    Use keyboard shortcuts when natural (cmd+l address bar, cmd+t new tab, arrow keys for segmented fields).

    RULES
    - One tool per turn. The screen changes after every action — read the new screenshot before deciding the next step.
    - Extract the user's ACTUAL intent: pull the real values out of the request (a query, a name, a URL);
      never type the whole instruction into a field.
    - VERIFY by looking: confirm each action did what you expected before moving on.
    - If something didn't work, reason about WHY and adapt — try a different element, a click_at, or a
      shortcut. Never repeat the identical failing action. If the SAME action made NO visible change twice,
      STOP doing it and pick a different element or method.
    - CONFIRM/APPLY before moving on. After choosing an option or entering a value in a dialog/filter/menu,
      pressing Return usually does NOT apply it — look for the OK / Apply / Done / Save button and click it
      (if it's off-screen, use scroll with target="the dialog" to reveal it). Then take get_screen and CHECK
      the change actually took effect before the next step or finishing.
    - WAIT for pages/apps to load. After navigating or pressing Return, the screen often still shows the OLD
      page for a moment. Do NOT act on or finish from a stale screen — if what you expect isn't visible yet,
      call get_screen and look again until it has loaded.
    - FINISH ONLY WHEN TRULY DONE. "Done" means the user's real end goal is achieved AND visible on the
      CURRENT screenshot. Opening an app/website, focusing a field, or being "ready to" act is NOT done — keep
      going. NEVER finish with words like "ready to…", "should be loading", or "you can now…". NEVER claim you
      did something (typed a value, ran a search, produced a result) that you cannot SEE on the screenshot —
      that is a failure. Before calling finish, re-check your plan: if ANY step isn't done and confirmed on
      screen, do that step instead of finishing. Be persistent; only finish when the LAST step is verified.
    """

    /// TEST-ONLY bridge: shell out to the OpenRouter computer-use harness (cu-openrouter/or_run.py),
    /// which drives the REAL Anthropic quickstart ComputerTool, and stream its stdout into the chat.
    /// Enabled by setting CU_OPENROUTER=1. Lets us compare native pixel-grounding vs. the Swift loop.
    static func runViaComputerUse(command: String,
                                  model: String,
                                  step: @escaping (StepKind, String) -> Void,
                                  onFinish: @escaping (String) -> Void) async {
        let dir = "/Users/hritvik/cu-openrouter/src/computer-use-best-practices"
        let script = "\(dir)/or_run.py"
        guard FileManager.default.fileExists(atPath: script) else {
            onFinish("cu-openrouter harness not found at \(script)"); return
        }
        // CU_MODEL lets the harness run a grounding-strong model (e.g. claude-sonnet-4.6)
        // independent of the Swift agent's own LLM_MODEL.
        let cuModel = ProcessInfo.processInfo.environment["CU_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? model
        step(.reasoning, "▶︎ Routing through OpenRouter computer-use harness (model: \(cuModel))")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "-u", script, command, cuModel]
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { onFinish("failed to launch harness: \(error.localizedDescription)"); return }

        var last = ""
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                // tool actions are the indented "→ computer(...)" / result lines; the rest is the model talking
                let kind: StepKind = (line.hasPrefix(" ") || trimmed.hasPrefix("→")) ? .tool : .reasoning
                step(kind, trimmed)
                last = trimmed
            }
        } catch { /* stream ended */ }
        p.waitUntilExit()
        onFinish(last.isEmpty ? "harness finished." : last)
    }

    /// Run the agent. `status` streams each step to the UI; `moveCursor` animates the triangle to a point.
    static func run(command: String,
                    initialPID: pid_t,
                    model: String = Claude.model,             // which LLM to drive this run
                    priorTurns: [ChatTurn] = [],              // earlier conversation, for follow-ups
                    attachedImages: [String] = [],            // user-attached images (base64 JPEG)
                    step: @escaping (StepKind, String) -> Void,   // model reasoning + tool calls, streamed
                    onFinish: @escaping (String) -> Void,      // final answer/result
                    moveCursor: @escaping (CGPoint) -> Void) async {
        // TEST BRIDGE: when CU_OPENROUTER is set, route the whole task through the
        // OpenRouter computer-use harness (the REAL Anthropic quickstart ComputerTool,
        // native pixel-grounding) instead of the Swift OCR loop — so we can A/B it
        // straight from Tine's chat. Output streams into the chat like normal steps.
        // Only route to the harness when explicitly enabled. "0"/"false"/"no"/"" all mean OFF
        // (a plain non-empty check treated "0" as ON, which silently kept the bridge active).
        let cuRaw = (ProcessInfo.processInfo.environment["CU_OPENROUTER"] ?? "").lowercased()
        if ["1", "true", "yes", "on"].contains(cuRaw) {
            await runViaComputerUse(command: command, model: model, step: step, onFinish: onFinish)
            return
        }
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        // seed earlier conversation (text only — no stale screenshots) so the agent has context
        for t in priorTurns {
            messages.append(["role": t.role == "You" ? "user" : "assistant", "content": t.text])
        }
        var elements: [Inspector.Elem] = []
        // geometry of the LAST screenshot we sent, so click_at can map model pixels → real screen points.
        var shotImageSize = CGSize(width: 1, height: 1)            // pixel size of the image the model saw
        var shotBounds = CGDisplayBounds(CGMainDisplayID())        // captured display, points, top-left global
        var lastClickPt: CGPoint? = nil                           // where we last clicked — scroll happens HERE
                                                                  // (over the open popup/list), not screen center

        // build an observation message for the CURRENT target app. ALWAYS include the screenshot:
        // web page content never appears in the AX element list, so vision is the only way the agent
        // can see what's actually on a web page (Gmail, search results, etc.).
        func observation(prefix: String, withImage: Bool = true) -> [String: Any] {
            let pid = currentTargetPID(initialPID)
            elements = Inspector.clickableElements(pid: pid)
            if let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) {
                elements += Inspector.clickableElements(pid: dock.processIdentifier)
            }
            // DETERMINISTIC canvas locator: OCR every on-screen text string → exact screen coordinate.
            // This surfaces Google Sheets cells/headers (and any canvas text) that Accessibility can't see.
            elements += OCR.locate()
            // Grab the screenshot FIRST so we know the exact pixel space, then annotate every element with
            // its @x,y in THAT space — the SAME space click_at uses. This hands the model exact coordinates
            // to pass to click_at (and to SHIFT for a sub-part), instead of making it guess pixels or fall
            // back to click_text (which only ever hits an element's center).
            let shot = (withImage && Claude.supportsVision(model)) ? ScreenCapture.grab() : nil
            if let s = shot { shotImageSize = CGSize(width: s.imageW, height: s.imageH); shotBounds = s.bounds }
            let sx = shotImageSize.width / max(1, shotBounds.width)
            let sy = shotImageSize.height / max(1, shotBounds.height)
            let list = elements.enumerated()
                .map { (i, e) -> String in
                    let px = Int((e.center.x - shotBounds.origin.x) * sx)
                    let py = Int((e.center.y - shotBounds.origin.y) * sy)
                    // Also publish the box's LEFT and RIGHT x in the same pixel space. A single OCR/AX box can
                    // cover a MULTI-SEGMENT value (e.g. a "1:00 PM" time field is really HH:MM AM/PM); its
                    // center always lands on the middle segment (MM). Giving L→R lets the model aim click_at at
                    // ANY sub-part — left third for HH, right third for AM/PM — with no per-app hardcoding.
                    let lx = Int((e.frame.minX - shotBounds.origin.x) * sx)
                    let rx = Int((e.frame.maxX - shotBounds.origin.x) * sx)
                    let span = (rx - lx) >= 24 ? "  x:\(lx)→\(rx)" : ""
                    return "[\(i)] \(e.role.replacingOccurrences(of: "AX", with: "")) \"\(e.label)\" @\(px),\(py)\(span)"
                }
                .joined(separator: "\n")
            log("OBS [\(elements.count) els]: \(elements.prefix(20).map { $0.label }.joined(separator: " | "))")
            let baseText = "\(prefix)\n\nCLICKABLE ELEMENTS (each ends @x,y = its CENTER pixel in the screenshot. "
                + "Some also show x:L→R = the box's left and right edge in that same space. If a value has SEVERAL "
                + "parts inside ONE box — a time like \"1:00 PM\" (HH:MM AM/PM), a date \"06/18/2026\", a range — the "
                + "CENTER sits on the MIDDLE part, so to edit a specific part click_at the matching spot in x:L→R "
                + "(e.g. left edge for the hour), NOT the center):\n\(list.isEmpty ? "(none)" : list)"
            if let s = shot {
                // tell the model the EXACT coordinate space of the image it's looking at
                let dims = "\n\nSCREENSHOT: \(s.imageW)x\(s.imageH) pixels. For click_at, give x,y as integer "
                    + "pixels in this space (origin top-left)."
                return ["role": "user", "content": [
                    ["type": "text", "text": baseText + dims],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(s.base64)"]]]]
            }
            return ["role": "user", "content": baseText]
        }

        // Nudge (not the catalog): tell the agent how MANY skills exist so it knows to call get_skill.
        // The names/descriptions are only revealed when it actually calls get_skill — it decides relevance.
        let skillCount = SkillStore.all().count
        let skillNote = skillCount == 0 ? "" :
            "\n\n[You have \(skillCount) learned skill(s) available. Before starting this task, call get_skill to check whether one of them already covers it.]"
        var firstObs = observation(prefix: "COMMAND: \(command)\(skillNote)", withImage: true)
        // fold any user-attached image into the first observation so it rides with the latest
        // screenshot (stripOldImages keeps only the latest image-bearing message).
        if !attachedImages.isEmpty, var content = firstObs["content"] as? [[String: Any]] {
            content.append(["type": "text", "text": "The user also attached \(attachedImages.count) image(s) for context:"])
            for img in attachedImages {
                content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(img)"]])
            }
            firstObs["content"] = content
        }
        messages.append(firstObs)

        var consecutiveFails = 0
        for stepIdx in 0..<maxSteps {
            if Task.isCancelled { onFinish("⏹ Stopped."); return }   // Stop button pressed
            let action: Action
            do {
                let bodyData = Claude.completeBody(messages: stripOldImages(messages), model: model, tools: toolSchemas)
                let (toolName, toolArgs, content, reasoning) = try await Claude.completeTool(bodyData: bodyData)
                log("AGENT step \(stepIdx) tool=\(toolName ?? "—") args=\(toolArgs ?? "{}")")
                if !content.isEmpty { log("AGENT step \(stepIdx) content: \(content)") }
                if !reasoning.isEmpty { log("AGENT step \(stepIdx) reasoning: \(reasoning)") }
                if let toolName {
                    action = try actionFrom(name: toolName, argsJSON: toolArgs ?? "{}")
                } else if let parsed = try? decode(content) {
                    action = parsed                                  // model replied with text JSON — tolerate it
                } else {
                    // no tool call and no JSON → treat the prose as a final answer
                    action = Action(thought: nil, tool: "finish", app: nil, index: nil, x: nil, y: nil,
                                    text: nil, keys: nil, say: content.isEmpty ? "Done." : content, at: nil,
                                    target: nil, to: nil, toX: nil, toY: nil, seconds: nil, amount: nil)
                }
                consecutiveFails = 0
                // Stream the model's reasoning to the thinking UI. Prefer its separate `reasoning` field; for a
                // STRUCTURED tool call also use the assistant `content` (where models put their one-line reason).
                // In the text-JSON fallback the content IS the tool call, so don't surface that as reasoning.
                var think = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                if think.isEmpty, toolName != nil { think = content.trimmingCharacters(in: .whitespacesAndNewlines) }
                if think.isEmpty { think = (action.thought ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                if !think.isEmpty { step(.reasoning, think) }
            } catch {
                // a transient error (network/parse) shouldn't kill the whole run — note it and retry
                consecutiveFails += 1
                log("AGENT step \(stepIdx) error: \(error.localizedDescription)")
                if consecutiveFails >= 3 { onFinish("⚠️ \(error.localizedDescription)"); return }
                step(.tool, "Retrying")
                messages.append(["role": "user",
                    "content": "OBSERVATION: that didn't work. Call exactly one tool to continue."])
                continue
            }
            messages.append(["role": "assistant", "content": describe(action)])

            switch action.tool {
            case "open_app":
                let name = action.app ?? ""
                step(.tool, name.isEmpty ? "Open app" : "Open app · \(name)")
                openApp(name)
                try? await Task.sleep(nanoseconds: 1_500_000_000)   // let the app launch + come forward
                messages.append(observation(prefix: "OBSERVATION: opened \(name)."))

            case "click_text":
                // Click by NAME, not index — the model names a visible label and we resolve it to the
                // exact located coordinate (AX or OCR). Robust where index-counting in a 400-item list fails.
                let q = (action.text ?? "").lowercased().trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else {
                    messages.append(["role": "user", "content": "OBSERVATION: click_text needs text."]); continue
                }
                let scored: [(Int, Int)] = elements.enumerated().compactMap { (i, e) in
                    let l = e.label.lowercased()
                    if l == q { return (i, 4) }
                    if l.hasPrefix(q) { return (i, 3) }
                    if q.hasPrefix(l), l.count >= 3 { return (i, 2) }   // model gave fuller text than the truncated label
                    if l.contains(q) { return (i, 1) }
                    return nil
                }.sorted { $0.1 > $1.1 }
                guard let best = scored.first else {
                    messages.append(observation(prefix: "OBSERVATION: nothing on screen matches \"\(q)\". Pick a label that appears in the list."))
                    continue
                }
                let e = elements[best.0]
                // Target a trailing icon (column filter funnel, dropdown arrow) at the right/left edge of
                // the element's box when asked — that's where Sheets/Excel put per-column filter controls.
                var cpt = e.center
                switch (action.at ?? "").lowercased() {
                case "right": if e.frame.width > 6 { cpt = CGPoint(x: e.frame.maxX - min(12, e.frame.width / 4), y: e.frame.midY) }
                case "left":  if e.frame.width > 6 { cpt = CGPoint(x: e.frame.minX + min(12, e.frame.width / 4), y: e.frame.midY) }
                default: break
                }
                step(.tool, "Click · \(e.label)")
                moveCursor(cpt)
                try? await Task.sleep(nanoseconds: 450_000_000)
                Clicker.click(atTopLeft: cpt); lastClickPt = cpt
                log("CLICK_TEXT \"\(q)\" at=\(action.at ?? "center") → [\(best.0)] \"\(e.label)\" (\(e.role)) box=\(Int(e.frame.minX)),\(Int(e.frame.minY)),\(Int(e.frame.width))x\(Int(e.frame.height)) @\(Int(cpt.x)),\(Int(cpt.y))")
                try? await Task.sleep(nanoseconds: 700_000_000)
                messages.append(observation(prefix: "OBSERVATION: clicked \"\(e.label)\"."))

            case "double_click":
                var dp: CGPoint? = nil; var dlabel = ""
                if let i = action.index, i >= 0, i < elements.count {
                    dp = elements[i].center; dlabel = elements[i].label
                } else if let q = action.text?.lowercased().trimmingCharacters(in: .whitespaces), !q.isEmpty {
                    let hit = elements.first(where: { $0.label.lowercased() == q }) ?? elements.first(where: { $0.label.lowercased().contains(q) })
                    if let e = hit { dp = e.center; dlabel = e.label }
                }
                guard let dpt = dp else {
                    messages.append(["role": "user", "content": "OBSERVATION: double_click needs a valid index or text."]); continue
                }
                step(.tool, "Double-click · \(dlabel)")
                moveCursor(dpt)
                try? await Task.sleep(nanoseconds: 450_000_000)
                Clicker.doubleClick(atTopLeft: dpt); lastClickPt = dpt
                try? await Task.sleep(nanoseconds: 700_000_000)
                messages.append(observation(prefix: "OBSERVATION: double-clicked \"\(dlabel)\"."))

            case "click":
                guard let i = action.index, i >= 0, i < elements.count else {
                    messages.append(["role": "user", "content": "OBSERVATION: invalid index."]); continue
                }
                let target = elements[i].center
                let isDock = elements[i].role == "AXDockItem"
                step(.tool, "Click · \(elements[i].label)")
                moveCursor(target)
                try? await Task.sleep(nanoseconds: 450_000_000)
                Clicker.click(atTopLeft: target); lastClickPt = target
                // clicking a Dock icon or a link/tab usually switches context — wait longer to settle
                try? await Task.sleep(nanoseconds: isDock ? 1_500_000_000 : 700_000_000)
                messages.append(observation(prefix: "OBSERVATION: clicked \"\(elements[i].label)\"."))

            case "click_at" where action.target?.isEmpty == false:
                // GROUNDED click: the model DESCRIBES the target and the grounding VLM returns its EXACT pixel.
                let target = action.target!
                step(.tool, "Locate · \(target)")
                if let pt = await groundedScreenPoint(target) {
                    step(.tool, "Click · \(Int(pt.x)),\(Int(pt.y))")
                    moveCursor(pt)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    Clicker.click(atTopLeft: pt); lastClickPt = pt
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    messages.append(observation(prefix: "OBSERVATION: located \"\(target)\" and clicked it."))
                } else {
                    messages.append(observation(prefix: "OBSERVATION: could not locate \"\(target)\" on screen. Describe it more specifically, or use click_text for a labeled element."))
                }

            case "click_at":
                guard let xf = action.x, let yf = action.y else {
                    messages.append(["role": "user", "content": "OBSERVATION: click_at needs a 'target' description (preferred) or x and y."]); continue
                }
                // We told the model the image's exact pixel size, so x,y are pixels in that space.
                // Tolerate a model that still replied in 0–1 fractions (both <= 1) by scaling up.
                var ix = CGFloat(xf), iy = CGFloat(yf)
                if abs(ix) <= 1, abs(iy) <= 1 { ix *= shotImageSize.width; iy *= shotImageSize.height }
                // map screenshot PIXELS → display POINTS, then to global top-left (CGEvent) coords.
                // EXACT: we click PRECISELY where the model said — no snapping, no nearest-element guessing.
                // The model controls the pixel; it uses the screenshot + blue cursor + nudge to aim/refine.
                let cx = max(0, min(ix, shotImageSize.width)), cy = max(0, min(iy, shotImageSize.height))
                let pt = CGPoint(x: cx * (shotBounds.width / shotImageSize.width) + shotBounds.origin.x,
                                 y: cy * (shotBounds.height / shotImageSize.height) + shotBounds.origin.y)
                log("CLICK_AT exact raw=(\(xf),\(yf)) img=\(Int(shotImageSize.width))x\(Int(shotImageSize.height)) → screen=(\(Int(pt.x)),\(Int(pt.y)))pt")
                step(.tool, "Click · \(Int(cx)),\(Int(cy))")
                moveCursor(pt)
                try? await Task.sleep(nanoseconds: 450_000_000)
                Clicker.click(atTopLeft: pt); lastClickPt = pt
                try? await Task.sleep(nanoseconds: 700_000_000)
                messages.append(observation(prefix: "OBSERVATION: clicked at screen (\(Int(pt.x)), \(Int(pt.y)))."))

            case "type":
                let txt = action.text ?? ""
                // Don't type into nothing — that just makes macOS beep and loses the text. Require a focused
                // text input first; otherwise tell the model to click the field.
                guard Inspector.focusedAcceptsTyping() else {
                    log("TYPE blocked — no focused text field")
                    messages.append(observation(prefix: "OBSERVATION: typing did nothing — NO text field is focused. "
                        + "Click the input field FIRST (click_text its label/placeholder), then type."))
                    continue
                }
                step(.tool, "Type · \(txt)")
                Clicker.type(txt)
                try? await Task.sleep(nanoseconds: 200_000_000)
                messages.append(["role": "user", "content": "OBSERVATION: typed \"\(txt)\"."])

            case "press_return":
                step(.tool, "Press Return")
                Clicker.pressReturn()
                try? await Task.sleep(nanoseconds: 900_000_000)
                messages.append(observation(prefix: "OBSERVATION: pressed Return."))

            case "hotkey":
                let keys = action.keys ?? ""
                step(.tool, "Hotkey · \(keys)")
                Clicker.hotkey(keys)
                try? await Task.sleep(nanoseconds: 700_000_000)
                messages.append(observation(prefix: "OBSERVATION: pressed \(keys)."))

            case "scroll":
                let dir = (action.text ?? "down").lowercased()
                let notches = max(1, action.amount ?? 6)
                step(.tool, "Scroll · \(dir)")
                let scr = (NSScreen.main ?? NSScreen.screens.first!).frame
                // WHERE to scroll, in priority order:
                //  1. a grounded "target" the model named (e.g. "the filter condition dropdown") — most reliable
                //     for scrolling INSIDE a specific dropdown/dialog/list to reveal off-screen items (OK button,
                //     more options) rather than scrolling the whole page;
                //  2. the last click point, if it was in the content area (a popup/list we just opened);
                //  3. screen center as a last resort.
                var at = CGPoint(x: scr.midX, y: scr.midY)
                if let t = action.target, !t.isEmpty, let p = await groundedScreenPoint(t) {
                    at = p
                } else if let p = lastClickPt, p.y > scr.minY + 160 {
                    at = p
                }
                moveCursor(at)
                try? await Task.sleep(nanoseconds: 200_000_000)
                Clicker.scroll(at: at, lines: Int32(dir.contains("up") ? notches : -notches))
                log("SCROLL \(dir) x\(notches) at @\(Int(at.x)),\(Int(at.y))\(action.target.map { " target=\"\($0)\"" } ?? "")")
                try? await Task.sleep(nanoseconds: 600_000_000)
                messages.append(observation(prefix: "OBSERVATION: scrolled \(dir)."))

            case "right_click":
                // Open a context menu. Target by description (grounded), by index, or by label.
                var rp: CGPoint? = nil
                if let t = action.target, !t.isEmpty { rp = await groundedScreenPoint(t) }
                else if let i = action.index, i >= 0, i < elements.count { rp = elements[i].center }
                else if let q = action.text?.lowercased(), let e = elements.first(where: { $0.label.lowercased().contains(q) }) { rp = e.center }
                guard let p = rp else {
                    messages.append(observation(prefix: "OBSERVATION: right_click needs a 'target' description, an index, or text.")); continue
                }
                step(.tool, "Right-click · \(Int(p.x)),\(Int(p.y))")
                moveCursor(p)
                try? await Task.sleep(nanoseconds: 450_000_000)
                Clicker.rightClick(atTopLeft: p); lastClickPt = p
                try? await Task.sleep(nanoseconds: 700_000_000)
                messages.append(observation(prefix: "OBSERVATION: right-clicked (context menu should be open)."))

            case "drag":
                // Drag from one point to another. Endpoints: grounded "target"→"to", or x,y→toX,toY.
                var from: CGPoint? = nil, dest: CGPoint? = nil
                if let t = action.target, !t.isEmpty { from = await groundedScreenPoint(t) }
                else if let x = action.x, let y = action.y {
                    let cx = max(0, min(CGFloat(x), shotImageSize.width)), cy = max(0, min(CGFloat(y), shotImageSize.height))
                    from = CGPoint(x: cx * (shotBounds.width / shotImageSize.width) + shotBounds.origin.x,
                                   y: cy * (shotBounds.height / shotImageSize.height) + shotBounds.origin.y)
                }
                if let t = action.to, !t.isEmpty { dest = await groundedScreenPoint(t) }
                else if let x = action.toX, let y = action.toY {
                    let cx = max(0, min(CGFloat(x), shotImageSize.width)), cy = max(0, min(CGFloat(y), shotImageSize.height))
                    dest = CGPoint(x: cx * (shotBounds.width / shotImageSize.width) + shotBounds.origin.x,
                                   y: cy * (shotBounds.height / shotImageSize.height) + shotBounds.origin.y)
                }
                guard let a = from, let b = dest else {
                    messages.append(observation(prefix: "OBSERVATION: drag needs a start ('target' or x,y) AND an end ('to' or toX,toY).")); continue
                }
                step(.tool, "Drag · \(Int(a.x)),\(Int(a.y)) → \(Int(b.x)),\(Int(b.y))")
                moveCursor(a)
                try? await Task.sleep(nanoseconds: 300_000_000)
                Clicker.drag(from: a, to: b); lastClickPt = b
                try? await Task.sleep(nanoseconds: 600_000_000)
                messages.append(observation(prefix: "OBSERVATION: dragged from (\(Int(a.x)),\(Int(a.y))) to (\(Int(b.x)),\(Int(b.y)))."))

            case "wait":
                let secs = max(0.2, min(action.seconds ?? 1.5, 10))
                step(.tool, "Wait · \(String(format: "%.1f", secs))s")
                try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
                messages.append(observation(prefix: "OBSERVATION: waited \(String(format: "%.1f", secs))s for the screen to settle."))

            case "get_skill":
                step(.tool, "Check skills")
                let all = SkillStore.all()
                if all.isEmpty {
                    messages.append(["role": "user", "content": "OBSERVATION: no learned skills yet. Proceed with the task normally."])
                } else {
                    let list = all.map { "- \"\($0.name)\": \($0.description.isEmpty ? "(no description)" : $0.description)" }.joined(separator: "\n")
                    log("GET_SKILL → \(all.count) skill(s)")
                    messages.append(["role": "user", "content": "LEARNED SKILLS (call use_skill with a name if one fits; else proceed normally):\n\(list)"])
                }

            case "use_skill":
                let want = (action.text ?? "").lowercased().trimmingCharacters(in: .whitespaces)
                let all = SkillStore.all()
                let exact = all.first(where: { $0.name.lowercased() == want })
                let fuzzy = all.first(where: { want.contains($0.name.lowercased()) || $0.name.lowercased().contains(want) })
                if let sk = exact ?? fuzzy {
                    step(.tool, "Use skill · \(sk.name)")
                    log("USE_SKILL \"\(sk.name)\"")
                    messages.append(["role": "user", "content": """
                    SKILL "\(sk.name)" — the user demonstrated this. Follow these steps IN ORDER on the CURRENT
                    screen, finding each element by its visible label with click_text (do not reuse old coords):
                    \(sk.plan)
                    """])
                } else {
                    let names = all.map { $0.name }.joined(separator: ", ")
                    messages.append(["role": "user", "content": "OBSERVATION: no skill named \"\(want)\". Available: \(names.isEmpty ? "(none)" : names)."])
                }

            case "nudge":
                guard let lp = lastClickPt else {
                    messages.append(["role": "user", "content": "OBSERVATION: nothing clicked yet — click first, then nudge."]); continue
                }
                let dxImg = CGFloat(action.x ?? 0), dyImg = CGFloat(action.y ?? 0)   // delta in screenshot pixels
                let np = CGPoint(x: lp.x + dxImg * (shotBounds.width / shotImageSize.width),
                                 y: lp.y + dyImg * (shotBounds.height / shotImageSize.height))
                step(.tool, "Nudge (\(Int(dxImg)),\(Int(dyImg)))")
                moveCursor(np)
                try? await Task.sleep(nanoseconds: 350_000_000)
                Clicker.click(atTopLeft: np); lastClickPt = np
                log("NUDGE d=(\(Int(dxImg)),\(Int(dyImg))) → screen=(\(Int(np.x)),\(Int(np.y)))")
                try? await Task.sleep(nanoseconds: 600_000_000)
                messages.append(observation(prefix: "OBSERVATION: nudged to (\(Int(np.x)), \(Int(np.y))) and clicked. Check the blue triangle for where you are now."))

            case "get_screen":
                step(.tool, "Read screen")
                messages.append(observation(prefix: "OBSERVATION: re-read screen."))

            case "finish":
                onFinish(action.say ?? "Done.")
                return

            default:
                messages.append(["role": "user", "content": "OBSERVATION: unknown tool."])
            }
        }
        onFinish("Reached the step limit before finishing.")
    }

    // MARK: helpers
    private static func currentTargetPID(_ fallback: pid_t) -> pid_t {
        if let front = NSWorkspace.shared.frontmostApplication, front.localizedName != "ClickyMine" {
            return front.processIdentifier
        }
        return fallback
    }

    private static func openApp(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", name]
        try? p.run()
    }

    private static func decode(_ raw: String) throws -> Action {
        // strip wrappers some models add: <tool_call> tags and ``` fences
        let s = raw
            .replacingOccurrences(of: "<tool_call>", with: "")
            .replacingOccurrences(of: "</tool_call>", with: "")
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        // happy path: first complete {...} object (minimax echoes it twice)
        if let obj = firstJSONObject(s),
           let a = try? JSONDecoder().decode(Action.self, from: Data(obj.utf8)) {
            return a
        }
        // RECOVERY: models often break `finish` JSON by putting unescaped quotes inside `say`.
        // If the reply clearly means to finish, finish anyway (best-effort text) — never loop into
        // re-doing the task (that's what caused the email to be typed 3×).
        if s.lowercased().contains("finish") {
            let say = extractStringField("say", from: s) ?? "Done."
            return Action(thought: nil, tool: "finish", app: nil, index: nil, x: nil, y: nil, text: nil, keys: nil, say: say, at: nil, target: nil, to: nil, toX: nil, toY: nil, seconds: nil, amount: nil)
        }
        throw NSError(domain: "clicky", code: 5, userInfo: [NSLocalizedDescriptionKey: "No JSON in model reply"])
    }

    /// Best-effort: pull the text of a JSON string field even if its value contains unescaped quotes.
    /// Grabs everything from after `"field":"` to the trailing `"}` / end, unescaping \n and \".
    private static func extractStringField(_ field: String, from s: String) -> String? {
        guard let r = s.range(of: "\"\(field)\"") else { return nil }
        var tail = String(s[r.upperBound...])
        if let colon = tail.firstIndex(of: ":") { tail = String(tail[tail.index(after: colon)...]) }
        tail = tail.trimmingCharacters(in: .whitespaces)
        if tail.hasPrefix("\"") { tail.removeFirst() }
        while tail.hasSuffix("}") || tail.hasSuffix("\"") || tail.hasSuffix(" ") || tail.hasSuffix("\n") {
            tail.removeLast()
        }
        let out = tail.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")
        return out.isEmpty ? nil : out
    }

    /// Keep the screenshot only in the most recent observation; replace older image messages with
    /// their text so the request stays small and fast (the agent only needs to see the CURRENT screen).
    private static func stripOldImages(_ msgs: [[String: Any]]) -> [[String: Any]] {
        var lastImg = -1
        for (i, m) in msgs.enumerated() where m["content"] is [[String: Any]] { lastImg = i }
        return msgs.enumerated().map { (i, m) in
            guard i != lastImg, let arr = m["content"] as? [[String: Any]] else { return m }
            let text = arr.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String ?? ""
            var mm = m; mm["content"] = text; return mm
        }
    }

    private static func firstJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0, i = start
        while i < s.endIndex {
            let c = s[i]
            if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { return String(s[start...i]) } }
            i = s.index(after: i)
        }
        return nil
    }

    private static func describe(_ a: Action) -> String {
        var d = "{\"tool\":\"\(a.tool)\""
        if let i = a.index { d += ",\"index\":\(i)" }
        if let x = a.x, let y = a.y { d += ",\"x\":\(x),\"y\":\(y)" }
        if let t = a.text { d += ",\"text\":\"\(t)\"" }
        if let app = a.app { d += ",\"app\":\"\(app)\"" }
        if let k = a.keys { d += ",\"keys\":\"\(k)\"" }
        if let s = a.say { d += ",\"say\":\"\(s)\"" }
        return d + "}"
    }
}
