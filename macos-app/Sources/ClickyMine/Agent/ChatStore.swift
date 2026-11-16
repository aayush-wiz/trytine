import Foundation

/// One streamed step saved with an assistant turn: kind is "reasoning" or "tool".
struct ChatStep: Codable { let kind: String; let text: String }

/// One message in a conversation. role is "You" (user) or "Clicky" (assistant).
/// Assistant turns may carry the work steps (reasoning + tool calls) they streamed.
struct ChatTurn: Codable { let role: String; let text: String; var steps: [ChatStep]? = nil }

/// A single conversation session — what the chat tab, sidebar and command box all share.
struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var turns: [ChatTurn]
    var created: Date
}

/// Holds all chat sessions and the currently-active one, persisted to disk so the History
/// dropdown survives restarts. A single source of truth shared by every chat surface
/// (notch Chat tab, right sidebar, ⌃⌥Space command box), so follow-up messages keep context.
@MainActor
final class ChatStore {
    static let shared = ChatStore()

    private(set) var sessions: [ChatSession] = []
    private(set) var currentID = UUID()
    /// Fired when the active session changes (new / switched) so surfaces can reload.
    var onChange: (() -> Void)?

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClickyMine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }()

    init() {
        load()
        sessions.removeAll { $0.turns.isEmpty }      // drop blank sessions from past launches
        startNew(notify: false)                       // always begin fresh; old chats live in History
    }

    var current: ChatSession { sessions.first { $0.id == currentID } ?? sessions[0] }

    /// Begin a fresh conversation. If the current session is already empty, reuse it
    /// (so repeatedly hitting ⌃⌥Space / "new chat" doesn't pile up blank sessions).
    @discardableResult
    func startNew(notify: Bool = true) -> ChatSession {
        if let c = sessions.first(where: { $0.id == currentID }), c.turns.isEmpty {
            if notify { onChange?() }
            return c
        }
        let s = ChatSession(id: UUID(), title: "New chat", turns: [], created: Date())
        sessions.insert(s, at: 0)
        currentID = s.id
        save()
        if notify { onChange?() }
        return s
    }

    func switchTo(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentID = id
        onChange?()
    }

    /// Append a message to the active session. Does NOT fire onChange — the surface that's
    /// streaming already shows it, and we don't want to wipe a live transcript mid-run.
    func addTurn(role: String, text: String, steps: [ChatStep]? = nil) {
        guard let i = sessions.firstIndex(where: { $0.id == currentID }) else { return }
        sessions[i].turns.append(ChatTurn(role: role, text: text, steps: steps))
        if role == "You", sessions[i].title == "New chat" {
            sessions[i].title = String(text.prefix(44))
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }
        sessions = s
    }
    private func save() {
        if let data = try? JSONEncoder().encode(sessions) { try? data.write(to: url) }
    }
}
