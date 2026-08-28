import Testing
import Foundation
import Core
@testable import IntegrationsQuickBooks

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit — `BackendClient.normalize`
/// against the real shape `GET /connections` returns
/// (backend/src/routes/connections.ts, TokenStore.listConnections).
@Suite("BackendClient.normalize (connections)")
struct ConnectionsTests {
    @Test("Normalizes a real-shaped connection with a health check already recorded")
    func normalizesConnectionWithHealthCheck() {
        let raw = RawConnection(
            realmId: "9341456442848752",
            environment: "sandbox",
            companyName: "Sandbox Landscaping Co",
            writeEnabled: true,
            lastHealthCheckAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastHealthCheckStatus: "green"
        )
        let client = BackendClient.normalize(raw)
        #expect(client?.realmID.rawValue == "9341456442848752")
        #expect(client?.environment == .sandbox)
        #expect(client?.companyName == "Sandbox Landscaping Co")
        #expect(client?.writeEnabled == true)
        #expect(client?.lastHealthCheckStatus == .green)
    }

    @Test("A connection never health-checked decodes with nil health fields, not a guess")
    func normalizesConnectionNeverHealthChecked() {
        let raw = RawConnection(
            realmId: "123456",
            environment: "sandbox",
            companyName: nil,
            writeEnabled: false,
            lastHealthCheckAt: nil,
            lastHealthCheckStatus: nil
        )
        let client = BackendClient.normalize(raw)
        #expect(client?.companyName == nil)
        #expect(client?.lastHealthCheckAt == nil)
        #expect(client?.lastHealthCheckStatus == nil)
    }

    @Test("An unrecognized environment string is dropped, never guessed at")
    func dropsUnrecognizedEnvironment() {
        let raw = RawConnection(realmId: "123456", environment: "staging", companyName: nil, writeEnabled: false, lastHealthCheckAt: nil, lastHealthCheckStatus: nil)
        #expect(BackendClient.normalize(raw) == nil)
    }

    @Test("An unrecognized health status string decodes to nil, not a crash or a wrong color")
    func unrecognizedHealthStatusDecodesToNil() {
        let raw = RawConnection(realmId: "123456", environment: "sandbox", companyName: nil, writeEnabled: false, lastHealthCheckAt: nil, lastHealthCheckStatus: "unknown-status")
        #expect(BackendClient.normalize(raw)?.lastHealthCheckStatus == nil)
    }

    @Test("Decodes a real-shaped GET /connections JSON response end to end")
    func decodesRealShapedResponse() throws {
        let json = """
        {
          "connections": [
            {
              "realmId": "9341456442848752",
              "environment": "sandbox",
              "companyName": "Sandbox Landscaping Co",
              "createdAt": "2026-08-16T16:56:43.168Z",
              "updatedAt": "2026-08-28T12:00:00.000Z",
              "writeEnabled": false,
              "lastHealthCheckAt": "2026-08-28T12:00:00.000Z",
              "lastHealthCheckStatus": "green"
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConnectionsResponse.self, from: Data(json.utf8))
        #expect(decoded.connections.count == 1)
        let client = BackendClient.normalize(decoded.connections[0])
        #expect(client?.realmID.rawValue == "9341456442848752")
        #expect(client?.lastHealthCheckStatus == .green)
    }
}
