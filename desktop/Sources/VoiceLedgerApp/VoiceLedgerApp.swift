import SwiftUI
import AppKit
import Foundation
import Core
import IntegrationsQuickBooks
import DB
import DesignSystem
import VoiceLedgerUI

/// File > "Export Page as PDF…" (see the `.commands` block in
/// `VoiceLedgerApp.body` and `RootView.exportCurrentPageAsPDF`) — a plain
/// `NotificationCenter` post is the bridge from the menu command (which has
/// no reference to the live `RootView`/`AppState` instance) to the one view
/// that actually knows what's on screen right now.
extension Notification.Name {
    static let exportCurrentPageAsPDF = Notification.Name("VoiceLedgerExportCurrentPageAsPDF")
}

/// The real running app for Phase 1 step 1.6's slice. **Not visually
/// verified in this session** — no screenshot tool for a native macOS
/// window was available in this environment; see the final report for what
/// that means for confidence in this layer specifically (the logic
/// underneath, in Core, IS test-verified: 41/41 offline tests passing).
///
/// Usage:
///   VOICE_LEDGER_BACKEND_URL=https://your-backend.example.com \
///   VOICE_LEDGER_SESSION_TOKEN=<token> \
///   VOICE_LEDGER_REALM_ID=<sandbox realmId> \
///   swift run VoiceLedgerApp
@main
struct VoiceLedgerApp: App {
    /// Owner directive (2026-08-29): closing the app's one window (the red
    /// traffic-light button, or Cmd-W) left it with zero windows and no
    /// way back — neither the Dock icon nor `NSApp.activate` brought one
    /// back, confirmed live with a real Dock-icon click, not just
    /// `activate`. A plain `WindowGroup` with no app delegate is supposed
    /// to handle this itself, but doesn't here reliably; `AppDelegate`
    /// below hooks the real AppKit reopen callback and asks SwiftUI to
    /// open a fresh window explicitly rather than relying on that default.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var appState: AppState?
    @State private var configError: String?
    /// docs/VOICE_LEDGER_SPEC.md's Client Switcher — the one piece of
    /// configuration that stays constant across a switch (same backend,
    /// different realm/session). `nil` only before `configure()`'s first
    /// successful run.
    @State private var backendBaseURL: URL?

