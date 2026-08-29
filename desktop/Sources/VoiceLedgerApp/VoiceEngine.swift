import Foundation
import AVFoundation
import Observation
import Core
import Voice
import IntegrationsVoice

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

    private unowned let appState: AppState
    private let voiceService: VoiceServiceClient
    private let actorName: String
    private var context: VoiceSessionContext = .empty

    private let audioEngine = AVAudioEngine()
    private var recordingURL: URL?
    private var audioPlayer: AVAudioPlayer?
    private var levelMeterTimer: Timer?

    // Silence-detection thresholds — ported directly from
    // VoiceEngineContext.jsx's SPEAK_THRESHOLD/SILENCE_MS/MAX_RECORDING_MS.
    // Plain `let` (no isolation annotation needed): immutable Sendable
    // values are always safe to read from any thread, including the audio
    // tap's realtime thread where `evaluateSilenceOffMainActor` reads them.
    private let speakThreshold: Float = 0.06
    private let silenceSeconds: TimeInterval = 1.4
    private let maxRecordingSeconds: TimeInterval = 20

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
    @ObservationIgnored nonisolated(unsafe) private var silenceStartedAt: Date?
    @ObservationIgnored nonisolated(unsafe) private var recordingStartedAt: Date?
    @ObservationIgnored nonisolated(unsafe) private var rawMicLevel: Float = 0
    @ObservationIgnored nonisolated(unsafe) private var shouldAutoStop = false

    /// Fixed key for the reasoning fallback's Ask AI answer slot — every
    /// open-ended voice question shares one slot (each new question
    /// overwrites the last), distinct from `FindingDetailView`'s
    /// per-finding keys and `CleanupAssessmentView`'s page key.
    private static let reasoningContextKey = "voice-reasoning"

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
            stopListening()
            audioPlayer?.stop()
            isSpeaking = false
        } else {
            conversationMode = true
            Task { await startListening() }
        }
    }

    // MARK: - Recording

    private func startListening() async {
        guard !isListening else { return }
        errorMessage = nil
        transcript = ""

        let granted = await requestMicPermissionIfNeeded()
        guard granted else {
            micPermission = .denied
            errorMessage = "Microphone permission is required. Check System Settings → Privacy & Security → Microphone, then allow Voice Ledger."
            conversationMode = false
            return
        }
        micPermission = .granted

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("voiceledger-recording-\(UUID().uuidString).wav")
        recordingURL = tempURL

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        do {
            audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        } catch {
            errorMessage = "Could not start recording: \(error)"
            conversationMode = false
            return
        }

        hasSpokenThisRecording = false
        silenceStartedAt = nil
        recordingStartedAt = Date()
        shouldAutoStop = false
        rawMicLevel = 0

        // See the doc comment on the `nonisolated(unsafe)` properties above
        // for the crash history this specific shape fixes: the callback
        // below touches NOTHING isolated to this @MainActor class — no
        // stored property that isn't `nonisolated(unsafe)`, no Task, no
        // DispatchQueue-to-MainActor hop, no `MainActor.assumeIsolated`.
        // `self` is captured only to reach that plain storage.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            let level = Self.rmsLevel(of: buffer)
            self.rawMicLevel = level
            self.evaluateSilenceOffMainActor(level: level)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            startLevelMeterTimer()
        } catch {
            errorMessage = "Could not start the microphone: \(error)"
            inputNode.removeTap(onBus: 0)
            conversationMode = false
        }
    }

    /// Runs on the audio tap's own realtime thread (see the crash-history
    /// doc comment above `rawMicLevel` etc.) — touches ONLY
    /// `nonisolated(unsafe)` storage, never anything MainActor-isolated.
    /// Doesn't stop listening directly; sets `shouldAutoStop` for the
    /// main-thread level-meter timer to notice and act on.
    nonisolated private func evaluateSilenceOffMainActor(level: Float) {
        let now = Date()
        if level > speakThreshold {
            hasSpokenThisRecording = true
            silenceStartedAt = nil
        } else if hasSpokenThisRecording {
            if silenceStartedAt == nil {
                silenceStartedAt = now
            } else if let startedAt = silenceStartedAt, now.timeIntervalSince(startedAt) > silenceSeconds {
                shouldAutoStop = true
                return
            }
        }
        if let startedAt = recordingStartedAt, now.timeIntervalSince(startedAt) > maxRecordingSeconds {
            shouldAutoStop = true
        }
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
                if self.shouldAutoStop {
                    self.shouldAutoStop = false
                    self.stopListening()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelMeterTimer = timer
    }

    private func stopListening() {
        guard isListening else { return }
        isListening = false
        micLevel = 0
        levelMeterTimer?.invalidate()
        levelMeterTimer = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil // closing the AVAudioFile flushes it to disk

        guard let url = recordingURL else { return }
        recordingURL = nil
        Task { await handleRecordedAudio(at: url) }
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
            try? await Task.sleep(for: .milliseconds(400))
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
            resumeListeningIfConversationMode()
            return
        }

        isProcessing = true
        do {
            let text = try await voiceService.transcribe(audioData: data)
            isProcessing = false
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                transcript = "(heard nothing)"
                resumeListeningIfConversationMode()
                return
            }
            transcript = text
            await processCommand(text)
        } catch {
            isProcessing = false
            errorMessage = "Voice error: \(error)"
            resumeListeningIfConversationMode()
        }
    }

    private func processCommand(_ text: String) async {
        let intent = VoiceIntentRouter.match(text: text, context: context)
        let turn = await resolveTurn(for: intent, rawText: text)

        lastMessage = turn.speech
        if let newPending = turn.newPendingAction {
            context.pendingAction = newPending
        }
        if let uiAction = turn.uiAction {
            apply(uiAction)
        }
        await appState.saveVoiceSessionContext(context)
        await speak(turn.speech)
    }

    // MARK: - Speaking

    private func speak(_ text: String) async {
        guard !text.isEmpty else {
            resumeListeningIfConversationMode()
            return
        }
        isSpeaking = true
        do {
            let wav = try await voiceService.synthesize(text: text)
            let player = try AVAudioPlayer(data: wav)
            player.delegate = self
            audioPlayer = player
            player.play()
        } catch {
            isSpeaking = false
            errorMessage = "I have a reply, but couldn't play the audio: \(error)"
            resumeListeningIfConversationMode()
        }
    }

    // MARK: - UI actions

    private func apply(_ action: VoiceUIAction) {
        switch action {
        case .navigate(let destination):
            appState.screen = Self.screen(for: destination)
        case .openFinding(let id):
            appState.screen = .detail(findingID: id)
        case .goBack:
            // No navigation stack exists in AppState yet — the safest
            // universal "back" is the findings list, the same landing
            // screen every other "go back" affordance in this app uses.
            appState.screen = .list
        }
    }

    private static func screen(for destination: VoiceDestination) -> AppState.Screen {
        switch destination {
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
        }
    }

    // MARK: - Intent -> Turn

    private func resolveTurn(for intent: VoiceIntent, rawText: String) async -> VoiceTurn {
        switch intent {
        case .navigate(let destination):
            return VoiceTurn(speech: Self.speech(for: destination), uiAction: .navigate(destination))

        case .goBack:
            return VoiceTurn(speech: "Going back.", uiAction: .goBack)

        case .startReviewQueue:
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
            return await explainCurrentEntity()

        case .confirmPending:
            return await resolvePendingAction(approved: true)

        case .rejectPending:
            return await resolvePendingAction(approved: false)

        case .unrecognized:
            return await reasoningFallback(rawText: rawText)
        }
    }

    private static func speech(for destination: VoiceDestination) -> String {
        switch destination {
        case .findingsList: return "Findings."
        case .cleanupAssessment: return "Cleanup Assessment."
        case .balanceSheetIntegrity: return "Balance Sheet Integrity."
        case .bankFeedCleanup: return "Bank Feed Cleanup."
        case .chartOfAccountsCleanup: return "Chart of Accounts Cleanup."
        case .batchFixes: return "Batch Fixes."
        case .salesTaxReview: return "Sales Tax Review."
        case .taxes: return "Taxes."
        case .firmCockpit: return "Firm Cockpit."
        case .monthEndClose: return "Month-End Close."
        case .activityLog: return "Activity Log."
        case .closePackage: return "Close Package."
        case .clientMemory: return "Client Memory."
        case .balanceSheetReport: return "Balance Sheet."
        case .profitAndLossReport: return "Profit and Loss."
        case .cashFlowReport: return "Cash Flow."
        case .trialBalanceReport: return "Trial Balance."
        case .agedReceivablesReport: return "Aged Receivables."
        case .agedPayablesReport: return "Aged Payables."
        case .generalLedgerReport: return "General Ledger."
        }
    }

    /// "Why is this flagged" et al. — grounded ENTIRELY in the current
    /// finding's own already-computed fields via `AskAIContext.compose`,
    /// the exact same call `FindingDetailView`'s on-screen Ask AI panel
    /// makes. No new reasoning path, no new prompt.
    private func explainCurrentEntity() async -> VoiceTurn {
        guard let entityRef = context.currentEntity, entityRef.type == .finding,
              let finding = appState.finding(id: entityRef.id) else {
            return VoiceTurn(speech: "I don't have a specific finding open right now. Open one first, or ask me to start a review.")
        }
        let contextText = AskAIContext.compose(finding: finding)
        await appState.askAI(contextKey: Self.reasoningContextKey, contextText: contextText, question: "Why is this flagged, in one or two short sentences I can read aloud?")
        if let answer = appState.askAIAnswers[Self.reasoningContextKey] {
            return VoiceTurn(speech: answer)
        }
        return VoiceTurn(speech: "I couldn't get an explanation right now. \(finding.narrative ?? finding.title)")
    }

    /// Open-ended questions the router didn't match — grounded in whatever
    /// entity is currently active, same `AskAIContext` boundary as above,
    /// never a general free-form chat with no real data behind it.
    private func reasoningFallback(rawText: String) async -> VoiceTurn {
        let contextText: String
        if let entityRef = context.currentEntity, entityRef.type == .finding, let finding = appState.finding(id: entityRef.id) {
            contextText = AskAIContext.compose(finding: finding)
        } else {
            let openFindings = appState.findings.filter { $0.status == .open }
            contextText = AskAIContext.compose(pageTitle: "Voice Ledger", findings: openFindings)
        }
        await appState.askAI(contextKey: Self.reasoningContextKey, contextText: contextText, question: rawText)
        if let answer = appState.askAIAnswers[Self.reasoningContextKey] {
            return VoiceTurn(speech: answer)
        }
        if let aiStatus = appState.aiStatus, !aiStatus.configured {
            return VoiceTurn(speech: "AI isn't configured on this backend yet, so I can't answer that kind of question — but I can navigate, open findings, and walk you through a review queue.")
        }
        return VoiceTurn(speech: "I didn't catch a command in that, and I couldn't get an answer either. Try asking again, or say a page name to navigate.")
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.resumeListeningIfConversationMode()
        }
    }
}
