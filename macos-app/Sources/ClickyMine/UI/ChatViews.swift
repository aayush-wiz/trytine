import AppKit
import QuartzCore

/// Flipped container so a chat list flows top→down inside an NSScrollView.
@MainActor
final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// A label whose text is filled with a gradient that sweeps left→right — the "Working" shimmer,
/// like the orpex / Grammarly thinking header. Stops to a flat muted color when finished.
@MainActor
final class ShimmerLabel: NSView {
    private let grad = CAGradientLayer()
    private let textLayer = CATextLayer()
    private var text: String
    private let weight: NSFont.Weight = .semibold
    let fontSize: CGFloat = 13

    init(_ s: String) {
        text = s
        super.init(frame: .zero)
        wantsLayer = true
        let dim = Theme.shared.inkFaint.cgColor
        let bright = Theme.shared.ink.cgColor
        grad.colors = [dim, bright, dim]
        grad.startPoint = CGPoint(x: 0, y: 0.5)
        grad.endPoint = CGPoint(x: 1, y: 0.5)
        grad.locations = [0, 0.5, 1]
        textLayer.string = s
        textLayer.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.truncationMode = .end
        grad.mask = textLayer
        layer?.addSublayer(grad)
        startShimmer()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func layout() { super.layout(); grad.frame = bounds; textLayer.frame = bounds }

    override var intrinsicContentSize: NSSize {
        let attr = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: fontSize, weight: weight)]
        let sz = (text as NSString).size(withAttributes: attr)
        return NSSize(width: ceil(sz.width) + 4, height: ceil(sz.height) + 2)
    }

    func setText(_ s: String) { text = s; textLayer.string = s; invalidateIntrinsicContentSize(); needsLayout = true }

    func startShimmer() {
        grad.colors = [Theme.shared.inkFaint.cgColor, Theme.shared.ink.cgColor, Theme.shared.inkFaint.cgColor]
        grad.removeAnimation(forKey: "shimmer")
        let a = CABasicAnimation(keyPath: "locations")
        a.fromValue = [-1.0, -0.5, 0.0]
        a.toValue = [1.0, 1.5, 2.0]
        a.duration = 1.5
        a.repeatCount = .infinity
        grad.add(a, forKey: "shimmer")
    }
    func stopShimmer() {
        grad.removeAnimation(forKey: "shimmer")
        let flat = Theme.shared.inkFaint.cgColor
        grad.colors = [flat, flat, flat]
    }
}

/// The collapsible "Working… / Worked for Ns" dropdown: a clickable shimmer header with a
/// chevron, and an indented body holding the streamed reasoning + tool-call steps.
@MainActor
final class WorkGroupView: NSView {
    private let chevron = NSImageView()
    private let shimmer = ShimmerLabel("Working")
    private let body = NSStackView()
    private var expanded = true
    private let started = Date()
    private var finished = false
    var onLayoutChange: (() -> Void)?
    private var bodyBottom: NSLayoutConstraint!      // active when expanded
    private var collapsedBottom: NSLayoutConstraint! // active when collapsed (no body height)
    private(set) var steps: [ChatStep] = []          // streamed steps, for persistence

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.contentTintColor = Theme.shared.inkFaint
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.imageScaling = .scaleProportionallyDown
        addSubview(chevron)
        shimmer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shimmer)

        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 9
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)

        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            chevron.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
            shimmer.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 7),
            shimmer.centerYAnchor.constraint(equalTo: chevron.centerYAnchor),
            shimmer.heightAnchor.constraint(equalToConstant: 18),

            body.topAnchor.constraint(equalTo: chevron.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),   // indented right
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
        // bottom is driven by the body when expanded, or by the header when collapsed (no gap)
        bodyBottom = body.bottomAnchor.constraint(equalTo: bottomAnchor)
        collapsedBottom = chevron.bottomAnchor.constraint(equalTo: bottomAnchor)
        bodyBottom.isActive = true

        let click = NSClickGestureRecognizer(target: self, action: #selector(toggle))
        addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Rebuild a finished, collapsed group from previously-saved steps (on session reload).
    func loadSaved(_ saved: [ChatStep]) {
        for st in saved {
            if st.kind == "tool" { addTool(st.text) } else { addReasoning(st.text) }
        }
        finished = true
        shimmer.stopShimmer()
        shimmer.setText("Worked")
        setExpanded(false)
    }

    /// One reasoning chunk — the model's own thinking, as muted flowing prose.
    func addReasoning(_ s: String) {
        steps.append(ChatStep(kind: "reasoning", text: s))
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: 12.5)
        l.textColor = Theme.shared.inkFaint
        l.isSelectable = true; l.isEditable = false; l.drawsBackground = false; l.isBordered = false
        l.translatesAutoresizingMaskIntoConstraints = false
        addRow(l)
    }

    /// One tool call — its real derived name, as a bold dotted step line.
    func addTool(_ s: String) {
        steps.append(ChatStep(kind: "tool", text: s))
        let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
        let dot = NSTextField(labelWithString: "•")
        dot.font = .systemFont(ofSize: 13); dot.textColor = Theme.shared.inkFaint
        dot.translatesAutoresizingMaskIntoConstraints = false
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: 12.5, weight: .semibold)
        l.textColor = Theme.shared.inkDim
        l.isSelectable = true; l.isEditable = false; l.drawsBackground = false; l.isBordered = false
        l.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(dot); row.addSubview(l)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            dot.topAnchor.constraint(equalTo: row.topAnchor),
            l.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            l.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            l.topAnchor.constraint(equalTo: row.topAnchor),
            l.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        addRow(row)
    }

    private func addRow(_ v: NSView) {
        body.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        onLayoutChange?()
    }

    func finish() {
        guard !finished else { return }
        finished = true
        shimmer.stopShimmer()
        let secs = max(1, Int(Date().timeIntervalSince(started).rounded()))
        shimmer.setText("Worked for \(secs)s")
        // collapse by default once done, like orpex
        setExpanded(false)
    }

    @objc private func toggle() { setExpanded(!expanded) }
    private func setExpanded(_ on: Bool) {
        expanded = on
        body.isHidden = !on
        bodyBottom.isActive = on
        collapsedBottom.isActive = !on
        chevron.image = NSImage(systemSymbolName: on ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        onLayoutChange?()
    }
}
