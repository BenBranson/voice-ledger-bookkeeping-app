import Foundation

/// Everything needed to reach our own thin backend. Deliberately the ONLY
/// thing this module holds — there is no QBO client ID, QBO client secret,
/// or Claude API key anywhere in this target, and there must never be one.
///
/// docs/phase-0/03_SECURITY_THREAT_MODEL.md §3.3: "the QBO client secret and
/// Claude API key live only in the thin backend." This type's job is to make
/// that easy to keep true — every value here is supplied at runtime, never
/// compiled in.
///
/// `Tests/ArchitectureTests/SecretScanTests.swift` scans this target's
/// source for secret-shaped literals and fails the build if it finds one,
/// which is the "no secret in the client bundle" half of the 1.2 exit gate.
public struct BackendConfiguration: Sendable {
    public let baseURL: URL
    public let sessionToken: String?

    public init(baseURL: URL, sessionToken: String?) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
    }

    /// Reads configuration from the environment. Nothing here is a literal —
    /// an empty or missing `VOICE_LEDGER_BACKEND_URL` is a configuration
    /// error to surface, never a fallback to a baked-in address.
    ///
    /// Takes a plain dictionary (defaulting to the real process environment)
    /// rather than `ProcessInfo` itself, so tests can inject an empty
    /// environment without subclassing a Foundation type that isn't
    /// designed to be subclassed.
    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> BackendConfiguration {
        guard let urlString = environment["VOICE_LEDGER_BACKEND_URL"],
              let url = URL(string: urlString) else {
            throw BackendConfigurationError.missingBaseURL
        }
        let token = environment["VOICE_LEDGER_SESSION_TOKEN"]
        return BackendConfiguration(baseURL: url, sessionToken: token)
    }
}

public enum BackendConfigurationError: Error, CustomStringConvertible {
    case missingBaseURL

    public var description: String {
        switch self {
        case .missingBaseURL:
            return "VOICE_LEDGER_BACKEND_URL is not set. Point it at your deployed backend, e.g. https://your-service.onrender.com"
        }
    }
}
