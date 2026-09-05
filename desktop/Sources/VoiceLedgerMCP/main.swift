import Foundation
import Core
import IntegrationsQuickBooks
import DB

// A real Model Context Protocol server — stdio transport: one JSON-RPC 2.0
// message per line, UTF-8, no embedded newlines, no Content-Length framing
// (see MCPDispatcher.swift for the exact methods handled, VoiceLedgerTools
// .swift for the two v1 tools). Read-only: this process can tell an MCP
// client what Voice Ledger already found, never change anything in QBO —
// see VoiceLedgerTools's own doc comment for why that's structural, not a
// runtime check.
//
// Usage:
//   VOICE_LEDGER_REALM_ID=<realmId> \
//   VOICE_LEDGER_ENVIRONMENT=sandbox \
//   VOICE_LEDGER_BACKEND_URL=https://your-backend.example.com \
//   VOICE_LEDGER_SESSION_TOKEN=<token> \
//   swift run voiceledger-mcp
//
// VOICE_LEDGER_BACKEND_URL/VOICE_LEDGER_SESSION_TOKEN are optional —
// get_open_findings needs neither (it only reads this realm's local
// ClientStore); get_client_status degrades to local-only data without them.
//
// Register with Claude Code: claude mcp add voiceledger --env
//   VOICE_LEDGER_REALM_ID=<realmId> -- swift run --package-path
//   <path-to-desktop> voiceledger-mcp
//
// CRITICAL: stdout carries ONLY JSON-RPC response lines. Every diagnostic
// message in this file goes to stderr instead — a stray write to stdout
// would corrupt the protocol stream for whatever client is reading it.

func logToStderr(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

guard let realmIDString = ProcessInfo.processInfo.environment["VOICE_LEDGER_REALM_ID"] else {
    logToStderr("voiceledger-mcp: VOICE_LEDGER_REALM_ID is not set.")
    exit(2)
}
let realmID = RealmID(rawValue: realmIDString)

// Same env var name and same sandbox default VoiceLedgerApp.swift's own
// `configure()` uses (CLAUDE.md rule 7) — never silently defaults a real
// production client's data to being reported under a sandbox label.
let environmentString = ProcessInfo.processInfo.environment["VOICE_LEDGER_ENVIRONMENT"] ?? "sandbox"
let qboEnvironment: QBOEnvironment = environmentString == "production" ? .production : .sandbox

// The exact Application Support path VoiceLedgerApp.swift's own
// `buildAppState` computes — this process reads the SAME on-disk realm
// data the real desktop app writes, never a separate copy (Package.swift's
// doc comment on this target explains why that matters).
let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "VoiceLedger", directoryHint: .isDirectory)

let store: ClientStore
do {
    store = try ClientStore(realmID: realmID, rootDirectory: supportDir)
} catch {
    logToStderr("voiceledger-mcp: failed to open ClientStore for realm \(realmID.rawValue): \(error)")
    exit(2)
}

// Optional — see this file's own usage comment above.
let backendConfiguration = try? BackendConfiguration.fromEnvironment()
let tools = VoiceLedgerTools(realmID: realmID, environment: qboEnvironment, store: store, backendConfiguration: backendConfiguration)

logToStderr("voiceledger-mcp: ready — realm \(realmID.rawValue), environment \(qboEnvironment.rawValue), backend \(backendConfiguration == nil ? "not configured" : "configured")")

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { continue }
    guard let data = trimmed.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        logToStderr("voiceledger-mcp: skipping unparsable line")
        continue
    }
    guard let response = await MCPDispatcher.handle(request: request, tools: tools) else {
        continue // a notification — JSON-RPC forbids responding to these
    }
    guard let responseData = try? JSONSerialization.data(withJSONObject: response) else {
        logToStderr("voiceledger-mcp: failed to serialize a response for method \(request["method"] ?? "?")")
        continue
    }
    FileHandle.standardOutput.write(responseData)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}
logToStderr("voiceledger-mcp: stdin closed, exiting")
