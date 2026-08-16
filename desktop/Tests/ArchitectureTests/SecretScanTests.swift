import Testing
import Foundation
import IntegrationsQuickBooks

/// The "no secret in the client bundle" half of Phase 1 step 1.2's exit gate
/// (docs/phase-0/00_OVERVIEW.md Build Order; docs/phase-0/03_SECURITY_THREAT_MODEL.md
/// §3.3). A policy that isn't checked by CI is a policy that erodes.
@Test("No secret-shaped literal exists anywhere in Sources/")
func noSecretsInSources() throws {
    let scriptPath = try locateScript(named: "check-no-secrets.sh")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["bash", scriptPath]

    let stderrPipe = Pipe()
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

    #expect(
        process.terminationStatus == 0,
        "Possible secret found in desktop source:\n\(stderrText)"
    )
}

/// docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3: BackendConfiguration must
/// only ever be constructed from the environment, never from a literal —
/// this is the type-level companion to the source scan above. An empty
/// environment must fail to produce a configuration; a working fallback
/// baked into the type would be exactly the leak this test exists to catch.
@Test("An empty environment fails to produce a BackendConfiguration")
func backendConfigurationRequiresEnvironment() {
    #expect(throws: BackendConfigurationError.self) {
        try BackendConfiguration.fromEnvironment(environment: [:])
    }
}

@Test("A valid VOICE_LEDGER_BACKEND_URL produces a usable configuration")
func backendConfigurationFromValidEnvironment() throws {
    let config = try BackendConfiguration.fromEnvironment(environment: [
        "VOICE_LEDGER_BACKEND_URL": "https://example.onrender.com",
        "VOICE_LEDGER_SESSION_TOKEN": "test-token"
    ])
    #expect(config.baseURL.absoluteString == "https://example.onrender.com")
    #expect(config.sessionToken == "test-token")
}
