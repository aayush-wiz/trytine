import AppKit

/// Makes Clicky's own windows (notch, sidebar, inline bar, the blue cursor overlay) VISIBLE to screen
/// recorders — Zoom / Google Meet / Cap / QuickTime — so you can film the agent working, WITHOUT the
/// agent ever seeing or clicking its own UI.
///
/// How: our windows sit at `sharingType = .readOnly` (visible to all capture) the whole time. Right before
/// the agent takes a screenshot we flip them to `.none` (hidden), capture the clean screen, then flip back.
/// That instant is a single frame — invisible in a 30/60fps recording — so the panels appear continuously
/// in your video while the agent's grab stays exactly the plain capture it always was.
@MainActor
final class RecordMode {
    static let shared = RecordMode()
    private var windows: [NSWindow] = []

    /// Interactive panels (notch, sidebar, inline) → hidden during an agent grab, visible to recorders.
    func register(_ w: NSWindow) {
        windows.append(w)
        w.sharingType = .readOnly
    }

    /// The cursor overlay stays VISIBLE even in the agent's screenshot — so the AI can SEE the blue triangle
    /// marking where it currently is / last clicked, and nudge from there. (It's a click-through marker, so
    /// the agent can't act on it.)
    func registerAlwaysVisible(_ w: NSWindow) {
        w.sharingType = .readOnly
    }

    /// Hide our panels for the instant of an agent screenshot (so the AI never sees its own UI).
    func hideForCapture() { for w in windows { w.sharingType = .none } }

    /// Restore them right after the capture so they stay visible in screen recordings.
    func restoreAfterCapture() { for w in windows { w.sharingType = .readOnly } }
}
