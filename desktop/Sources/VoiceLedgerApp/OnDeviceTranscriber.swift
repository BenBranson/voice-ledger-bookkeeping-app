import Foundation
import Speech
import Voice

/// Apple's on-device speech recognition for a short recorded command
/// (docs/MONEYPENNY_CONSISTENCY_DESIGN.md Part 2, Layer 0). Nothing leaves
/// the Mac. Returns nil whenever it can't run — not authorized, not
/// available for this locale, or slower than the deadline — so the caller
/// falls back to the Whisper voice-service unchanged.
enum OnDeviceTranscriber {
    static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        default: return false
        }
    }

    // A recognizer that cannot finish promptly must not hold a short command
    // for six seconds before the already-warm local Whisper fallback starts.
    static func transcribe(fileAt url: URL, deadline: TimeInterval = 1.5) async -> String? {
        guard await authorize(), let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .search
        request.contextualStrings = VoiceDestination.allCases.map(\.menuTitle) + [
            "month end close", "profit and loss", "balance sheet integrity", "chart of accounts",
            "search by amount", "client diagnostics", "voice history"
        ]
        let box = ResultBox()
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result, result.isFinal { box.finish(result.bestTranscription.formattedString) }
            else if error != nil { box.finish(nil) }
        }
        let started = Date()
        while !Task.isCancelled, !box.isDone, Date().timeIntervalSince(started) < deadline { try? await Task.sleep(for: .milliseconds(40)) }
        if Task.isCancelled || !box.isDone { task.cancel() }
        guard !Task.isCancelled else { return nil }
        return box.value
    }

    /// Thread-safe holder for the recognizer callback's single result.
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var text: String?
        func finish(_ t: String?) { lock.lock(); if !done { done = true; text = t }; lock.unlock() }
        var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }
        var value: String? { lock.lock(); defer { lock.unlock() }; return text }
    }
}
