import Foundation
import AVFoundation
import AppKit
import Observation
import Core
import Voice
import IntegrationsVoice
import IntegrationsQuickBooks

/// docs/VOICE_LEDGER_SPEC.md's `/voice` module's Swift half — owns the
/// microphone/speaker plumbing and orchestrates one voice turn end to end:
/// record → `VoiceServiceClient.transcribe` → `VoiceIntentRouter.match`
/// (deterministic fast path) or the reasoning fallback (existing OpenAI
/// Ask AI path) → apply the resulting `VoiceTurn` → `VoiceServiceClient
/// .synthesize` → play. Ported concept-for-concept from a design already
/// battle-tested in a separate app (`VoiceEngineContext.jsx`) — conversation
/// mode (one click starts an ongoing back-and-forth; mic reopens after each
/// reply), RMS-based silence auto-stop, a live level meter — translated
/// from `getUserMedia`/`MediaRecorder` to `AVCaptureDevice`/`AVAudioEngine`.
///
/// **Never applies a QBO write.** `VoiceIntent` has no case that could
/// (see its own doc comment); the only two `VoicePendingAction` kinds this
/// engine can ever confirm are `dismissFinding`/`completeChecklistItem` —
/// Voice Ledger's own low-stakes internal state, never
/// `AppState.applyStagedFix`. That method is never called from this file.
@MainActor
@Observable
public final class VoiceEngine: NSObject {
    public enum MicPermission: String, Sendable {
        case unknown, granted, denied
    }

    public private(set) var isListening = false
    public private(set) var isSpeaking = false
    public private(set) var isProcessing = false
    public private(set) var conversationMode = false
    /// 0...1, updated live while listening — proves audio is reaching the
    /// engine independent of whether transcription/routing/TTS succeed,
    /// same reasoning `VoiceEngineContext.jsx`'s own comment gives.
    public private(set) var micLevel: Double = 0
    public private(set) var transcript: String = ""
    public private(set) var micPermission: MicPermission = .unknown
    /// The most recent spoken reply, shown on screen too — not just heard.
    public private(set) var lastMessage: String?
    public private(set) var errorMessage: String?
    /// Every past turn, oldest first — persisted via `ClientStore`
    /// (`appendVoiceTranscriptEntry`/`loadVoiceTranscript`) so a
    /// conversation survives an app restart ("working memory," not just
    /// the structural `VoiceSessionContext` pointers). Loaded once in
    /// `loadPersistedContext()`; appended to live as each turn happens.
    public private(set) var transcriptHistory: [VoiceTranscriptEntry] = []

    /// `internal`, not `private` — widened 2026-09-06 so `VoiceToolLoop.swift`
    /// (a same-target extension, kept in its own file for size) can dispatch
    /// tool calls against the same `AppState` this engine already owns,
    /// rather than threading it through every tool function as a parameter.
    unowned let appState: AppState
    private let voiceService: VoiceServiceClient
    /// Which recognizer produced the last transcript ("on-device" / "whisper").
    public private(set) var transcriptSource = ""
    /// The microphone actually in use for the current/last recording.
    public private(set) var activeMicrophoneName = ""
    /// Audio for the rest of a reply, synthesized while the first sentence plays.
    private var pendingSpeechTask: Task<Data?, Never>?
    private var commandTask: Task<Void, Never>?
    private var speechGeneration = 0
    private var isStartingListening = false
    private let actorName: String
    /// `internal`, not `private` — `VoiceToolLoop.swift` reads
    /// `currentEntity` to keep an open-ended follow-up grounded in
    /// whichever finding is currently on screen, same as `explainCurrentEntity` already did.
    var context: VoiceSessionContext = .empty

    private let audioEngine = AVAudioEngine()
    private var recordingURL: URL?
    private var audioPlayer: AVAudioPlayer?
    private var levelMeterTimer: Timer?

    // Everything below is written from inside `installTap`'s callback,
    // which AVAudioEngine invokes on a CoreAudio-owned realtime thread via
    // its `RealtimeMessenger` relay — NOT any GCD queue or thread Swift's
    // concurrency runtime recognizes as the MainActor's executor. THREE
    // separate real, live-verified crashes (2026-08-28) came from letting
    // that callback synchronously touch ANY `@MainActor`-isolated member
    // of this class (a stored property read/write, or a hop back in via
    // `Task`/`DispatchQueue.main.async`/`MainActor.assumeIsolated`) — every
    // one of those inserts a runtime isolation-verification call that
    // fails against that thread's real executor identity and traps with
    // EXC_BREAKPOINT/SIGTRAP. The only combination that doesn't crash:
    // the tap callback touches ONLY `nonisolated(unsafe)` storage
    // (synchronous, no actor involved at all), and a plain `Timer` added
    // to the MAIN run loop — a genuinely different, main-thread execution
    // context the MainActor runtime does recognize correctly — polls that
    // storage and publishes it into the `@Observable` properties below.
    // `nonisolated` alone doesn't compile here — `@Observable`'s macro
    // expansion wraps every stored property (via `@ObservationTracked`),
    // and Swift rejects `nonisolated` on a macro-generated mutable stored
    // property; `nonisolated(unsafe)` is the form that actually works,
    // despite the compiler's (misleading, in this specific case) "has no
    // effect" warning suggestion above.
    @ObservationIgnored nonisolated(unsafe) private var audioFile: AVAudioFile?
    @ObservationIgnored nonisolated(unsafe) private var hasSpokenThisRecording = false
    @ObservationIgnored nonisolated(unsafe) private var endpointDetector = SpeechEndpointDetector()
    @ObservationIgnored nonisolated(unsafe) private var recordingStartedAt: Date?
    @ObservationIgnored nonisolated(unsafe) private var rawMicLevel: Float = 0
    @ObservationIgnored nonisolated(unsafe) private var recordingWriteFailed = false
    @ObservationIgnored nonisolated(unsafe) private var shouldAutoStop = false
    /// Set by a `.AVAudioEngineConfigurationChange` observer (e.g. a
    /// Bluetooth headset connecting/disconnecting mid-recording) — read by
    /// the same safe main-thread timer poll `shouldAutoStop` already uses,
    /// rather than calling back into MainActor code directly from the
    /// notification closure.
    @ObservationIgnored nonisolated(unsafe) private var audioRouteDidChange = false
    private var configurationChangeObserver: NSObjectProtocol?

    /// Fixed key for the reasoning fallback's Ask AI answer slot — every
    /// open-ended voice question shares one slot (each new question
    /// overwrites the last), distinct from `FindingDetailView`'s
    /// per-finding keys and `CleanupAssessmentView`'s page key.
    private static let reasoningContextKey = "voice-reasoning"

