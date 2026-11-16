import AppKit
import ApplicationServices

/// What the user is doing RIGHT NOW — read deterministically from macOS, no AI, no screenshots.
struct Context {
    var app: String          // frontmost application
    var window: String       // focused window title
    var role: String         // UI element under the cursor (button, textfield, link…)
    var label: String        // that element's title/value/description
    var mouse: CGPoint       // pointer position (top-left origin)
}

enum Inspector {
    /// Read the live context at the current mouse position.
    static func current() -> Context {
        let systemWide = AXUIElementCreateSystemWide()
        // mouse position — NSEvent is bottom-left origin; flip to top-left for AX
        let m = NSEvent.mouseLocation
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let pt = CGPoint(x: m.x, y: screenH - m.y)

        var app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        var role = "—", label = "", window = ""

        // the UI element directly under the cursor
        var elementRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(pt.x), Float(pt.y), &elementRef) == .success,
           let element = elementRef {

            // the app that OWNS the element under the cursor (not the frontmost app)
            var epid: pid_t = 0
            if AXUIElementGetPid(element, &epid) == .success,
               let owner = NSRunningApplication(processIdentifier: epid)?.localizedName {
                app = owner
                // unlock Chromium/Electron web a11y tree (hidden by default)
                let appEl = AXUIElementCreateApplication(epid)
                AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }

            role = str(element, "AXRoleDescription") ?? str(element, kAXRoleAttribute) ?? "—"
            label = firstLabel(element)
            // climb parents for a label and the enclosing window title
            var node = element, hops = 0
            while hops < 8 {
                if window.isEmpty, str(node, kAXRoleAttribute) == "AXWindow" {
                    window = str(node, kAXTitleAttribute) ?? ""
                }
                if label.isEmpty { label = firstLabel(node) }
                var pRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &pRef) == .success,
                      let p = pRef, CFGetTypeID(p) == AXUIElementGetTypeID() else { break }
                node = p as! AXUIElement; hops += 1
            }
        }

        return Context(app: app, window: window, role: role, label: label, mouse: pt)
    }

    /// The text the user is currently typing — read from the focused text field via AX
    /// (uses Accessibility permission; no keylogging / Input-Monitoring needed).
    static func focusedTyping() -> (app: String, text: String)? {
        let systemWide = AXUIElementCreateSystemWide()
        var f: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &f) == .success,
              let raw = f, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let el = raw as! AXUIElement
        let role = str(el, kAXRoleAttribute) ?? ""
        // only real single-line input fields — NOT text areas (terminals/editors dump huge buffers)
        let editable = ["AXTextField", "AXComboBox", "AXSearchField"]
        guard editable.contains(role) else { return nil }
        guard let value = str(el, kAXValueAttribute), !value.isEmpty, value.count <= 120 else { return nil }
        var pid: pid_t = 0; AXUIElementGetPid(el, &pid)
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
        return (app, value)
    }

    /// Can the currently-focused element accept typed text? Used to avoid "typing into nothing" (which
    /// just makes macOS beep). Permissive: blocks ONLY when nothing is focused, or the focus is clearly a
    /// non-text control (a button/checkbox/etc.). Everything else — text fields, date-time areas (Calendar
    /// time), steppers, web inputs, unknown roles — is allowed.
    static func focusedAcceptsTyping() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var f: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &f) == .success,
              let raw = f, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }   // nothing focused → block
        let el = raw as! AXUIElement
        let role = str(el, kAXRoleAttribute) ?? ""
        let desc = (str(el, kAXRoleDescriptionAttribute) ?? "").lowercased()
        // RESCUE genuine editable areas whose AXRole is nonstandard — Calendar's time stepper reports the
        // role description "date time area", not AXTextField. If the focus clearly reads as a text/date/
        // time/edit field, allow typing regardless of its raw role.
        if editableRoles.contains(role) { return true }
        if desc.contains("text") || desc.contains("date") || desc.contains("time")
            || desc.contains("field") || desc.contains("edit") || desc.contains("combo") { return true }
        // Otherwise BLOCK generic containers and non-text controls. Typing into one of these does nothing but
        // make macOS beep and the text is lost — this is the "I hear a click sound but nothing types" bug.
        // Blocking it makes the agent click a real field first instead of typing into the void.
        let cannotType: Set<String> = [
            "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXImage",
            "AXMenuItem", "AXMenuBarItem", "AXSlider", "AXGroup", "AXLayoutArea", "AXLayoutItem",
            "AXScrollArea", "AXSplitGroup", "AXList", "AXTable", "AXOutline", "AXRow", "AXColumn",
            "AXToolbar", "AXTabGroup", "AXStaticText", "AXUnknown", ""]
        return !cannotType.contains(role)   // web areas / unknown editable roles still allowed
    }

    struct Elem { let label: String; let role: String; let center: CGPoint; let frame: CGRect }   // screen top-left coords

    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    /// Walk an app's accessibility tree and collect every actionable element with its EXACT frame + label.
    /// "Actionable" = supports the AXPress action (the universal clickable test — works for native AND
    /// web content) or is an editable text field. This surfaces web links, search boxes, list rows, etc.
    static func clickableElements(pid: pid_t, limit: Int = 400) -> [Elem] {
        let app = AXUIElementCreateApplication(pid)
        // unlock Chromium/Electron web accessibility (the web page's elements live behind this)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        var out: [Elem] = []
        var seen = Set<String>()                       // dedupe by label+position
        var stack: [(AXUIElement, Int)] = [(app, 0)]
        while let (el, depth) = stack.popLast(), out.count < limit {
            if depth > 40 { continue }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let kids = childrenRef as? [AXUIElement] {
                for k in kids.prefix(150) { stack.append((k, depth + 1)) }
            }
            let role = str(el, kAXRoleAttribute) ?? ""
            guard pressable(el) || editableRoles.contains(role) else { continue }
            guard let f = frameOf(el) else { continue }
            let c = CGPoint(x: f.midX, y: f.midY)
            let label = firstLabel(el)
            guard !label.isEmpty, label.count <= 80 else { continue }
            let key = "\(Int(c.x)),\(Int(c.y)):\(label)"
            if seen.contains(key) { continue }; seen.insert(key)
            let nice = role.replacingOccurrences(of: "AX", with: "")
            out.append(Elem(label: label.replacingOccurrences(of: "\n", with: " "), role: nice, center: c, frame: f))
        }
        return out
    }

    /// True if the element supports the AXPress action — the definitive "is this clickable" signal.
    private static func pressable(_ el: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success,
              let arr = names as? [String] else { return false }
        return arr.contains(kAXPressAction as String)
    }

    private static func frameOf(_ el: AXUIElement) -> CGRect? {
        var pRef: CFTypeRef?, sRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sRef) == .success else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(pRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sRef as! AXValue, .cgSize, &size)
        guard size.width > 2, size.height > 2 else { return nil }
        return CGRect(origin: pos, size: size)   // screen top-left coords, points
    }

    /// Best human label for an element from the common AX text attributes.
    private static func firstLabel(_ el: AXUIElement) -> String {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, "AXValueDescription",
                     kAXValueAttribute, kAXHelpAttribute, "AXSelectedText", "AXPlaceholderValue"] {
            if let s = str(el, attr) { return s }
        }
        return ""
    }

    private static func str(_ el: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        if let s = ref as? String, !s.isEmpty { return s }
        return nil
    }

    static func ensureAccessibility() -> Bool {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
