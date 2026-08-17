import Foundation
import Core

/// The desktop client's ONLY channel to QBO data — and it isn't QBO at all.
/// Every call goes to our own backend's fixed operation catalog
/// (docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.4). There is no method on
/// this type that accepts a URL, a path, or an HTTP verb chosen by the
/// caller — only named operations from `CatalogOperation`.
public actor BackendClient {
    private let configuration: BackendConfiguration
    private let session: URLSession

    public init(configuration: BackendConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// docs/phase-0/02_QBO_CAPABILITY_MATRIX.md row C1: a live, timestamped
    /// call — never a cached assumption. This is the exact request the
    /// Phase 1 step 1.2 exit gate ("health check green from desktop") is
    /// checking. It hits the backend's dedicated health route, which
    /// internally performs the same `readCompanyInfo` catalog operation
    /// rather than a separate code path, so there is exactly one
    /// implementation of "is this connection actually alive."
    public func healthCheck(realmID: RealmID) async throws -> HealthCheckResult {
        var url = configuration.baseURL
        url.append(path: "/realms/\(realmID.rawValue)/health")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = configuration.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw BackendClientError.httpError(status: http.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HealthCheckResult.self, from: data)
    }

    /// The one generic call this client makes — `POST
    /// /realms/:realmId/operations/:operationName`, mirroring
    /// `backend/src/routes/operations.ts`'s "entire surface." `operation` is
    /// `CatalogOperation`, not a `String`, so nothing in this module can
    /// invoke a name outside the fixed catalog (§3.4). `params` is JSON,
    /// encoded from a caller-supplied `Encodable`; the raw QBO response body
    /// is returned undecoded — normalization into Core's shape happens one
    /// layer up (`QBOSyncClient`), which is where §4's normalization
    /// contract actually lives, not in this transport-only client.
    public func call<Params: Encodable>(
        _ operation: CatalogOperation,
        realmID: RealmID,
        params: Params
    ) async throws -> Data {
        var url = configuration.baseURL
        url.append(path: "/realms/\(realmID.rawValue)/operations/\(operation.rawValue)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = configuration.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(params)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw BackendClientError.httpError(status: http.statusCode, body: body)
        }
        return data
    }
}

/// Empty parameter payload, for operations like `readPreferences` that take
/// none — mirrors the backend's `z.object({}).strict()` schema.
public struct EmptyParams: Encodable, Sendable {
    public init() {}
}

public struct HealthCheckResult: Codable, Sendable {
    public let realmID: String
    public let status: HealthStatus
    public let checkedAt: Date
    public let latencyMs: Int
    public let detail: String?

    enum CodingKeys: String, CodingKey {
        case realmID = "realmId"
        case status, checkedAt, latencyMs, detail
    }
}

/// Mirrors the color semantics in docs/phase-0/05_FINDING_SCHEMA.md §5.7 —
/// a health check has no "we didn't look" state that could be confused with
/// "we looked and it's fine." Gray means the check didn't complete.
public enum HealthStatus: String, Codable, Sendable {
    case green
    case yellow
    case red
    case gray
}

public enum BackendClientError: Error, CustomStringConvertible {
    case invalidResponse
    case httpError(status: Int, body: String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "Backend returned a non-HTTP response."
        case .httpError(let status, let body):
            return "Backend returned HTTP \(status): \(body)"
        }
    }
}