    /// Owner directive (2026-09-06): "gemma4:e4b is 3 times faster than
    /// gemma4:12b" — confirmed live (12.0s vs. 5.3s for the same real
    /// question, same grounded-answer quality). The app's global default
    /// model (`gemma4:12b`, set once on the backend) was tuned for the
    /// two on-screen report buttons, where a few extra seconds is
    /// invisible — but every second here is a live silence someone is
    /// listening to. `AppState.askAI`'s `model` param overrides just
    /// these two call sites; every on-screen Ask AI panel elsewhere in
    /// the app is untouched and keeps using the configured default.
    private static let voiceModel = "gemma4:12b"   // owner directive 2026-09-30: best answers over speed

    public init(appState: AppState, voiceService: VoiceServiceClient = VoiceServiceClient(), actorName: String = NSFullUserName()) {
        self.appState = appState
        self.voiceService = voiceService
        self.actorName = actorName
        super.init()
    }

    public func loadPersistedContext() async {
        if let saved = await appState.loadVoiceSessionContext() {
            context = saved
        }
        transcriptHistory = await appState.loadVoiceTranscript()
    }

    // MARK: - Conversation mode toggle

    /// One click starts an ongoing conversation; clicking again — whatever
    /// state it's in (listening, processing, speaking) — ends it. Mirrors
    /// `VoiceEngineContext.jsx`'s `toggleListening` exactly: that's the
    /// explicit "off" switch, so conversation mode never has to be guessed
    /// at from silence alone.
    public func toggleListening() {
        if conversationMode || isListening {
            conversationMode = false
            commandTask?.cancel()
            commandTask = nil
            stopListening(discard: true)
            cancelSpeech()
            isProcessing = false
        } else {
            // A quick retry can land while a command's spoken reply is
            // still being synthesized. Cancel that turn first so the
            // startListening guard below cannot silently discard the tap.
            if isProcessing || isSpeaking {
                commandTask?.cancel()
                commandTask = nil
                cancelSpeech()
                isProcessing = false
            }
            conversationMode = true
            Task { await startListening() }
        }
    }

    /// Tab: cut her off if she's talking (or thinking) and start listening
    /// right away; ignored while already listening. Unlike the mic toggle it
    /// never turns conversation mode off. Owner request 2026-10-01.
    public func interruptAndListen() {
        guard !isListening else { return }
        commandTask?.cancel()
        commandTask = nil
        cancelSpeech()
        isProcessing = false
        errorMessage = nil
        conversationMode = true
        Task { await startListening() }
    }

    @ObservationIgnored nonisolated(unsafe) private var tabMonitor: Any?

