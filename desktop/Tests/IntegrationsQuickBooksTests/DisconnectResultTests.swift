import Testing
import Foundation
@testable import IntegrationsQuickBooks

/// The exact shapes `POST /realms/:realmId/disconnect` returns
/// (backend/src/routes/connections.ts).
@Suite("DisconnectResult decoding")
struct DisconnectResultTests {
    @Test("Decodes a confirmed revoke")
    func decodesConfirmedRevoke() throws {
        let json = #"{"realmId":"123","revokedAtIntuit":true,"localTokensDeleted":true}"#
        let result = try JSONDecoder().decode(DisconnectResult.self, from: Data(json.utf8))
        #expect(result == DisconnectResult(revokedAtIntuit: true, localTokensDeleted: true))
    }

    @Test("An unconfirmed Intuit revoke stays false, never rounded up to success")
    func decodesUnconfirmedRevoke() throws {
        let json = #"{"realmId":"123","revokedAtIntuit":false,"localTokensDeleted":true}"#
        let result = try JSONDecoder().decode(DisconnectResult.self, from: Data(json.utf8))
        #expect(result.revokedAtIntuit == false)
    }
}
