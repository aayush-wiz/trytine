import Foundation
import Speech
import AVFoundation

func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    if let h = FileHandle(forWritingAtPath: "/tmp/clicky-debug.log") {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else { try? line.write(toFile: "/tmp/clicky-debug.log", atomically: true, encoding: .utf8) }
}

/// Push-to-talk speech-to-text using Apple's on-device Speech framework.
/// Press to start listening, press again to stop → returns the transcript.
@MainActor
final class SpeechManager {
    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isListening = false
    private var transcript = ""

    var onPartial: ((String) -> Void)?

    /// Request BOTH speech + microphone permission, then call back on the main thread.
    /// Must complete before touching the audio engine, or macOS kills the process.
    func requestPermissions(_ done: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            AVCaptureDevice.requestAccess(for: .audio) { micOK in
                let ok = (status == .authorized) && micOK
                log("Voice: permissions speech=\(status.rawValue) mic=\(micOK)")
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { done(ok) }
                }
            }
        }
    }

    func start() throws {
        guard !isListening else { return }
        transcript = ""
        log("Voice: creating request")
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        log("Voice: getting input node")
        let input = engine.inputNode
        let fmt = input.inputFormat(forBus: 0)
        log("Voice: format ch=\(fmt.channelCount) sr=\(fmt.sampleRate)")
        guard fmt.channelCount > 0 else {
            throw NSError(domain: "voice", code: 9, userInfo: [NSLocalizedDescriptionKey: "no mic input"])
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
        log("Voice: tap installed, starting engine")
        engine.prepare()
        try engine.start()
        log("Voice: engine started")
        isListening = true

        task = recognizer?.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let r = result else { return }
            let text = r.bestTranscription.formattedString
            DispatchQueue.main.async {           // callback is on a background queue → hop to main
                MainActor.assumeIsolated {
                    self.transcript = text
                    self.onPartial?(text)
                }
            }
        }
    }

    /// Stop and return the final transcript shortly after (lets the recognizer flush).
    func stop(_ completion: @escaping (String) -> Void) {
        guard isListening else { completion(""); return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isListening = false
        // give the recognizer a beat to finalize the last words
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                let final = self?.transcript ?? ""
                self?.task?.cancel()
                self?.task = nil
                completion(final)
            }
        }
    }
}