    /// Installs the Tab-key shortcut once. Tab still moves focus normally
    /// while the owner is typing in a text field or when any modifier is held.
    public func installTabShortcut() {
        guard tabMonitor == nil else { return }
        tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 48, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            MainActor.assumeIsolated { self?.interruptAndListen() }
            return nil
        }
    }

    /// A dedicated Stop control, distinct from the mic toggle above — real,
    /// live-tested gap (2026-08-29): saying "stop" out loud while she's
    /// speaking is never heard at all, because the mic isn't listening
    /// during playback (see this class's header doc comment on why true
    /// voice barge-in is deferred). This gives an immediate, reliable way
    /// to cut off speech from the status panel without also ending
    /// conversation mode the way the mic-toggle button does — a bookkeeper
    /// who wants to stop a reply short and then keep talking shouldn't
    /// have to restart the whole conversation.
    private func cancelSpeech() {
        speechGeneration += 1
        pendingSpeechTask?.cancel()
        pendingSpeechTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }

    public func stopSpeaking() {
        commandTask?.cancel()
        commandTask = nil
        cancelSpeech()
        isProcessing = false
        resumeListeningIfConversationMode()
    }

    /// Clears everything the floating status panel shows — real, live-
    /// tested gap (2026-08-29): `lastMessage`/`errorMessage` were only ever
    /// overwritten, never cleared, so the panel had no way to go away once
    /// something had been said. Does not touch `conversationMode`/
    /// `isListening` — dismissing the panel is a display action, not a
    /// "stop talking to me" action (that's `toggleListening`/`stopSpeaking`).
    public func dismissStatus() {
        lastMessage = nil
        errorMessage = nil
        transcript = ""
    }

    // MARK: - Recording

    private func startListening() async {
        guard conversationMode, !isListening, !isStartingListening, !isProcessing, !isSpeaking else { return }
        isStartingListening = true
        defer { isStartingListening = false }
        errorMessage = nil
        transcript = ""
        transcriptSource = ""

        let granted = await requestMicPermissionIfNeeded()
        guard granted else {
            micPermission = .denied
            errorMessage = "Microphone permission is required. Check System Settings → Privacy & Security → Microphone, then allow Voice Ledger."
            conversationMode = false
            return
        }
        micPermission = .granted
        guard conversationMode else { return }
        do {
            let mic = try AudioDeviceManager.applyPreferredInput()
            activeMicrophoneName = mic?.name ?? AudioDeviceManager.currentDefaultInput()?.name ?? "Unknown microphone"
        } catch {
            errorMessage = error.localizedDescription
            conversationMode = false
            return
        }
        // Give Core Audio a moment to switch before we read the input format.
        try? await Task.sleep(for: .milliseconds(150))

        guard conversationMode else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("voiceledger-recording-\(UUID().uuidString).wav")
        recordingURL = tempURL

        let inputNode = audioEngine.inputNode

        // Real, reported gap (2026-08-29): Bluetooth headphones don't
        // arrive at their microphone-capable format instantly. macOS keeps
        // a Bluetooth headset in its high-quality, playback-only mode
        // (A2DP) until something actually asks for its mic, at which point
        // it renegotiates to a lower-quality, bidirectional mode (HFP) —
        // a real profile switch that takes a moment. Reading
        // `outputFormat(forBus:)` the instant this method is called can
        // catch that transition mid-flight (0 channels/0 sample rate, or a
        // stale format from whatever device was active a moment ago),
        // which is the most likely cause of "it took forever" and "it
        // couldn't hear me over Bluetooth at all." Poll briefly for a
        // genuinely valid format instead of trusting the first read.
        var format = inputNode.outputFormat(forBus: 0)
        var waited: TimeInterval = 0
        let pollInterval: TimeInterval = 0.1
        let maxWait: TimeInterval = 2.0
        while (format.channelCount == 0 || format.sampleRate == 0), waited < maxWait {
            try? await Task.sleep(for: .seconds(pollInterval))
            waited += pollInterval
            format = inputNode.outputFormat(forBus: 0)
        }
        guard format.channelCount > 0, format.sampleRate > 0 else {
            errorMessage = "The microphone isn't ready yet — this can happen right after switching to Bluetooth headphones. Wait a moment and try again."
            conversationMode = false
            recordingURL = nil
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        do {
            audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        } catch {
            errorMessage = "Could not start recording: \(error)"
            conversationMode = false
            recordingURL = nil
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        guard conversationMode else { audioFile = nil; try? FileManager.default.removeItem(at: tempURL); return }
        recordingWriteFailed = false
        hasSpokenThisRecording = false
        endpointDetector = SpeechEndpointDetector()
        recordingStartedAt = Date()
        shouldAutoStop = false
        rawMicLevel = 0

        // FOURTH real, live-verified crash from this same callback
        // (2026-08-28/29) — even after the previous fix removed every
        // touch of MainActor-isolated storage, it crashed again with the
        // IDENTICAL signature (`dispatch_assert_queue_fail` inside
        // `swift_task_checkIsolatedSwift`), at a different byte offset
        // (proving it really was the new code, not a stale binary). Root
        // cause, actually correct this time: a closure LITERAL written
        // inside a `@MainActor` method is inferred `@MainActor`-isolated
        // by Swift BY DEFAULT, regardless of what it touches inside —
        // AVAudioEngine's `installTap` closure parameter isn't declared
        // `@Sendable` in this SDK, so nothing forced that inference off.
        // The isolation check Swift inserts at the closure's own entry
        // point (before any of the body runs) is what was failing —
        // matching every crash's near-identical low `symbolLocation`.
        // Explicitly typing this closure as `@Sendable` at its
        // declaration is what actually suppresses that inference; a
        // `@MainActor`-isolated class instance is itself Sendable (global
        // actor isolation implies Sendable), so capturing `self` here
        // remains legal — the closure body still reaches only
        // `nonisolated(unsafe)` storage, same as before.
        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            guard let self else { return }
            do { try self.audioFile?.write(from: buffer) }
            catch { self.recordingWriteFailed = true }
            let level = Self.rmsLevel(of: buffer)
            self.rawMicLevel = level
            self.evaluateSilenceOffMainActor(level: level)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: tapBlock)

        audioRouteDidChange = false
        // A route change mid-recording (Bluetooth headset connects,
        // disconnects, or renegotiates its profile) invalidates the tap's
        // format — the safe response is to stop cleanly and ask the user
        // to try again, not to keep recording against a format that no
        // longer matches the actual hardware. `queue: .main` means this
        // closure is dispatched via the main OperationQueue rather than
        // CoreAudio's realtime relay, so it only ever touches the plain
        // `nonisolated(unsafe)` flag below, never MainActor-isolated state
        // directly — same reasoning as the tap callback's own doc comment.
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            self?.audioRouteDidChange = true
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            startLevelMeterTimer()
        } catch {
            errorMessage = "Could not start the microphone: \(error)"
            inputNode.removeTap(onBus: 0)
            audioFile = nil
            recordingURL = nil
            try? FileManager.default.removeItem(at: tempURL)
            conversationMode = false
            if let observer = configurationChangeObserver {
                NotificationCenter.default.removeObserver(observer)
                configurationChangeObserver = nil
            }
        }
    }

    /// Runs on the audio tap's own realtime thread (see the crash-history
    /// doc comment above `rawMicLevel` etc.) — touches ONLY
    /// `nonisolated(unsafe)` storage, never anything MainActor-isolated.
    /// Doesn't stop listening directly; sets `shouldAutoStop` for the
    /// main-thread level-meter timer to notice and act on.
    nonisolated private func evaluateSilenceOffMainActor(level: Float) {
        guard let startedAt = recordingStartedAt else { return }
        shouldAutoStop = endpointDetector.update(level: level, elapsed: Date().timeIntervalSince(startedAt))
        hasSpokenThisRecording = endpointDetector.hasSpeech
    }

    /// A silent/empty recording is a normal occurrence in an ongoing
    /// conversation (a pause, ambient noise, a moment of thinking) — it
    /// auto-stops the SAME way regardless, and `handleRecordedAudio`
    /// reopens the mic afterward if still in conversation mode, mirroring
    /// `resumeListeningIfConversationMode` in the reference app.
    ///
    /// Fires on the MAIN run loop (added via `RunLoop.main.add(_:forMode:
    /// .common)` in `startLevelMeterTimer`) — a genuinely different
    /// execution context than the audio tap's realtime thread, and one
    /// Swift's MainActor runtime correctly recognizes, so touching
    /// `micLevel`/calling `stopListening()` here is safe.
    private func startLevelMeterTimer() {
        levelMeterTimer?.invalidate()
        // `Timer`'s block parameter is typed `@Sendable`, so the compiler
        // can't statically prove this closure runs on the MainActor the
        // way it can for a method written directly on this class — hence
        // the explicit `Task { @MainActor in }` hop. This is NOT the same
        // shape that crashed in the audio tap: that hop was created from
        // CoreAudio's `RealtimeMessenger` relay thread, which Swift's
        // concurrency runtime cannot identify; this one is created from a
        // callback that RunLoop.main is, by construction, already firing
        // on the real main thread, so entering @MainActor here is the
        // standard, safe pattern.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.micLevel = Double(self.rawMicLevel)
                if self.audioRouteDidChange {
                    self.audioRouteDidChange = false
                    self.errorMessage = "The audio device changed (e.g. Bluetooth headphones connecting or disconnecting) — stopped listening. Try again now that it's settled."
                    self.conversationMode = false
                    self.stopListening(discard: true)
                    Task { await self.recordTranscript(speaker: .assistant, text: "VOICE ERROR: \(self.errorMessage ?? "Audio device changed")") }
                } else if self.shouldAutoStop {
                    self.shouldAutoStop = false
                    self.stopListening()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelMeterTimer = timer
    }

    private func stopListening(discard: Bool = false) {
        guard isListening else { return }
        isListening = false
        micLevel = 0
        levelMeterTimer?.invalidate()
        levelMeterTimer = nil
        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationChangeObserver = nil
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil // closing the AVAudioFile flushes it to disk
        if !discard, let started = recordingStartedAt {
            NSLog("Voice timing: recording %.2fs, stop=%@", Date().timeIntervalSince(started), endpointDetector.stopReason ?? "manual")
        }

        guard let url = recordingURL else { return }
        recordingURL = nil
        guard !discard else { try? FileManager.default.removeItem(at: url); return }
        guard !recordingWriteFailed, hasSpokenThisRecording else {
            try? FileManager.default.removeItem(at: url)
            if recordingWriteFailed {
                conversationMode = false
                errorMessage = "Couldn't save microphone audio. Try starting the microphone again."
                let reason = errorMessage ?? "Couldn't save microphone audio."
                Task { await recordTranscript(speaker: .assistant, text: "VOICE ERROR: \(reason)") }
            } else if conversationMode {
                // A pause after a reply is normal in hands-free conversation.
                // Keep the session ready instead of presenting a mic failure
                // when the user simply hasn't started their next sentence.
                Task {
                    await recordTranscript(speaker: .assistant, text: "VOICE NOTE: No speech detected from \(activeMicrophoneName); conversation stayed ready for the next command.")
                    resumeListeningIfConversationMode()
                }
            } else {
                errorMessage = "No speech detected from \(activeMicrophoneName). Check its mute button and input gain, or choose another microphone in Audio Settings."
                let reason = errorMessage ?? "No speech detected."
                Task { await recordTranscript(speaker: .assistant, text: "VOICE ERROR: \(reason)") }
            }
            return
        }
        commandTask = Task { await handleRecordedAudio(at: url) }
    }

    private func requestMicPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    nonisolated private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        let samples = channelData[0]
        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = samples[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        return min(1, rms * 4)
    }

    // MARK: - Processing a recorded utterance

    private func resumeListeningIfConversationMode() {
        guard conversationMode else { return }
        Task {
            // Leave a short acoustic tail after the Mac finishes speaking so
            // the nearby microphone doesn't immediately capture its own reply.
            try? await Task.sleep(for: .milliseconds(800))
            if conversationMode { await startListening() }
        }
    }

    private func handleRecordedAudio(at url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        // A real recording, even a short one, is well more than a bare
        // WAV header (44 bytes) — anything tiny means nothing usable was
        // captured, the same floor voice-service's own /transcribe applies
        // server-side.
        guard let data = try? Data(contentsOf: url), data.count > 2000 else {
            errorMessage = "No audio was captured — check that the right microphone is selected as your input device."
            conversationMode = false
            await recordTranscript(speaker: .assistant, text: "VOICE ERROR: \(errorMessage!)")
            return
        }

        guard !Task.isCancelled else { return }
        isProcessing = true
        defer { if !Task.isCancelled { isProcessing = false } }
        do {
            let transcriptionStarted = Date()
            // On-device first; Whisper only as fallback.
            let text: String
            if let local = await OnDeviceTranscriber.transcribe(fileAt: url), !local.trimmingCharacters(in: .whitespaces).isEmpty {
                text = local
                transcriptSource = "on-device"
            } else {
                try Task.checkCancellation()
                text = try await voiceService.transcribe(audioData: data)
                transcriptSource = "whisper"
            }
            try Task.checkCancellation()
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                if conversationMode {
                    // Acoustic echo or a brief unclear sound can reach the
                    // recognizer after a successful command. That's not a
                    // failed command: preserve its response and keep the mic
                    // ready, while leaving a diagnostic note in Voice History.
                    transcript = ""
                    errorMessage = nil
                    await recordTranscript(speaker: .assistant, text: "VOICE NOTE: Audio arrived from \(activeMicrophoneName), but transcription returned no words; conversation stayed ready for another command.")
                    resumeListeningIfConversationMode()
                } else {
                    transcript = "(no words recognized)"
                    errorMessage = "Audio arrived from \(activeMicrophoneName), but no words were recognized. Check the mic's mute/gain and try again."
                    await recordTranscript(speaker: .assistant, text: "VOICE ERROR: \(errorMessage!)")
                }
                return
            }
            NSLog("Voice timing: transcription %.2fs, source=%@", Date().timeIntervalSince(transcriptionStarted), transcriptSource)
            transcript = text
            await recordTranscript(speaker: .user, text: text)
            await processCommand(text)
        } catch {
            guard !Task.isCancelled else { return }
            isProcessing = false
            conversationMode = false
            errorMessage = "Voice transcription failed: \(error). Check Audio Settings and that Voice Ledger Launcher is running."
            await recordTranscript(speaker: .assistant, text: "VOICE ERROR: \(errorMessage!)")
        }
    }

    /// Owner-facing (2026-09-06): "there should be a harness on the
    /// dashboard for me to ask questions and make commands just as
    /// powerful as by voice" — a typed fallback for when the microphone
    /// isn't available, reusing the EXACT same pipeline a spoken command
    /// goes through (router match → tool-calling fallback → apply UI
    /// action → speak the answer aloud too, same as a real voice turn)
    /// rather than a separate, weaker text-only path. The only thing
    /// skipped is speech-to-text itself — everything downstream of having
    /// real text is identical.
    public func handleTypedCommand(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        commandTask?.cancel()
        stopListening(discard: true)
        cancelSpeech()
        errorMessage = nil
        transcript = text
        transcriptSource = ""
        isProcessing = true
        let task = Task {
            await recordTranscript(speaker: .user, text: text)
            await processCommand(text)
            if !Task.isCancelled { isProcessing = false }
        }
        commandTask = task
        await task.value
    }

    private func processCommand(_ text: String) async {
        let commandStarted = Date()
        syncCurrentEntityWithScreen()
        let intent = VoiceIntentRouter.match(text: text, context: context)
        if case .chooseFinding = intent {} else { context.candidateFindingIDs = nil }
        let turn = await resolveTurn(for: intent, rawText: text)

        guard !Task.isCancelled else { return }
        lastMessage = turn.speech
        if let newPending = turn.newPendingAction {
            context.pendingAction = newPending
        }
        if let uiAction = turn.uiAction {
            apply(uiAction)
        }
        NSLog("Voice timing: command to screen %.2fs", Date().timeIntervalSince(commandStarted))
        await appState.saveVoiceSessionContext(context)
        let actionDescription: String
        if let uiAction = turn.uiAction { actionDescription = describe(uiAction) }
        else { actionDescription = "No screen action" }
        await recordTranscript(speaker: .assistant, text: "COMMAND RESULT\nHEARD: \(text)\nSOURCE: \(transcriptSource.isEmpty ? "typed" : transcriptSource)\nACTION: \(actionDescription) → \(appState.voiceLogLabel)\nRESPONSE: \(turn.speech)")
        guard !Task.isCancelled else { return }
        // Fresh data: the scope sentence stays on screen but isn't read aloud.
        var fresh = false
        if case .synced(let at) = appState.freshness, Date().timeIntervalSince(at) < 15 * 60 { fresh = true }
        await speak(VoiceSpeechFormatter.shortenForSpeech(turn.speech, dataIsFresh: fresh))
    }

    private func describe(_ action: VoiceUIAction) -> String {
        switch action {
        case .navigate(let destination): return "Opened \(destination.menuTitle)"
        case .showFindingGroup(let group): return "Opened \(group.rawValue) findings"
        case .openFinding: return "Opened finding detail"
        case .openFindings(let ids): return ids.count == 1 ? "Opened one finding" : "Opened \(ids.count) findings for comparison"
        case .goBack: return "Went back"
        case .goForward: return "Went forward"
        case .presentChart: return "Displayed chart"
        }
    }

    /// Appends to both the persisted store (survives an app restart) and
    /// the live `transcriptHistory` shown in `VoiceHistoryView` — the two
    /// stay in sync because this is the only place either is written to.
    func recordTranscript(speaker: VoiceTranscriptEntry.Speaker, text: String) async {
        guard !text.isEmpty else { return }
        let entry = VoiceTranscriptEntry(speaker: speaker, text: text)
        transcriptHistory.append(entry)
        await appState.appendVoiceTranscriptEntry(entry)
    }

    // MARK: - Speaking

    private func speak(_ text: String) async {
        guard !text.isEmpty else {
            resumeListeningIfConversationMode()
            return
        }
        isSpeaking = true
        pendingSpeechTask?.cancel()
        pendingSpeechTask = nil
        speechGeneration += 1
        let generation = speechGeneration
        // Speak the first sentence as soon as it's ready; synthesize the rest
        // while it plays (Part 2, Layer 0).
        let (first, rest) = Self.splitFirstSentence(text)
        do {
            let wav = try await voiceService.synthesize(text: VoiceSpeechFormatter.formatCurrency(first))
            guard !Task.isCancelled, generation == speechGeneration else { return }
            if let rest {
                pendingSpeechTask = Task { [voiceService] in
                    let data = try? await voiceService.synthesize(text: VoiceSpeechFormatter.formatCurrency(rest))
                    return Task.isCancelled ? nil : data
                }
            }
            try play(wav)
        } catch {
            guard !Task.isCancelled, generation == speechGeneration else { return }
            isSpeaking = false
            errorMessage = "I have a reply, but couldn't play the audio: \(error)"
            resumeListeningIfConversationMode()
        }
    }

    private func play(_ wav: Data) throws {
        let player = try AVAudioPlayer(data: wav)
        player.delegate = self
        audioPlayer = player
        guard player.play() else { throw CocoaError(.fileReadUnknown) }
    }

    static func splitFirstSentence(_ text: String) -> (String, String?) {
        guard text.count > 80, let range = text.range(of: #"(?<=[.!?])\s+"#, options: .regularExpression) else { return (text, nil) }
        let first = String(text[..<range.lowerBound])
        let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? (text, nil) : (first, rest)
    }

    // MARK: - UI actions

    /// `internal`, not `private` — `VoiceToolLoop.swift` applies the same
    /// UI actions a tool call resolves to, through this one chokepoint.
    func apply(_ action: VoiceUIAction) {
        switch action {
        case .navigate(let destination):
            appState.screen = Self.screen(for: destination)
        case .showFindingGroup(let group):
            appState.screen = .findingGroup(group)
        case .openFinding(let id):
            appState.screen = .detail(findingID: id)
        case .openFindings(let ids):
            // A single id degrades to the normal full-page detail view —
            // no reason to force a two-pane comparison sheet open for
            // what "pull up X" already handles well.
            if ids.count <= 1 {
                if let id = ids.first { appState.screen = .detail(findingID: id) }
            } else {
                appState.comparedFindingIDs = ids
            }
        case .goBack:
            appState.goBack()
        case .goForward:
            appState.goForward()
        case .presentChart(let request):
            appState.presentedChart = request
        }
    }

    /// `internal`, not `private` — `VoiceToolLoop.swift`'s `navigate` tool
    /// reuses this exact mapping so a tool-driven navigation can never
    /// silently diverge from what `VoiceIntentRouter`'s own matches do.
    static func screen(for destination: VoiceDestination) -> AppState.Screen {
        switch destination {
        case .dashboard: return .clientDashboard
        case .findingsList: return .list
        case .cleanupAssessment: return .cleanupAssessment
        case .balanceSheetIntegrity: return .balanceSheetIntegrity
        case .bankFeedCleanup: return .bankFeedCleanup
        case .chartOfAccountsCleanup: return .chartOfAccountsCleanup
        case .batchFixes: return .batchFixes
        case .salesTaxReview: return .salesTaxReview
        case .taxes: return .taxes
        case .firmCockpit: return .firmCockpit
        case .monthEndClose: return .monthEndClose
        case .activityLog: return .activityLog
        case .closePackage: return .closePackage
        case .clientMemory: return .clientMemory
        case .balanceSheetReport: return .balanceSheetReport
        case .profitAndLossReport: return .profitAndLossReport
        case .cashFlowReport: return .cashFlowReport
        case .trialBalanceReport: return .trialBalanceReport
        case .agedReceivablesReport: return .agedReceivablesReport
        case .agedPayablesReport: return .agedPayablesReport
        case .generalLedgerReport: return .generalLedgerReport
        case .cashFlowForecast: return .cashFlowForecast
        case .recurringVendors: return .recurringVendors
        case .amountSearch: return .amountSearch
        case .clientDiagnostics: return .diagnostics
        case .pricingCalculator: return .pricingCalculator
        case .intakeQuestions: return .intakeQuestions
        case .aiConversations: return .voiceHistory
        case .connection: return .connection
        case .scopeAndPeriodLock: return .scopeAndPeriodLock
        case .audioSettings: return .audioSettings
        }
    }

    /// "Hi"/"status update" — real, requested phrasing (2026-08-29): a
    /// greeting that gets a real answer instead of falling through to the
    /// reasoning path with nothing useful to say. Both numbers are already-
    /// computed `Finding` data (count, `dollarExposure` sum) — no AI call,
    /// no invented figure, same posture as everywhere else voice touches
    /// dollar amounts.
    private func statusOverview() -> VoiceTurn {
        let open = appState.findings.filter { $0.status == .open }
        guard !open.isEmpty else {
            return VoiceTurn(
                speech: "Connected to QuickBooks. No open findings right now — you're all caught up.",
                uiAction: .navigate(.firmCockpit)
            )
        }
        let currency = open[0].dollarExposure.currency
        let sameCurrency = open.allSatisfy { $0.dollarExposure.currency == currency }
        var exposureClause = ""
        if sameCurrency {
            let total = open.dropFirst().reduce(open[0].dollarExposure) { $0 + $1.dollarExposure }
            exposureClause = " totaling \(total.description) in exposure"
        }
        return VoiceTurn(
            speech: "Connected to QuickBooks. You have \(open.count) open finding\(open.count == 1 ? "" : "s")\(exposureClause). Ready when you are.",
            uiAction: .navigate(.firmCockpit)
        )
    }

    // MARK: - Intent -> Turn

    /// Builds a fresh review queue from `appState.findings` and opens the
    /// first item — shared by `.startReviewQueue` (the original "start
    /// review"/"show anomalies" phrasing) and `.recheckAnomalies` (re-sync
    /// first, then this). Pulled out so both stay byte-for-byte identical
    /// rather than drifting apart under separate maintenance.
    private func startReviewQueue() -> VoiceTurn {
        let queue = ReviewQueue.build(from: appState.findings)
        context.reviewQueue = queue
        context.reviewQueueIndex = queue.isEmpty ? nil : 0
        guard let firstID = queue.first, let finding = appState.finding(id: firstID) else {
            return VoiceTurn(speech: "There's nothing open to review right now.")
        }
        context = context.viewingEntity(VoiceEntityRef(type: .finding, id: finding.id, label: finding.title))
        return VoiceTurn(
            speech: "\(queue.count) item\(queue.count == 1 ? "" : "s") to review. Starting with \(finding.title).",
            uiAction: .openFinding(id: finding.id)
        )
    }

    private func resolveTurn(for intent: VoiceIntent, rawText: String) async -> VoiceTurn {
        switch intent {
        case .chooseFinding(let index):
            guard let ids = context.candidateFindingIDs, ids.indices.contains(index), let finding = appState.finding(id: ids[index]) else {
                return VoiceTurn(speech: "That selection is no longer available. Please search again.")
            }
            context.candidateFindingIDs = nil
            context = context.viewingEntity(VoiceEntityRef(type: .finding, id: finding.id, label: finding.title))
            return VoiceTurn(speech: "Opening \(ClientText.polish(finding.title)).", uiAction: .openFinding(id: finding.id))
        case .navigate(let destination):
            return VoiceTurn(speech: Self.speech(for: destination), uiAction: .navigate(destination))

        case .goBack:
            guard appState.canGoBack else { return VoiceTurn(speech: "There's no earlier page to go back to.") }
            return VoiceTurn(speech: "Going back.", uiAction: .goBack)

        case .goForward:
            guard appState.canGoForward else { return VoiceTurn(speech: "There's no page to go forward to.") }
            return VoiceTurn(speech: "Going forward.", uiAction: .goForward)

        case .findingsGroup(let group):
            return findingsGroupTurn(group)

        case .openFindingMatching(let amount, let text):
            return await openFindingMatchingTurn(amount: amount, text: text, rawText: rawText)

        case .accountBalance(let name):
            let fact = ClientFacts.accountBalance(appState.clientData, name: name)
            guard let account = fact.value else { return VoiceTurn(speech: fact.note ?? "I couldn't find that account.") }
            return VoiceTurn(speech: ClientText.polish("\(account.name) currently shows \(account.balance.accountingDescription). \(fact.note ?? "") \(fact.scope.sentence())"))

        case .searchAmount(let amount):
            let result = await execute(AIToolCall(id: "grammar", name: "search_transactions", arguments: ["query": .string(amount.accountingDescription)]))
            return VoiceTurn(speech: ClientText.polish(result.resultText), uiAction: result.uiAction)

        case .searchVendor(let name):
            let result = await execute(AIToolCall(id: "grammar", name: "get_vendor_details", arguments: ["vendor_name": .string(name)]))
            return VoiceTurn(speech: ClientText.polish(result.resultText), uiAction: result.uiAction)

        case .kpi(let metric, let period):
            let metricName = metric == .revenue ? "revenue" : metric == .netIncome ? "net_income" : "cash_balance"
            let result = await execute(AIToolCall(id: "grammar", name: "get_financial_summary", arguments: ["metric": .string(metricName), "period": .string(period.rawValue)]))
            return VoiceTurn(speech: ClientText.polish(result.resultText), uiAction: result.uiAction)

        case .freshness:
            return VoiceTurn(speech: ClientFacts.freshnessSentence(appState.clientData))

        case .vendorOwed(let name):
            if appState.agedPayablesLines.isEmpty { await appState.loadAgedPayables() }
            let fact = ClientFacts.amountOwed(appState.clientData, vendor: name)
            guard let owed = fact.value else { return VoiceTurn(speech: (fact.note ?? "I couldn't find that vendor.") + " " + fact.scope.sentence()) }
            var speech = "We owe \(owed.vendor) \(owed.total.accountingDescription)"
            if owed.overdue.minorUnits > 0 { speech += ": \(owed.current.accountingDescription) current and \(owed.overdue.accountingDescription) past due" }
            if owed.over90.minorUnits > 0 { speech += ", of which \(owed.over90.accountingDescription) is over 90 days" }
            return VoiceTurn(speech: ClientText.polish(speech + ". " + fact.scope.sentence()))

        case .totalOwed:
            if appState.agedPayablesLines.isEmpty { await appState.loadAgedPayables() }
            let data = appState.clientData
            guard let total = data.agedPayables.last(where: \.isSummary), let owed = total.total else {
                return VoiceTurn(speech: "The aged payables report isn't loaded yet. " + ClientFacts.freshnessSentence(data), uiAction: .navigate(.agedPayablesReport))
            }
            let split = AgingSplit(total)
            var speech = "We owe vendors \(owed.accountingDescription) in total"   // `owed` is the page's TOTAL (net of credits)
            if split.over60Owed.minorUnits > 0 { speech += ", \(split.over60Owed.accountingDescription) of it more than 60 days past due" }
            if split.credits.minorUnits < 0 { speech += ", less \(Money(minorUnits: -split.credits.minorUnits, currency: split.credits.currency).accountingDescription) in credits" }
            return VoiceTurn(speech: ClientText.polish(speech + "."), uiAction: .navigate(.agedPayablesReport))

        case .totalReceivable:
            if appState.agedReceivablesLines.isEmpty { await appState.loadAgedReceivables() }
            guard let total = appState.agedReceivablesLines.last(where: \.isSummary), total.total != nil else {
                return VoiceTurn(speech: "The aged receivables report isn't loaded yet. " + ClientFacts.freshnessSentence(appState.clientData), uiAction: .navigate(.agedReceivablesReport))
            }
            let split = AgingSplit(total)
            // The page's TOTAL is net of credits; say the gross, the credits, and the page's net so the
            // spoken numbers can always be matched to the screen.
            var speech: String
            if split.credits.minorUnits < 0 {
                let credits = Money(minorUnits: -split.credits.minorUnits, currency: split.credits.currency)
                speech = "Customers owe us \(split.owed.accountingDescription) before \(credits.accountingDescription) in credits, which is \(split.net.accountingDescription) net"
            } else {
                speech = "Customers owe us \(split.owed.accountingDescription)"
            }
            if split.over60Owed.minorUnits > 0 { speech += ". \(split.over60Owed.accountingDescription) of it is more than 60 days old" }
            return VoiceTurn(speech: ClientText.polish(speech + "."), uiAction: .navigate(.agedReceivablesReport))

        case .retry:
            dismissStatus()
            conversationMode = true
            return VoiceTurn(speech: "Go ahead.")

        case .chart(let kind):
            let result = await execute(AIToolCall(id: "grammar", name: "generate_chart", arguments: ["kind": .string(kind.rawValue)]))
            return VoiceTurn(speech: result.resultText, uiAction: result.uiAction)

        case .statusOverview:
            return statusOverview()

        case .startReviewQueue:
            return startReviewQueue()

        case .recheckAnomalies:
            // Real re-sync against QBO, same path the sidebar's own
            // refresh button already calls — not a new sync mechanism,
            // just voice parity for "check again"/"any new anomalies"
            // after a batch has already been cleared.
            await appState.syncAndEvaluate()
            let turn = startReviewQueue()
            if context.reviewQueue.isEmpty {
                return VoiceTurn(speech: "Rechecked — nothing open right now.")
            }
            return VoiceTurn(speech: "Rechecked. \(turn.speech)", uiAction: turn.uiAction)

        case .queueNext, .queueSkip:
            guard !context.reviewQueue.isEmpty else {
                return VoiceTurn(speech: "There's no review queue active. Say \"start review\" to begin one.")
            }
            let nextIndex = (context.reviewQueueIndex ?? -1) + 1
            guard nextIndex < context.reviewQueue.count else {
                context.reviewQueueIndex = nil
                return VoiceTurn(speech: "That's everything in the queue.")
            }
            context.reviewQueueIndex = nextIndex
            let findingID = context.reviewQueue[nextIndex]
            guard let finding = appState.finding(id: findingID) else {
                // The queue was built from a snapshot; a finding can
                // resolve/vanish between then and now. Skip forward rather
                // than getting stuck, same "don't guess, don't stall"
                // posture the rest of this app already has.
                context.reviewQueueIndex = nextIndex
                return VoiceTurn(speech: "That finding isn't open anymore. Say next to continue.")
            }
            context = context.viewingEntity(VoiceEntityRef(type: .finding, id: finding.id, label: finding.title))
            let remaining = context.reviewQueue.count - nextIndex - 1
            return VoiceTurn(
                speech: "\(finding.title). \(remaining) remaining after this.",
                uiAction: .openFinding(id: finding.id)
            )

        case .queueStatus:
            let total = context.reviewQueue.count
            let done = context.reviewQueueIndex ?? 0
            return VoiceTurn(speech: "\(done) of \(total) reviewed so far.")

        case .openLastEntity:
            guard let entity = context.lastViewedEntities.first else {
                return VoiceTurn(speech: "I don't have anything recent to open.")
            }
            return VoiceTurn(speech: entity.label.map { "Opening \($0)." } ?? "Opening it.", uiAction: .openFinding(id: entity.id))

        case .recapContext:
            if let entity = context.currentEntity {
                return VoiceTurn(speech: "We were looking at \(entity.label ?? "a finding").")
            }
            return VoiceTurn(speech: "We haven't looked at anything specific yet this session.")

        case .explainCurrent:
            return await explainCurrentEntity(rawText: rawText)

        case .confirmPending:
            return await resolvePendingAction(approved: true)

        case .rejectPending:
            return await resolvePendingAction(approved: false)

        case .unrecognized:
            // Owner directive (2026-09-06): "move away from phrase matching
            // and move to understand me no matter how I say it." Anything
            // `VoiceIntentRouter`'s exact-phrase matches didn't catch now
            // gets real tool-calling capability (navigate, open/compare
            // findings, financial lookups, charts, refresh, switch client)
            // instead of narration only — see `VoiceToolLoop`'s own doc
            // comment for why this is the same safety property through a
            // different, still-real mechanism.
            return await handleWithTools(rawText: rawText)
        }
    }

    /// "Pull up the duplicates": go to the page that owns the group and
    /// speak its count and total — the same numbers the page header shows.
    private func findingsGroupTurn(_ group: FactFindingGroup) -> VoiceTurn {
        let data = appState.clientData
        let list = ClientFacts.findings(data, category: group).value ?? []
        let total = ClientFacts.totalExposure(data, category: group).value
        let label = group.rawValue.replacingOccurrences(of: "_", with: " ")
        let noun = group == .duplicates ? "duplicate pair\(list.count == 1 ? "" : "s")" : "open"
        var speech = "\(label.prefix(1).uppercased() + label.dropFirst()): \(list.count) \(noun)"
        if let total, list.count > 0 { speech += ", \(total.accountingDescription) in total" }
        speech += "."
        if let top = list.first, list.count > 0 { speech += " Largest: \(ClientText.polish(top.title))." }
        return VoiceTurn(speech: speech, uiAction: .showFindingGroup(group))
    }

    /// Resolve "the $1,420 one" / "the Cool Cars payment" against open
    /// findings in code: exact amount first, then vendor, then title words.
    private func openFindingMatchingTurn(amount: Money?, text: String, rawText: String) async -> VoiceTurn {
        let open = FindingTriage.sorted(appState.findings.filter { $0.status == .open })
        var matches: [Finding] = []
        if let amount {
            matches = open.filter { abs($0.dollarExposure.minorUnits) == abs(amount.minorUnits) }
        }
        if matches.isEmpty {
            let words = text.split(separator: " ").map(String.init).filter { $0.count > 2 && !["the", "one", "finding", "issue", "item", "flag", "that", "this"].contains($0) }
            if !words.isEmpty {
                matches = open.filter { f in
                    let hay = ((f.vendorName ?? "") + " " + f.title).lowercased()
                    return words.allSatisfy { hay.contains($0) }
                }
            }
        }
        switch matches.count {
        case 1:
            let f = matches[0]
            context = context.viewingEntity(VoiceEntityRef(type: .finding, id: f.id, label: f.title))
            return VoiceTurn(speech: "Opening \(ClientText.polish(f.title)).", uiAction: .openFinding(id: f.id))
        case 2...4:
            context.candidateFindingIDs = matches.map(\.id)
            let list = matches.enumerated().map { "\($0.offset + 1): \(ClientText.polish($0.element.title))" }.joined(separator: "; ")
            return VoiceTurn(speech: "I found \(matches.count): \(list). Say first, second, or the finding's amount.", uiAction: .openFindings(ids: matches.map(\.id)))
        case 0 where amount != nil:
            let result = await execute(AIToolCall(id: "grammar", name: "search_transactions", arguments: ["query": .string(amount!.accountingDescription)]))
            return VoiceTurn(speech: "No open finding is \(amount!.accountingDescription). " + ClientText.polish(result.resultText), uiAction: result.uiAction)
        case 0:
            return await handleWithTools(rawText: rawText)
        default:
            return VoiceTurn(speech: "I found \(matches.count) matching findings — say an amount or a vendor name to narrow it down.")
        }
    }

    private static func speech(for destination: VoiceDestination) -> String { destination.menuTitle + "." }

    /// Prior turns of THIS voice conversation, for the AI reasoning path
    /// to replay — added 2026-08-29, after researching a different app's
    /// voice assistant that the owner said felt sharper: it replays its
    /// last several exchanges into every call, while this engine
    /// previously sent one isolated question with zero memory of what was
    /// just discussed (the likely cause of a follow-up feeling like it
    /// was "talking in circles"). `dropLast()` excludes the CURRENT
    /// user utterance — it's already recorded into `transcriptHistory`
    /// (via `recordTranscript` in `handleRecordedAudio`, before this is
    /// ever called) but is sent separately as the actual `question`, not
    /// as history. Capped at 12 turns here too — belt-and-suspenders with
    /// the backend's own `sanitizeHistory`, which enforces the real budget
    /// regardless of what this sends.
    /// `internal`, not `private` — `VoiceToolLoop.swift` reuses this for
    /// the same reason (conversation continuity across tool-calling turns,
    /// not just the reasoning fallback).
    func recentHistory(maxTurns: Int = 12) -> [AskAIHistoryTurn] {
        transcriptHistory.dropLast().suffix(maxTurns).map { entry in
            AskAIHistoryTurn(role: entry.speaker == .user ? "user" : "assistant", content: entry.text)
        }
    }

    /// "Why is this flagged" et al. — grounded ENTIRELY in the current
    /// finding's own already-computed fields via `AskAIContext.compose`,
    /// the exact same call `FindingDetailView`'s on-screen Ask AI panel
    /// makes. No new reasoning path, no new prompt.
    /// The screen is the source of truth for "this": a finding the user
    /// clicked open themselves must count, and one voice opened earlier
    /// must stop counting once they've navigated away.
    private func syncCurrentEntityWithScreen() {
        switch appState.screen {
        case .detail(let findingID), .procedure(let findingID, _):
            if context.currentEntity?.id != findingID, let finding = appState.finding(id: findingID) {
                context = context.viewingEntity(VoiceEntityRef(type: .finding, id: finding.id, label: finding.title))
            }
        default:
            context.currentEntity = nil
        }
    }

    private func explainCurrentEntity(rawText: String) async -> VoiceTurn {
        guard let entityRef = context.currentEntity, entityRef.type == .finding,
              let finding = appState.finding(id: entityRef.id) else {
            return await handleWithTools(rawText: rawText)
        }
        let contextText = AskAIContext.compose(finding: finding)
        // Asks for the reason AND a recommendation together (real,
        // live-tested gap 2026-08-29: "why" alone left no path to "so what
        // should I do") — explicitly grounded in the proposed
        // resolution(s) `AskAIContext.compose` already lists, never a new
        // fix invented on the spot (CLAUDE.md rule 1).
        await appState.askAI(
            contextKey: Self.reasoningContextKey,
            contextText: contextText,
            question: "In two or three short sentences I can read aloud: why is this flagged, and what would you recommend as the next step? Reference only the proposed resolution(s) already listed above — never invent a new fix.",
            history: recentHistory(),
            model: Self.voiceModel
        )
        // Real, requested fix (2026-08-29 — "the screen doesn't follow the
        // conversation"): every explain/fix-options answer re-syncs the
        // screen to the finding actually being discussed, whether the user
        // had navigated away or was already looking at it. Same
        // `.openFinding` action `.startReviewQueue`/`.queueNext` already
        // produce — not a new mechanism, and still only ever a navigation,
        // never a write.
        if let answer = appState.askAIAnswers[Self.reasoningContextKey] {
            return VoiceTurn(speech: answer, uiAction: .openFinding(id: finding.id))
        }
        return VoiceTurn(speech: "I couldn't get an explanation right now. \(finding.narrative ?? finding.title)", uiAction: .openFinding(id: finding.id))
    }

    /// Resolves `context.pendingAction` — the ONLY two kinds that can ever
    /// be pending are `dismissFinding`/`completeChecklistItem` (see
    /// `VoicePendingAction.Kind`'s doc comment), never a QBO write.
    private func resolvePendingAction(approved: Bool) async -> VoiceTurn {
        guard let pending = context.pendingAction else {
            return VoiceTurn(speech: "There's nothing waiting on a yes or no right now.")
        }
        context = context.clearingPendingAction()
        guard approved else {
            return VoiceTurn(speech: "Okay, I won't do that.")
        }
        switch pending.kind {
        case .dismissFinding:
            guard let findingID = pending.findingID else { return VoiceTurn(speech: "I lost track of which finding that was — say it again.") }
            await appState.dismissFinding(findingID: findingID, actorName: actorName, reason: "Dismissed by voice command")
            return VoiceTurn(speech: "Dismissed.")
        case .completeChecklistItem:
            guard let itemID = pending.checklistItemID else { return VoiceTurn(speech: "I lost track of which item that was — say it again.") }
            await appState.completeChecklistItem(ChecklistItemID(rawValue: itemID), actorName: actorName, note: "Marked complete by voice command")
            return VoiceTurn(speech: "Marked complete.")
        }
    }
}

extension VoiceEngine: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let current = self.audioPlayer, ObjectIdentifier(current) == playerID else { return }
            let generation = self.speechGeneration
            if let task = self.pendingSpeechTask {
                self.pendingSpeechTask = nil
                let next = await task.value
                guard generation == self.speechGeneration else { return }
                if let next, (try? self.play(next)) != nil { return }
                self.errorMessage = "The rest of the spoken reply couldn't be played. The full answer is shown on screen."
            }
            self.isSpeaking = false
            self.resumeListeningIfConversationMode()
        }
    }
}