    var body: some Scene {
        WindowGroup("Voice Ledger", id: Self.mainWindowID) {
            Group {
                if let appState {
                    RootView(state: appState)
                } else if let configError {
                    ConfigErrorView(message: configError)
                } else {
                    ProgressView().onAppear { configure() }
                }
            }
            .frame(minWidth: 720, minHeight: 480)
            .onAppear {
                // Confirmed live 2026-08-28: a raw (unbundled) executable
                // launched via `nohup binary &` from a script — as the
                // desktop launcher does, since there is no Xcode-built .app
                // bundle for this SwiftPM executable — comes up with AppKit's
                // "background only" activation policy: alive as a process
                // (`ps`/`pgrep` see it), but no Dock icon and no visible
                // window, confirmed via `osascript`'s "background only of
                // process" reporting true. Running via `swift run`/Terminal
                // never hit this because Terminal-launched processes inherit
                // a foreground-capable session context an `open`-launched
                // script's child process does not. Forcing `.regular` here
                // makes the window appear regardless of how the binary was
                // started, since AppKit's default in that inherited context
                // otherwise silently stays background-only.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                // Hands the AppDelegate a real way to open a fresh window —
                // see `AppDelegate`'s own doc comment for why the default
                // reopen behavior wasn't enough on its own, confirmed via
                // an actual Dock-icon click leaving the app at zero windows.
                appDelegate.onReopenWithNoWindows = { openWindow(id: Self.mainWindowID) }
                // Developer test hook (2026-10-02): voiceledger-dev://ask?q=...&silent=1
                // runs a question through the same path as the typed command box.
                // Handled by the app delegate so SwiftUI never opens a new window
                // for it. Sandbox companies only; voice never writes to QuickBooks.
                appDelegate.onDevAsk = { q, silent in
                    guard let appState, appState.environment != .production else { return }
                    appState.voiceEngine.muteSpeech = silent
                    Task { await appState.voiceEngine.handleTypedCommand(q) }
                }
            }
        }
        .commands {
            // File > "Export Page as PDF…" — a `Commands` scene builder has
            // no reference to the specific `RootView` instance currently on
            // screen (there's no view-model handle to call through), so
            // this posts a notification and `RootView` itself does the
            // actual rendering — it's the one place that knows both `state
            // .screen` (which page) and the page's real current on-screen
            // size (see `RootView.exportCurrentPageAsPDF`).
            CommandGroup(after: .saveItem) {
                Button("Export Page as PDF…") {
                    NotificationCenter.default.post(name: .exportCurrentPageAsPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        // Owner-reported bug (2026-09-06): the finding-comparison popup
        // used to be a `.sheet`, which doesn't offer a resize grip on
        // macOS regardless of frame flexibility. A real `Window` scene
        // gets genuine user resizability and native traffic-light window
        // controls for free — `RootView` opens/closes it by id as
        // `AppState.comparedFindingIDs` transitions to/from empty (see its
        // `.onChange` there); this closure re-reads `appState` fresh every
        // time the window's content re-renders, so it always reflects
        // whichever `AppState` is current (client switches replace the
        // whole instance, same as the main window above).
        Window("Comparing Findings", id: Self.comparisonWindowID) {
            if let appState {
                FindingComparisonView(
                    findings: appState.comparedFindingIDs.compactMap { appState.finding(id: $0) },
                    onSelectFinding: { finding in
                        appState.comparedFindingIDs = []
                        appState.screen = .detail(findingID: finding.id)
                    },
                    onClose: { finding in
                        appState.comparedFindingIDs.removeAll { $0 == finding.id }
                    },
                    onCloseAll: { appState.comparedFindingIDs = [] },
                    analysisAnswer: appState.askAIAnswers[appState.comparisonContextKey(for: appState.comparedFindingIDs)],
                    isGeneratingAnalysis: appState.askingAIContextKeys.contains(appState.comparisonContextKey(for: appState.comparedFindingIDs)),
                    analysisError: appState.askAIError?.contextKey == appState.comparisonContextKey(for: appState.comparedFindingIDs) ? appState.askAIError?.message : nil,
                    onAnalyze: { Task { await appState.generateComparisonAnalysis() } },
                    onAskFollowUp: { question in Task { await appState.askComparisonFollowUp(question) } },
                    secondOpinionConfigured: appState.aiStatus?.secondaryConfigured ?? false,
                    analysisSecondOpinionAnswer: appState.secondOpinionAnswers[appState.comparisonContextKey(for: appState.comparedFindingIDs)],
                    isGeneratingAnalysisSecondOpinion: appState.askingSecondOpinionContextKeys.contains(appState.comparisonContextKey(for: appState.comparedFindingIDs)),
                    analysisSecondOpinionError: appState.secondOpinionError?.contextKey == appState.comparisonContextKey(for: appState.comparedFindingIDs) ? appState.secondOpinionError?.message : nil,
                    onAnalyzeSecondOpinion: { Task { await appState.generateComparisonAnalysisSecondOpinion() } },
                    onAskFollowUpSecondOpinion: { question in Task { await appState.askComparisonFollowUpSecondOpinion(question) } },
                    claudeConfigured: appState.aiStatus?.anthropicConfigured ?? false,
                    analysisClaudeAnswer: appState.askAIAnswers["\(appState.comparisonContextKey(for: appState.comparedFindingIDs))-claude"],
                    isGeneratingAnalysisClaude: appState.askingAIContextKeys.contains("\(appState.comparisonContextKey(for: appState.comparedFindingIDs))-claude"),
                    analysisClaudeError: appState.askAIError?.contextKey == "\(appState.comparisonContextKey(for: appState.comparedFindingIDs))-claude" ? appState.askAIError?.message : nil,
                    onAnalyzeClaude: { Task { await appState.generateComparisonAnalysisClaude() } },
                    onAskFollowUpClaude: { question in Task { await appState.askComparisonFollowUpClaude(question) } }
                )
                // A real window's own close control (red traffic light,
                // Cmd-W) bypasses `RootView`'s `.onChange` entirely — this
                // is what keeps `comparedFindingIDs` in sync when the
                // window is closed that way instead of via the in-view "X".
                .onDisappear { appState.comparedFindingIDs = [] }
                .environment(\.qboLinks, appState.qboLinks)
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 640)
    }

    private static let mainWindowID = "main"
    static let comparisonWindowID = "finding-comparison"

    private func configure() {
        do {
            let launchValues = Self.consumeLauncherConfiguration()
            var launchEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in launchValues { launchEnvironment[key] = value }
            let configuration = try BackendConfiguration.fromEnvironment(environment: launchEnvironment)
            guard let realmIDString = launchEnvironment["VOICE_LEDGER_REALM_ID"] else {
                configError = "VOICE_LEDGER_REALM_ID is not set."
                return
            }
            let realmID = RealmID(rawValue: realmIDString)

            // CLAUDE.md rule 7: sandbox vs. production must be visually
            // unmistakable. This app has no environment picker — the
            // environment comes from which backend/realm you pointed it at,
            // surfaced honestly rather than defaulted to sandbox. (Only for
            // THIS initial launch — a client switched-to later carries its
            // own real environment from the backend's connection registry,
            // see `performSwitch` below, never this env var.)
            let environmentString = launchEnvironment["VOICE_LEDGER_ENVIRONMENT"] ?? "sandbox"
            let environment: QBOEnvironment = environmentString == "production" ? .production : .sandbox

            backendBaseURL = configuration.baseURL
            appState = try buildAppState(realmID: realmID, environment: environment, sessionToken: configuration.sessionToken, backendBaseURL: configuration.baseURL)
        } catch {
            configError = "\(error)"
        }
    }

    /// LaunchServices on some macOS versions silently omits `open --env`
    /// values. The Launcher therefore writes a mode-0600 one-shot config;
    /// consume and remove it before constructing the backend client.
    private static func consumeLauncherConfiguration() -> [String: String] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/VoiceLedger/launch-config.json")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            recordLauncherConfigDiagnostic("present=false or invalid")
            return [:]
        }
        var environment: [String: String] = [:]
        if let value = values["backendURL"] { environment["VOICE_LEDGER_BACKEND_URL"] = value }
        if let value = values["sessionToken"] { environment["VOICE_LEDGER_SESSION_TOKEN"] = value }
        if let value = values["realmID"] { environment["VOICE_LEDGER_REALM_ID"] = value }
        if let value = values["environment"] { environment["VOICE_LEDGER_ENVIRONMENT"] = value }
        recordLauncherConfigDiagnostic("present=true fields=\(environment.keys.sorted().joined(separator: ","))")
        return environment
    }

    private static func recordLauncherConfigDiagnostic(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/VoiceLedger/launcher-config-diagnostic.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The one place an `AppState` is constructed — used for the initial
    /// launch AND every subsequent client switch, so the two paths can
    /// never quietly drift apart (a switch producing a subtly
    /// differently-configured `AppState` than a fresh launch would).
    private func buildAppState(realmID: RealmID, environment: QBOEnvironment, sessionToken: String?, backendBaseURL: URL) throws -> AppState {
        let configuration = BackendConfiguration(baseURL: backendBaseURL, sessionToken: sessionToken)
        let backend = BackendClient(configuration: configuration)
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "VoiceLedger", directoryHint: .isDirectory)
        let store = try ClientStore(realmID: realmID, rootDirectory: supportDir)
        let period = AccountingPeriod(year: 2026, month: 7)
        let newState = AppState(realmID: realmID, environment: environment, period: period, backend: backend, store: store, clientStoreRootDirectory: supportDir)
        newState.onSwitchToClient = { [weak newState] targetRealmID, targetEnvironment in
            await performSwitch(to: targetRealmID, environment: targetEnvironment, requestingFrom: newState)
        }
        newState.onDisconnectClient = { [weak newState] in
            await performDisconnect(requestingFrom: newState)
        }
        return newState
    }

    /// docs/VOICE_LEDGER_SPEC.md's Client Switcher. `requestingFrom` is
    /// whichever `AppState` the user actually clicked "switch" on —
    /// always the currently-displayed one in practice, but captured
    /// explicitly at the moment the switch started (never re-read from
    /// `self.appState`), so a failure reports back onto the exact
    /// instance that initiated it even if something else changed
    /// `self.appState` in the meantime.
    private func performSwitch(to targetRealmID: RealmID, environment targetEnvironment: QBOEnvironment, requestingFrom current: AppState?) async {
        guard let current, let backendBaseURL else { return }
        do {
            let newToken = try await current.requestSwitchSessionToken(forRealmID: targetRealmID)
            let newState = try buildAppState(realmID: targetRealmID, environment: targetEnvironment, sessionToken: newToken, backendBaseURL: backendBaseURL)
            appState = newState
        } catch {
            current.failClientSwitch("\(error)")
        }
    }

    /// Disconnecting deletes the active realm's backend sessions, so a
    /// session for the client to land on next must be minted FIRST.
    private func performDisconnect(requestingFrom current: AppState?) async {
        guard let current, let backendBaseURL else { return }
        let realmID = current.realmID
        let companyName = current.companyInfo?.companyName ?? realmID.rawValue
        do {
            let next = try await current.connectedClients().first { $0.realmID != realmID }
            var nextToken: String?
            if let next { nextToken = try await current.requestSwitchSessionToken(forRealmID: next.realmID) }
            let result = try await current.revokeConnection()

            if let next, let nextToken {
                appState = try buildAppState(realmID: next.realmID, environment: next.environment, sessionToken: nextToken, backendBaseURL: backendBaseURL)
            } else {
                appState = nil
                configError = "\(companyName) was disconnected and it was your last connected client. Connect a QuickBooks company through Intuit to continue."
            }

            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "VoiceLedger", directoryHint: .isDirectory)
            let localDataRemoved = (try? FileManager.default.removeItem(at: supportDir.appending(path: realmID.rawValue, directoryHint: .isDirectory))) != nil

            let alert = NSAlert()
            alert.messageText = "\(companyName) disconnected"
            var lines = [result.revokedAtIntuit
                ? "Intuit confirmed Voice Ledger's access was revoked."
                : "Voice Ledger deleted its tokens, but Intuit did not confirm the revoke. To be sure, also remove Voice Ledger in QuickBooks under Settings > Apps."]
            lines.append(localDataRemoved ? "This client's local Voice Ledger data was deleted." : "This client's local data folder could not be deleted; it is at Application Support/VoiceLedger/\(realmID.rawValue).")
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.alertStyle = result.revokedAtIntuit && localDataRemoved ? .informational : .warning
            alert.runModal()
        } catch {
            current.failDisconnect("Disconnect failed — nothing was removed. \(error)")
        }
    }
}

/// Owner directive (2026-08-29): "make sure everything works soundly" —
/// closing this app's one window (traffic-light close button, or Cmd-W)
/// left the app running with zero windows and no way to get one back.
/// Confirmed live: neither `NSApp.activate` nor a real Dock-icon click
/// brought a window back on their own, even though a plain `WindowGroup`
/// with no custom delegate is supposed to handle exactly this case by
/// default. `onReopenWithNoWindows` is set once, right after launch
/// (`VoiceLedgerApp.body`'s `.onAppear`), to call SwiftUI's own
/// `openWindow(id:)` — asking explicitly rather than continuing to rely on
/// a default that demonstrably wasn't firing here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopenWithNoWindows: (() -> Void)?
    var onDevAsk: ((String, Bool) -> Void)?

    // The dev test link is caught as a raw Apple Event, before SwiftUI sees it.
    // Verified 2026-10-02: left to SwiftUI, every link opened another window
    // (a hidden tab, or the Comparing Findings window when the main one refused).
    private func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s),
              url.scheme == "voiceledger-dev", url.host == "ask",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let q = items.first(where: { $0.name == "q" })?.value, !q.isEmpty else { return }
        onDevAsk?(q, items.contains { $0.name == "silent" && $0.value == "1" })
    }
    /// Defensive guard, live-verified 2026-08-29: without this, a reopen
    /// callback that fires before launch has actually settled could open a
    /// window before `WindowGroup`'s own initial one is up, risking a
    /// duplicate. Debug logging confirmed `applicationShouldHandleReopen`
    /// does NOT fire during a normal cold launch in practice — only after a
    /// real post-launch "closed to zero windows, then Dock-clicked" case —
    /// but gating on `didFinishLaunching` costs nothing and removes the
    /// possibility outright rather than relying on that being permanent.
    private var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        // One window, no tab bar: duplicates must never hide as tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        // After launch, so it replaces SwiftUI's own handler rather than being replaced by it.
        installURLHandler()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Live-verified 2026-08-29: returning `true` unconditionally made
        // AppKit ALSO perform its own default reopen behavior on top of the
        // window `onReopenWithNoWindows` just opened, producing two windows
        // titled "Voice Ledger" from a single Dock-icon click. Returning
        // `false` here tells AppKit "already handled it, don't also do your
        // own thing" — only the `flag == true` case (windows already
        // visible) should fall through to AppKit's normal behavior.
        if didFinishLaunching && !flag {
            onReopenWithNoWindows?()
            return false
        }
        return true
    }
}

private struct ConfigErrorView: View {
    let message: String
    @State private var recoveryError: String?
    var body: some View {
        VStack(spacing: VLSpacing.md) {
            Text("Open Voice Ledger with its Launcher")
                .font(VLTypography.pageTitle())
            Text("The Launcher starts the local services and supplies your client session. Reopening the app directly after a crash can lose that session.")
                .font(VLTypography.body())
            Text(recoveryError ?? message)
                .font(VLTypography.caption())
                .foregroundStyle(VLColor.textMuted)
            if let path = Bundle.main.object(forInfoDictionaryKey: "VoiceLedgerLauncherPath") as? String {
                Button("Restart with Launcher") {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = [path]
                    var environment = ProcessInfo.processInfo.environment
                    environment["VOICE_LEDGER_RELAUNCH_PID"] = String(ProcessInfo.processInfo.processIdentifier)
                    process.environment = environment
                    do {
                        try process.run()
                        NSApplication.shared.terminate(nil)
                    } catch { recoveryError = "Couldn't open Launcher: \(error.localizedDescription)" }
                }
            }
        }
        .padding(VLSpacing.pageGutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VLColor.background)
    }
}
