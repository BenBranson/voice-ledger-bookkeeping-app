import Foundation
import Core
import IntegrationsQuickBooks

// Verifies Phase 1 step 1.2's exit gate: "health check green from the
// desktop; no secret in the client bundle." This is deliberately NOT the
// Connection Page (docs/VOICE_LEDGER_SPEC.md) — that's step 1.3, not yet
// approved. It's the smallest thing on the desktop that can prove the gate.
//
// Usage:
//   VOICE_LEDGER_BACKEND_URL=https://your-backend.example.com \
//   VOICE_LEDGER_SESSION_TOKEN=<token from /oauth/callback> \
//   VOICE_LEDGER_REALM_ID=<sandbox realmId> \
//   swift run voiceledger-devtool health
//
// Exit codes: 0 = green, 1 = yellow/gray, 2 = red or error. Chosen so this
// is usable as a scripted gate check, not just a human-readable print.

let arguments = CommandLine.arguments
guard arguments.count >= 2, arguments[1] == "health" else {
    print("""
    voiceledger-devtool — Phase 1 gate-verification CLI, not the app.

    Commands:
      health    Run the live health check against a connected realm.

    Required environment variables:
      VOICE_LEDGER_BACKEND_URL     e.g. https://your-backend.onrender.com
      VOICE_LEDGER_SESSION_TOKEN   from the backend's /oauth/callback response
      VOICE_LEDGER_REALM_ID        the sandbox company's realmId
    """)
    exit(64) // EX_USAGE
}

guard let realmIDString = ProcessInfo.processInfo.environment["VOICE_LEDGER_REALM_ID"] else {
    FileHandle.standardError.write("VOICE_LEDGER_REALM_ID is not set.\n".data(using: .utf8)!)
    exit(2)
}

do {
    let configuration = try BackendConfiguration.fromEnvironment()
    let client = BackendClient(configuration: configuration)
    let result = try await client.healthCheck(realmID: RealmID(rawValue: realmIDString))

    print("realmId:    \(result.realmID)")
    print("status:     \(result.status.rawValue)")
    print("checkedAt:  \(result.checkedAt)")
    print("latencyMs:  \(result.latencyMs)")
    if let detail = result.detail {
        print("detail:     \(detail)")
    }

    switch result.status {
    case .green:
        exit(0)
    case .yellow, .gray:
        exit(1)
    case .red:
        exit(2)
    }
} catch {
    FileHandle.standardError.write("Health check failed: \(error)\n".data(using: .utf8)!)
    exit(2)
}
