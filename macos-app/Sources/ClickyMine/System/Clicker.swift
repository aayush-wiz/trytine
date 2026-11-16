import AppKit
import CoreGraphics

/// Fires a REAL left-click at a screen point (top-left origin, AppKit points).
/// Requires Accessibility permission. This is what turns "pointing" into "acting".
enum Clicker {
    static func click(atTopLeft p: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        // move, then down + up with delays so it registers as a real click and the button is
        // properly released (a too-fast down/up can leave the mouse button "stuck" until quit).
        // flags = [] on every event so a leftover modifier (e.g. ⌘ from a prior hotkey) can't turn this
        // into a ⌘-click (which would open a link in a new tab / multi-select instead of a plain click).
        let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
        move?.flags = []; move?.post(tap: .cghidEventTap)
        usleep(30_000)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
        down?.flags = []; down?.post(tap: .cghidEventTap)
        usleep(60_000)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
        up?.flags = []; up?.post(tap: .cghidEventTap)
        usleep(20_000)
    }

    /// Fires a REAL double-click at a screen point (top-left origin). Sets the click-state field so the
    /// system treats the two clicks as a genuine double-click (needed to open events, enter rename mode, etc.).
    static func doubleClick(atTopLeft p: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(20_000)
        for clickState in 1...2 {
            let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            down?.post(tap: .cghidEventTap)
            usleep(40_000)
            let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            up?.post(tap: .cghidEventTap)
            usleep(40_000)
        }
    }

    /// Fires a REAL right-click (secondary click) at a screen point — opens context menus.
    static func rightClick(atTopLeft p: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .right)
        move?.flags = []; move?.post(tap: .cghidEventTap)
        usleep(30_000)
        let down = CGEvent(mouseEventSource: src, mouseType: .rightMouseDown, mouseCursorPosition: p, mouseButton: .right)
        down?.flags = []; down?.post(tap: .cghidEventTap)
        usleep(60_000)
        let up = CGEvent(mouseEventSource: src, mouseType: .rightMouseUp, mouseCursorPosition: p, mouseButton: .right)
        up?.flags = []; up?.post(tap: .cghidEventTap)
        usleep(20_000)
    }

    /// Press-drag from one screen point to another (sliders, range selection, reordering).
    /// Moves in small steps so the drag is recognized by the target view.
    static func drag(from a: CGPoint, to b: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(30_000)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)
        down?.flags = []; down?.post(tap: .cghidEventTap)
        usleep(80_000)
        let steps = 24
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
            d?.flags = []; d?.post(tap: .cghidEventTap)
            usleep(12_000)
        }
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)
        up?.flags = []; up?.post(tap: .cghidEventTap)
        usleep(20_000)
    }

    /// Type arbitrary text into the currently focused field (synthesized keystrokes).
    static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text {
            var utf16 = Array(String(ch).utf16)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.flags = []                       // FORCE no modifiers — a leftover ⌘/⌥ from a prior hotkey
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)  // would turn
            down?.post(tap: .cghidEventTap)        // "Dentist" into ⌘D ⌘e… → system beep, nothing typed.
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.flags = []
            up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up?.post(tap: .cghidEventTap)
            usleep(8000)
        }
    }

    /// Press the Return key.
    static func pressReturn() { keyCombo([], 0x24) }

    /// Scroll the page under the given point. Positive `lines` scrolls up, negative scrolls down.
    static func scroll(at p: CGPoint, lines: Int32) {
        let src = CGEventSource(stateID: .combinedSessionState)
        CGWarpMouseCursorPosition(p)                 // put the real cursor over the page first
        usleep(20_000)
        for _ in 0..<5 {                             // several steps reach scrollable web/app views
            CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 1,
                    wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
            usleep(15_000)
        }
    }

    /// Press a keyboard shortcut like "cmd+l", "cmd+t", "cmd+shift+t", "esc".
    static func hotkey(_ combo: String) {
        let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        var flags: CGEventFlags = []
        var key: CGKeyCode? = nil
        for p in parts {
            switch p {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            default: key = keyCode(for: p)
            }
        }
        if let k = key { keyCombo(flags, k) }
    }

    private static func keyCombo(_ flags: CGEventFlags, _ key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        down?.flags = flags; down?.post(tap: .cghidEventTap)
        usleep(30_000)
        // RELEASE the modifiers on key-up (flags = []). If we leave the ⌘/⇧ flag set on the up event the
        // window server keeps treating the modifier as held, so the NEXT click becomes a ⌘-click and the
        // next typed text becomes a chord (⌘D…) → beep, nothing entered. Clearing here un-sticks it.
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        up?.flags = []; up?.post(tap: .cghidEventTap)
        usleep(20_000)
    }

    private static func keyCode(for s: String) -> CGKeyCode? {
        let letters: [String: CGKeyCode] = [
            "a":0,"b":11,"c":8,"d":2,"e":14,"f":3,"g":5,"h":4,"i":34,"j":38,"k":40,"l":37,"m":46,
            "n":45,"o":31,"p":35,"q":12,"r":15,"s":1,"t":17,"u":32,"v":9,"w":13,"x":7,"y":16,"z":6,
            "return":36,"enter":36,"space":49,"tab":48,"delete":51,"esc":53,"escape":53,
            "left":123,"right":124,"down":125,"up":126]   // arrows: move between time/date segments, list rows
        return letters[s]
    }
}
