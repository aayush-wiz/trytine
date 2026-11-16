import Foundation

struct ClickyReply: Decodable {
    let say: String       // what to speak
    let x: Double         // 0..1 fraction from left  (where to point)
    let y: Double         // 0..1 fraction from top
    let point: Bool       // whether there's a thing worth pointing at
    let click: Bool       // whether the buddy should actually CLICK that point
}

/// LLM client. Uses OpenRouter (OpenAI-compatible) — same key/model as company-brain.
/// Default model deepseek/deepseek-chat. NOTE: deepseek-chat is TEXT-ONLY (no vision),
/// so screenshots are only sent when a vision-capable model is configured.
enum Claude {
    /// Main agent model (notch command bar, chat tab, sidebar). Set via LLM_MODEL.
    static var model: String { ProcessInfo.processInfo.environment["LLM_MODEL"] ?? "deepseek/deepseek-chat" }
    /// Model used for the inline cursor bar. Set via LLM_MODEL_INLINE (falls back to `model`).
    static var inlineModel: String { ProcessInfo.processInfo.environment["LLM_MODEL_INLINE"] ?? model }

    /// Generic chat completion over a pre-serialized request body → returns the text content.
    /// (Body is built/serialized by the caller so no non-Sendable dict crosses an actor boundary.)
    static func complete(bodyData: Data) async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "clicky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set OPENROUTER_API_KEY"])
        }
        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        let data = try await send(req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else {
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad response"])
        }
        var text = (msg["content"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ""
        if text.isEmpty, let r = msg["reasoning"] as? String { text = r }
        return text
    }

    /// Like `complete`, but also returns the model's separate reasoning/chain-of-thought field
    /// (reasoning models put their thinking here, distinct from the JSON answer in `content`).
    static func completeFull(bodyData: Data) async throws -> (text: String, reasoning: String) {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "clicky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set OPENROUTER_API_KEY"])
        }
        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        let data = try await send(req)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = ((json ?? [:])["error"] as? [String: Any])?["message"] as? String {
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        guard let choices = (json ?? [:])["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else {
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad response"])
        }
        let content = (msg["content"] as? String) ?? ""
        let reasoning = (msg["reasoning"] as? String) ?? ""
        let text = content.isEmpty ? reasoning : content
        return (text, reasoning)
    }

    /// Turn a demonstrated Activity trace into a clean, generalized, replayable step plan.
    static func summarizeSkill(name: String, description: String, activity: [String]) async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else { return "" }
        let trace = activity.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let system = """
        The user DEMONSTRATED a task by doing it manually. Below is the raw recorded Activity trace
        (their real clicks — with the app, the element's role and visible label, and approx coordinates —
        and what they typed). Turn it into a clean, GENERALIZED, ordered step-by-step plan that an agent
        can follow to repeat the task on a fresh screen.

        RULES:
        - Refer to UI elements by their VISIBLE LABEL/TEXT (e.g. the "Data" menu, the "Amount Raised"
          header, the "Filter by condition" item). NEVER rely on coordinates — they shift.
        - Merge redundant/stray actions and drop obvious misclicks or accidental focus changes.
        - One action per numbered line. Start by stating which app to use.
        - Keep any text the user typed exactly.
        Task name: \(name)\(description.isEmpty ? "" : " — \(description)")
        """
        let body: [String: Any] = ["model": model, "max_tokens": 1200, "messages": [
            ["role": "system", "content": system],
            ["role": "user", "content": "RAW ACTIVITY TRACE:\n\(trace)\n\nReturn ONLY the numbered plan."]]]
        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else { return "" }
        var text = (msg["content"] as? String) ?? ""
        if text.isEmpty, let r = msg["reasoning"] as? String { text = r }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Zoom-refine: given a blown-up crop, return the EXACT pixel of the target in that crop.
    /// Returns nil if the target isn't visible (caller keeps the rough point).
    static func refinePoint(imageBase64: String, w: Int, h: Int, target: String, model: String) async throws -> (x: Int, y: Int)? {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else { return nil }
        let system = """
        You are given a ZOOMED-IN crop of the user's screen, exactly \(w)x\(h) pixels (origin top-left, x→right, y→down).
        Return the EXACT pixel at the CENTER of this target: \(target)
        Reply with ONLY JSON: {"x": <int>, "y": <int>} in pixels of THIS image.
        If the target is NOT visible in this crop, reply {"x": -1, "y": -1}.
        """
        let body: [String: Any] = ["model": model, "max_tokens": 400, "messages": [
            ["role": "system", "content": system],
            ["role": "user", "content": [
                ["type": "text", "text": "Give the exact pixel of the target in this zoomed image."],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(imageBase64)"]]]]]]
        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else { return nil }
        var text = (msg["content"] as? String) ?? ""
        if text.isEmpty, let r = msg["reasoning"] as? String { text = r }
        text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        if let lo = text.lastIndex(of: "{"), let hi = text.lastIndex(of: "}"), lo < hi { text = String(text[lo...hi]) }
        struct P: Decodable { let x: Int; let y: Int }
        guard let p = try? JSONDecoder().decode(P.self, from: Data(text.utf8)), p.x >= 0, p.y >= 0 else { return nil }
        return (p.x, p.y)
    }

    static func completeBody(messages: [[String: Any]], model: String? = nil, tools: [[String: Any]]? = nil) -> Data {
        var body: [String: Any] = ["model": model ?? self.model, "max_tokens": 2500, "messages": messages]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"      // structured function-calling: the model picks a tool itself
        }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// Structured function-calling call. Returns the FIRST tool_call the model made (name + raw JSON
    /// arguments), plus any assistant text and reasoning. tool name/args are nil when the model replied
    /// with plain text instead of calling a tool.
    static func completeTool(bodyData: Data) async throws
        -> (toolName: String?, toolArgs: String?, text: String, reasoning: String) {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "clicky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set OPENROUTER_API_KEY"])
        }
        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        let data = try await send(req)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = ((json ?? [:])["error"] as? [String: Any])?["message"] as? String {
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: err])
        }
        guard let choices = (json ?? [:])["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else {
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad response"])
        }
        let content = (msg["content"] as? String) ?? ""
        let reasoning = (msg["reasoning"] as? String) ?? ""
        var name: String? = nil, args: String? = nil
        if let calls = msg["tool_calls"] as? [[String: Any]],
           let fn = calls.first?["function"] as? [String: Any] {
            name = fn["name"] as? String
            args = fn["arguments"] as? String
        }
        return (name, args, content, reasoning)
    }

    /// POST with up to 3 retries for transient network/TLS failures.
    static func send(_ req: URLRequest) async throws -> Data {
        var lastErr: Error?
        for attempt in 0..<3 {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                return data
            } catch {
                lastErr = error
                try? await Task.sleep(nanoseconds: UInt64(300_000_000 * (attempt + 1)))
            }
        }
        throw lastErr ?? NSError(domain: "clicky", code: 99)
    }

    static var baseURL: String { ProcessInfo.processInfo.environment["OPENROUTER_BASE_URL"] ?? "https://openrouter.ai/api/v1" }
    static var supportsVision: Bool { supportsVision(model) }
    /// Every model we configure (main or inline) is a vision model, so always send the screenshot —
    /// the agent needs to SEE web pages (Gmail, search results) that never appear in the AX list.
    static func supportsVision(_ modelName: String) -> Bool { true }

    static func ask(question: String, imageBase64: String) async throws -> ClickyReply {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "clicky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set OPENROUTER_API_KEY"])
        }

        let system = """
        You are Clicky, an agent that CONTROLS the user's Mac by clicking on screen. You are given a
        screenshot and a COMMAND. Your job is to DO it, not describe it.

        Find the single UI element that fulfills the command (a button, link, field, menu item, icon, tab).
        Locate its CENTER and return x,y as fractions 0.0-1.0 from the TOP-LEFT of the image.
        ALWAYS set "click": true and "point": true whenever the command asks to click / open / press / select /
        go to / type in something AND you can see a plausible target — even if you think it may already be
        open, click it anyway. Only set click=false if the command is a pure question ("what is this?").
        Never say it's "already done/open"; just click the best matching element.
        "say" = one short spoken sentence describing the action you are taking (e.g. "Opening Settings.").

        Reply ONLY with JSON: {"say": string, "x": number, "y": number, "point": boolean, "click": boolean}
        """

        // Build user content. Vision models get the screenshot; text-only models get text only.
        var userContent: Any
        if supportsVision {
            userContent = [
                ["type": "text", "text": question],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]]
            ]
        } else {
            userContent = question + "\n\n(Note: you cannot see the screen with this model.)"
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2500,        // reasoning models need room to think AND emit the final JSON
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent]
            ]
        ]

        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("https://clicky.local", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("ClickyMine", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if let h = FileHandle(forWritingAtPath: "/tmp/clicky-debug.log") {
            h.seekToEndOfFile()
            h.write("RAW ASK status=\(code) bytes=\(data.count) body=\(String(data: data, encoding: .utf8) ?? "nil")\n".data(using: .utf8)!)
            h.closeFile()
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "?"
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad response: \(raw.prefix(200))"])
        }
        // prefer the final answer in `content`; only fall back to reasoning if it contains a JSON object
        var text = (msg["content"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ""
        if text.isEmpty, let r = msg["reasoning"] as? String, r.contains("{"), r.contains("}") { text = r }
        guard !text.isEmpty else {
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model returned no answer (try again)"])
        }

        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        // grab the first {...} block in case the model adds prose
        if let lo = cleaned.firstIndex(of: "{"), let hi = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[lo...hi])
        }
        return try JSONDecoder().decode(ClickyReply.self, from: Data(cleaned.utf8))
    }

    struct ClickyPick: Decodable {
        let index: Int
        let say: String
        let type: String?      // optional text to type into the element after clicking it
        let submit: Bool?      // press Return after typing (e.g. to run a search)
    }

    /// Pick which clickable element (by index) fulfils the command. The model does semantic matching;
    /// exact coordinates come from Accessibility — so clicks are pixel-perfect.
    static func pickTarget(command: String, elements: [(label: String, role: String)], imageBase64: String) async throws -> ClickyPick {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "clicky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set OPENROUTER_API_KEY"])
        }
        let list = elements.enumerated()
            .map { "[\($0.offset)] \($0.element.role.replacingOccurrences(of: "AX", with: "")) — \"\($0.element.label)\"" }
            .joined(separator: "\n")
        let system = """
        You control a Mac. You get a COMMAND and a numbered list of the clickable UI elements currently
        on screen (with a screenshot for context). Choose the ONE element that best fulfils the command.
        If the command also asks to TYPE / SEARCH / ENTER text, pick the text field/search box element and
        put the exact text in "type". Set "submit": true if it should press Return afterward (e.g. a search).
        Return ONLY JSON:
        {"index": <number from list>, "say": "<short action>", "type": "<text or empty>", "submit": <true/false>}
        If nothing matches, use {"index": -1, "say": "I can't find that on screen.", "type": "", "submit": false}.
        """
        let userText = "COMMAND: \(command)\n\nCLICKABLE ELEMENTS:\n\(list)"
        var content: Any = userText
        if supportsVision {
            content = [["type": "text", "text": userText],
                       ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]]]
        }
        let body: [String: Any] = ["model": model, "max_tokens": 2500,
            "messages": [["role": "system", "content": system], ["role": "user", "content": content]]]

        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else {
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad response"])
        }
        var text = (msg["content"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ""
        if text.isEmpty, let r = msg["reasoning"] as? String { text = r }
        text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        if let lo = text.lastIndex(of: "{"), let hi = text.lastIndex(of: "}"), lo < hi {
            text = String(text[lo...hi])
        }
        return try JSONDecoder().decode(ClickyPick.self, from: Data(text.utf8))
    }

    /// Plain ChatGPT-style turn. Optional image (screenshot or uploaded file) for vision.
    static func chat(history: [(role: String, text: String)], imageBase64: String?) async throws -> String {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
            throw NSError(domain: "clicky", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set OPENROUTER_API_KEY"])
        }
        var messages: [[String: Any]] = [[
            "role": "system",
            "content": "You are Clicky, a helpful assistant living on the user's Mac. Be concise and friendly."
        ]]
        for (i, turn) in history.enumerated() {
            // attach the image to the LAST user turn only
            if turn.role == "user", i == history.count - 1, let img = imageBase64, supportsVision {
                messages.append(["role": "user", "content": [
                    ["type": "text", "text": turn.text],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(img)"]]
                ]])
            } else {
                messages.append(["role": turn.role, "content": turn.text])
            }
        }
        let body: [String: Any] = ["model": model, "max_tokens": 1024, "messages": messages]

        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        if let h = FileHandle(forWritingAtPath: "/tmp/clicky-debug.log") {
            h.seekToEndOfFile()
            h.write("RAW CHAT RESPONSE: \(String(data: data, encoding: .utf8) ?? "?")\n".data(using: .utf8)!)
            h.closeFile()
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "?"
            throw NSError(domain: "clicky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad response: \(raw)"])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
