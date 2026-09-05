import Foundation

/// A minimal Model Context Protocol JSON-RPC 2.0 dispatcher — handles
/// exactly the methods a tool-only server needs (no resources, no
/// prompts, no sampling): `initialize`, `notifications/initialized`,
/// `ping`, `tools/list`, `tools/call`. Everything else that arrives as a
/// REQUEST (has an `id`) gets a "method not found" error, per the JSON-RPC
/// 2.0 spec; anything that arrives as a NOTIFICATION (no `id`) is silently
/// ignored — a notification must never receive a response at all, spec'd
/// behavior this dispatcher enforces by returning `nil` rather than an
/// empty/error response.
///
/// Deliberately untyped (`[String: Any]` in and out via `JSONSerialization`)
/// rather than a `Codable` request/response hierarchy — MCP's `params`/
/// `result` shapes vary per method and per tool's own `inputSchema`, and a
/// hand-rolled `Codable` model for that would need as much dynamic-JSON
/// escape-hatching as this does, with more ceremony for a two-tool v1.
enum MCPDispatcher {
    static func handle(request: [String: Any], tools: VoiceLedgerTools) async -> [String: Any]? {
        let id = request["id"]
        let isNotification = id == nil
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return response(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "voiceledger-mcp", "version": "0.1.0"]
            ])

        // The client's acknowledgment after `initialize` — and any other
        // `notifications/*` this dispatcher doesn't specifically know
        // about — never gets a response, by JSON-RPC notification
        // semantics, whether or not this server does anything with it.
        case _ where method.hasPrefix("notifications/"):
            return nil

        case "ping":
            return response(id: id, result: [:])

        case "tools/list":
            return response(id: id, result: ["tools": tools.definitions])

        case "tools/call":
            guard let name = params["name"] as? String else {
                return isNotification ? nil : errorResponse(id: id, code: -32602, message: "tools/call requires a \"name\" parameter")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = await tools.call(name: name, arguments: arguments)
            return isNotification ? nil : response(id: id, result: result)

        default:
            return isNotification ? nil : errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private static func response(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private static func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}
