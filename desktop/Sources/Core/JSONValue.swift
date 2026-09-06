import Foundation

/// A minimal untyped-JSON value — exists because Ollama's tool-calling
/// `arguments` (2026-09-06, Voice Ledger's own in-app voice assistant
/// moving off exact-phrase matching onto real function-calling) can be any
/// JSON shape the model produced, and `JSONSerialization`'s `[String: Any]`
/// isn't `Sendable` — it can't cross an actor boundary (`BackendClient` is
/// an `actor`), which a plain `[String: Any]` dictionary tried and failed
/// to do here exactly the way it did in a sibling project's own MCP work.
/// `anyValue` converts back to a plain `Any` for handing to
/// `JSONSerialization` at the one point (`VoiceToolLoop`) that actually
/// needs to read a specific argument's real value.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let value): return value.map(\.anyValue)
        case .object(let value): return value.mapValues { $0.anyValue }
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
