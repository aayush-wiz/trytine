import AppKit

/// App-wide light/dark theme. A single source of truth that every surface reads from.
/// Switching it flips `NSApp.appearance` (so all stock AppKit controls — text fields,
/// segmented controls, menus, scrollers — adapt automatically) and fires `onChange`
/// so our custom-drawn surfaces (the notch island, chat bubbles) can restyle + redraw.
@MainActor
final class Theme {
    static let shared = Theme()

    private let key = "ClickyTheme.isDark"
    private(set) var isDark: Bool

    /// Observers, keyed by an arbitrary token so views can register without retain cycles.
    private var observers: [ObjectIdentifier: () -> Void] = [:]

    private init() {
        if UserDefaults.standard.object(forKey: key) == nil {
            isDark = true                                   // default: dark
        } else {
            isDark = UserDefaults.standard.bool(forKey: key)
        }
    }

    func toggle() { set(isDark: !isDark) }

    func set(isDark v: Bool) {
        isDark = v
        UserDefaults.standard.set(v, forKey: key)
        apply()
        for cb in observers.values { cb() }
    }

    /// Push the current theme onto the running app (call once at launch and on every change).
    func apply() {
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    func observe(_ owner: AnyObject, _ cb: @escaping () -> Void) {
        observers[ObjectIdentifier(owner)] = cb
    }

    // MARK: palette ------------------------------------------------------------
    // Notch / panel surface gradient (top → bottom).
    var surfaceTop: NSColor { isDark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.99, alpha: 1) }
    var surfaceBot: NSColor { isDark ? NSColor(calibratedWhite: 0.04, alpha: 1) : NSColor(calibratedWhite: 0.92, alpha: 1) }

    var ink: NSColor { isDark ? .white : NSColor(calibratedWhite: 0.10, alpha: 1) }                       // primary text
    var inkDim: NSColor { isDark ? NSColor(white: 0.85, alpha: 1) : NSColor(calibratedWhite: 0.30, alpha: 1) }
    var inkFaint: NSColor { isDark ? NSColor(white: 0.5, alpha: 1) : NSColor(calibratedWhite: 0.55, alpha: 1) }

    /// Translucent fill for inset controls (the command pill, input wells).
    var well: NSColor { isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.06) }

    var accent: NSColor { NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1) }

    // Floating panel (sidebar) surface.
    var panelBg: NSColor { isDark ? NSColor(calibratedWhite: 0.09, alpha: 0.98) : NSColor(calibratedWhite: 0.97, alpha: 0.98) }
    var hairline: NSColor { isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.10) }
    var headerBg: NSColor { isDark ? NSColor(white: 1, alpha: 0.04) : NSColor(white: 0, alpha: 0.03) }

    /// Icon used by the toggle button — show the destination, not the current state.
    var toggleSymbol: String { isDark ? "sun.max.fill" : "moon.fill" }
}
