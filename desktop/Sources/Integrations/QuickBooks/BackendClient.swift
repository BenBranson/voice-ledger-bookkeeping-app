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

    /// CLAUDE.md rule 4's access-mode gate, read side — `GET
    /// /realms/:realmId/write-access`. Every connection starts Read-Only;
    /// this reads the realm's current flag, never assumes it.
    public func getWriteAccess(realmID: RealmID) async throws -> Bool {
        var url = configuration.baseURL
        url.append(path: "/realms/\(realmID.rawValue)/write-access")

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
        return try JSONDecoder().decode(WriteAccessResponse.self, from: data).writeEnabled
    }

    /// The write side of the same gate — `PUT /realms/:realmId/write-access`.
    /// A separate, explicit control-plane call, never a side effect of any
    /// catalog operation — flipping this is a deliberate human action, not
    /// something that happens implicitly.
    @discardableResult
    public func setWriteAccess(realmID: RealmID, enabled: Bool) async throws -> Bool {
        var url = configuration.baseURL
        url.append(path: "/realms/\(realmID.rawValue)/write-access")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = configuration.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(WriteAccessRequest(enabled: enabled))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw BackendClientError.httpError(status: http.statusCode, body: body)
        }
        return try JSONDecoder().decode(WriteAccessResponse.self, from: data).writeEnabled
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "every connected client on
    /// one screen." `GET /connections` — deliberately the one call in this
    /// client that isn't scoped to `realmID`, mirroring the backend route's
    /// own doc comment on why crossing realms here is intentional, not a
    /// gap in the isolation model.
    public func getConnections() async throws -> [ConnectedClient] {
        var url = configuration.baseURL
        url.append(path: "/connections")

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
        let decoded = try decoder.decode(ConnectionsResponse.self, from: data)
        return decoded.connections.compactMap(Self.normalize)
    }

    /// A raw connection with an environment string this build's
    /// `QBOEnvironment` doesn't recognize is dropped, not guessed at —
    /// mirrors `QBOSyncClient.normalize`'s posture for an unrecognized
    /// `AccountType`. Pulled out as its own static function (rather than
    /// inline in `getConnections()`) so this mapping is unit-testable
    /// without a network call, the same reason `QBOSyncClient.normalize`
    /// is static.
    static func normalize(_ raw: RawConnection) -> ConnectedClient? {
        guard let environment = QBOEnvironment(rawValue: raw.environment) else { return nil }
        return ConnectedClient(
            realmID: RealmID(rawValue: raw.realmId),
            companyName: raw.companyName,
            environment: environment,
            writeEnabled: raw.writeEnabled,
            lastHealthCheckAt: raw.lastHealthCheckAt,
            lastHealthCheckStatus: raw.lastHealthCheckStatus.flatMap { ConnectionHealthStatus(rawValue: $0) }
        )
    }

    /// docs/VOICE_LEDGER_SPEC.md's Client Switcher — `POST
    /// /realms/:realmId/session`. Mints a fresh session token for a
    /// DIFFERENT already-connected realm than this client's own current
    /// session, proving only that the caller already holds a valid
    /// session for *some* realm (this is a single-operator tool — see
    /// the backend route's own doc comment for why that's sufficient,
    /// not a privilege escalation). Never sends or needs a refresh
    /// token — this backend never exposes one to the desktop client at
    /// all, matching every other call in this file.
    public func requestSession(forRealmID targetRealmID: RealmID) async throws -> String {
        var url = configuration.baseURL
        url.append(path: "/realms/\(targetRealmID.rawValue)/session")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
        return try JSONDecoder().decode(SwitchSessionResponse.self, from: data).sessionToken
    }

    /// docs/VOICE_LEDGER_SPEC.md's Ask [AI] panel status — `GET /ai/status`.
    /// Not realm-scoped (the kill switch and API-key configuration are
    /// app-wide, per the backend's `ai_settings` table), but still
    /// session-authenticated, so any connected client can check it.
    public func getAIStatus() async throws -> AIStatus {
        var url = configuration.baseURL
        url.append(path: "/ai/status")

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
        return try JSONDecoder().decode(AIStatus.self, from: data)
    }

    /// The AI kill switch's write side — `POST /ai/settings`. Spec: "a
    /// single toggle that disables all AI features app-wide."
    @discardableResult
    public func setAIEnabled(_ enabled: Bool) async throws -> AIStatus {
        var url = configuration.baseURL
        url.append(path: "/ai/settings")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = configuration.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(AISettingsRequest(enabled: enabled))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw BackendClientError.httpError(status: http.statusCode, body: body)
        }
        return try JSONDecoder().decode(AIStatus.self, from: data)
    }

    /// The Ask [AI] panel's only call — `POST /realms/:realmId/ask-ai`.
    /// `context` is plain text the caller (`AppState`) already composed
    /// from real `Finding`/report data — this client has no opinion about
    /// its shape, matching this whole type's transport-only role. The
    /// OpenAI API key itself never reaches this process; only the backend
    /// holds it (CLAUDE.md rule 3).
    /// - Parameter tier: `.primary` (the app's default, free/local tier) or
    ///   `.secondary` (the opt-in, paid "second opinion" — 2026-08-29). The
    ///   backend rejects any other value outright rather than silently
    ///   treating it as primary, so a caller bug here fails loudly instead
    ///   of ever silently making an unwanted paid request.
    /// `model` (2026-09-06): an opt-in override of the primary/Ollama
    /// tier's model for THIS call only — the backend's own
    /// `ALLOWED_MODEL_OVERRIDES` allowlist is the actual enforcement point
    /// (`backend/src/routes/ai.ts`), this is just the passthrough. Added
    /// for `VoiceEngine`'s two spoken reasoning-fallback call sites: the
    /// app's global default (`gemma4:12b`) reads well for the two
    /// on-screen report buttons but is noticeably slower than
    /// `gemma4:e4b` for a live spoken answer — confirmed live 2026-09-06,
    /// 12.0s vs. 5.3s for the same question, same grounded-answer quality.
    /// `nil` (the default) leaves every other call site's behavior exactly
    /// as it was.
    public func askAI(realmID: RealmID, question: String, context: String, history: [AskAIHistoryTurn] = [], tier: AskAITier = .primary, format: AskAIFormat = .concise, model: String? = nil) async throws -> String {
        var url = configuration.baseURL
        url.append(path: "/realms/\(realmID.rawValue)/ask-ai")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = configuration.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(AskAIRequest(question: question, context: context, history: history, tier: tier.rawValue, format: format.rawValue, model: model))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw BackendClientError.httpError(status: http.statusCode, body: body)
        }
        return try JSONDecoder().decode(AskAIResponse.self, from: data).answer
    }

    /// The tool-calling counterpart to `askAI` (2026-09-06) — Voice
    /// Ledger's own in-app voice assistant moving off exact-phrase
    /// matching onto real function-calling (`VoiceToolLoop`). Always the
    /// primary/Ollama tier (the backend's own route rejects `tools` on
    /// the secondary tier outright) and always `model` — the tool-calling
    /// loop needs a specific, verified-capable model, not whatever the
    /// backend happens to default to.
    ///
    /// `tools` is `[[String: JSONValue]]`, not `[[String: Any]]` — this is
    /// an `actor`, and a plain `Any`-typed dictionary can't cross that
    /// boundary (the exact same fix a sibling project's own MCP work
    /// needed for the identical reason). Returns the model's own answer
    /// text (empty when it chose to call a tool instead of answering
    /// directly — confirmed live this is the real Ollama shape, not an
    /// error) plus any tool calls it made.
    public func askAIWithTools(
        realmID: RealmID,
        question: String,
        context: String,
        history: [AskAIHistoryTurn] = [],
        model: String,
        tools: [[String: JSONValue]]
    ) async throws -> (answer: String, toolCalls: [AIToolCall]) {
        var url = configuration.baseURL
        url.append(path: "/realms/\(realmID.rawValue)/ask-ai")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = configuration.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body = AskAIWithToolsRequest(
            question: question,
            context: context,
            history: history,
            tier: AskAITier.primary.rawValue,
            model: model,
            tools: tools.map { JSONValue.object($0) }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw BackendClientError.httpError(status: http.statusCode, body: responseBody)
        }
        let decoded = try JSONDecoder().decode(AskAIWithToolsResponse.self, from: data)
        let toolCalls = (decoded.toolCalls ?? []).map { AIToolCall(id: $0.id, name: $0.name, arguments: $0.arguments) }
        return (decoded.answer, toolCalls)
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

struct WriteAccessRequest: Encodable, Sendable {
    let enabled: Bool
}

struct WriteAccessResponse: Decodable, Sendable {
    let writeEnabled: Bool
}

struct SwitchSessionResponse: Decodable, Sendable {
    let sessionToken: String
}

struct ConnectionsResponse: Decodable, Sendable {
    let connections: [RawConnection]
}

struct RawConnection: Decodable, Sendable {
    let realmId: String
    let environment: String
    let companyName: String?
    let writeEnabled: Bool
    let lastHealthCheckAt: Date?
    let lastHealthCheckStatus: String?
}

struct AISettingsRequest: Encodable, Sendable {
    let enabled: Bool
}

/// Mirrors `backend/src/routes/ai.ts`'s `tier` field — `"primary"` (the
/// app's default tier) or `"secondary"` (the opt-in, paid "second
/// opinion," 2026-08-29).
public enum AskAITier: String, Sendable {
    case primary
    case secondary
}

/// Mirrors `backend/src/routes/ai.ts`'s `format` field (2026-08-29) —
/// `.report` asks for a genuinely fuller, multi-paragraph write-up
/// instead of the brief, spoken-friendly default. Used ONLY by the two
/// report-generation buttons (`AppState.generateHealthReport`/
/// `generateValueSummary`); every other caller keeps `.concise`.
/// `.clientMessage` (2026-08-31): drafts written for the CLIENT to read,
/// not the bookkeeper — a different register (no "severity," "materiality,"
/// or other internal jargon), used by `AppState.draftClientMessage` and
/// the Close Package executive summary.
public enum AskAIFormat: String, Sendable {
    case concise
    case report
    case clientMessage = "client_message"
}

struct AskAIRequest: Encodable, Sendable {
    let question: String
    let context: String
    let history: [AskAIHistoryTurn]
    let tier: String
    let format: String
    /// `nil` (omitted from the encoded JSON) unless the caller explicitly
    /// wants a different Ollama model for this one call — see `askAI`'s
    /// own doc comment.
    let model: String?
}

struct AskAIResponse: Decodable, Sendable {
    let answer: String
}

struct AskAIWithToolsRequest: Encodable, Sendable {
    let question: String
    let context: String
    let history: [AskAIHistoryTurn]
    let tier: String
    let model: String
    let tools: [JSONValue]
}

struct AskAIWithToolsResponse: Decodable, Sendable {
    struct ToolCallPayload: Decodable, Sendable {
        let id: String?
        let name: String
        let arguments: [String: JSONValue]
    }
    let answer: String
    let toolCalls: [ToolCallPayload]?
}

/// A single tool call the model chose to make — see `BackendClient
/// .askAIWithTools`'s doc comment for why `arguments` is `JSONValue`-typed
/// rather than `[String: Any]`.
public struct AIToolCall: Sendable {
    public let id: String?
    public let name: String
    public let arguments: [String: JSONValue]
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
