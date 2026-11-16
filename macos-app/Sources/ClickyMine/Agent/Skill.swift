import Foundation

/// A learned task. `rawActivity` is the slice of the EXISTING Activity feed captured between teaching
/// start and stop (the same `🖱 CLICK …` / `⌨️ TYPE …` lines already recorded). `plan` is the LLM's
/// cleaned, generalized step list used for replay.
struct Skill: Codable {
    var name: String
    var description: String
    var plan: String              // numbered, generalized steps referring to elements by label
    var rawActivity: [String]     // the captured activity-feed lines from the demonstration
    var createdAt: Date
}

/// Persists learned skills as JSON under Application Support, and matches a chat message to a skill.
enum SkillStore {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClickyMine/skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return s.lowercased().replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: allowed.inverted).joined()
    }

    static func save(_ skill: Skill) {
        let url = dir.appendingPathComponent(slug(skill.name) + ".json")
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(skill) { try? data.write(to: url) }
        log("SKILL saved \"\(skill.name)\" → \(url.lastPathComponent)")
    }

    static func all() -> [Skill] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? dec.decode(Skill.self, from: $0) } }
    }
}

/// Captures the Activity feed while "teaching" is on. Start → the existing activity lines are buffered →
/// Stop returns them for the LLM to turn into a skill. No new recording machinery — it taps what the
/// Activity feed already records.
@MainActor
final class SkillRecorder {
    static let shared = SkillRecorder()
    private(set) var active = false
    private(set) var paused = false
    private(set) var name = ""
    private(set) var description = ""
    private var lines: [String] = []

    func start(name: String, description: String) {
        self.name = name; self.description = description
        lines = []; active = true; paused = false
        log("TEACH start \"\(name)\"")
    }

    func pause()  { guard active else { return }; paused = true;  log("TEACH paused") }
    func resume() { guard active else { return }; paused = false; log("TEACH resumed") }

    /// Called wherever the Activity feed appends a USER action line (click / type / scroll).
    func capture(_ line: String) {
        guard active, !paused else { return }
        lines.append(line)
    }

    func stop() -> (name: String, description: String, lines: [String])? {
        guard active else { return nil }
        active = false; paused = false
        log("TEACH stop \"\(name)\" — \(lines.count) activity lines")
        return (name, description, lines)
    }
}
