import AppKit
import Vision

/// Deterministic on-screen text locator. OCRs the display and returns every text string with its
/// EXACT center in screen points (top-left origin). This works on CANVAS content — Google Sheets
/// cells/headers, etc. — that exposes nothing to Accessibility. No LLM, no guessing: same pixels,
/// same coordinates every time.
enum OCR {
    /// Recognize all text on the main display. Returns each string as a clickable Elem whose `center`
    /// is the exact screen point of that text (top-left origin, points — the space `Clicker` clicks in).
    @MainActor
    static func locate(limit: Int = 250) -> [Inspector.Elem] {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        guard let img = CGWindowListCreateImage(bounds, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
                ?? CGDisplayCreateImage(CGMainDisplayID()) else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate         // word-level boxes, high quality
        req.usesLanguageCorrection = false       // don't "fix" cell values / labels
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        do { try handler.perform([req]) } catch { log("OCR error: \(error.localizedDescription)"); return [] }
        guard let results = req.results else { return [] }
        var out: [Inspector.Elem] = []
        for obs in results.prefix(limit) {
            guard let top = obs.topCandidates(1).first else { continue }
            let s = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            // Vision boundingBox: normalized 0..1, BOTTOM-left origin, relative to the image.
            let bb = obs.boundingBox
            // Full box in screen points (TOP-left origin). Top edge = 1 - bb.maxY (y is flipped).
            let frame = CGRect(x: bounds.minX + bb.minX * bounds.width,
                               y: bounds.minY + (1.0 - bb.maxY) * bounds.height,
                               width: bb.width * bounds.width,
                               height: bb.height * bounds.height)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            out.append(Inspector.Elem(label: String(s.prefix(80)), role: "Text", center: center, frame: frame))
        }
        log("OCR \(out.count) text boxes: \(out.prefix(12).map { $0.label }.joined(separator: " | "))")
        return out
    }
}
