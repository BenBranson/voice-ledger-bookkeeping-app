import Foundation

/// The desktop client's channel to the local `voice-service` (STT/TTS
/// only — see that service's own doc comment: "neither endpoint computes
/// or knows anything about financial data"). Mirrors
/// `IntegrationsQuickBooks.BackendClient`'s shape (an actor, a fixed base
/// URL, a small typed error), but this client talks to a DIFFERENT local
/// process than the QBO backend — voice-service never sees a realm id, a
/// session token, or any bookkeeping data at all, only raw audio/text.
///
/// **Hardcoded to loopback, not configurable** — unlike `BackendClient`'s
/// `configuration.baseURL` (which can legitimately point at a remote
/// backend), this client only ever talks to `127.0.0.1`. There is no
/// initializer parameter that could point it at a different host — voice
/// audio must never leave this machine, and that's enforced by there
/// being no code path that could send it elsewhere, not by a default that
/// happens not to be overridden.
public actor VoiceServiceClient {
    private let baseURL: URL
    private let session: URLSession

    public init(port: Int = 8790, session: URLSession = .shared) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.session = session
    }

    public func healthCheck() async throws -> Bool {
        let request = URLRequest(url: baseURL.appending(path: "health"))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return false
        }
        struct HealthBody: Decodable { let status: String }
        return (try? JSONDecoder().decode(HealthBody.self, from: data))?.status == "ok"
    }

    /// `audioData` is sent as a multipart file upload, matching
    /// `voice-service/main.py`'s `UploadFile = File(...)` parameter.
    /// Returns the empty string (never throws) for the service's own
    /// `empty_or_too_short` warning — that's a real "nothing usable was
    /// recorded" outcome, not a network/decode failure, so the caller
    /// (`VoiceEngine`) can tell the two apart without parsing this
    /// method's error type.
    public func transcribe(audioData: Data, filename: String = "command.wav", mimeType: String = "audio/wav") async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "transcribe"))
        request.httpMethod = "POST"
        let boundary = "voiceledger-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceServiceClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw VoiceServiceClientError.httpError(status: http.statusCode, body: bodyText)
        }

        struct TranscribeResponse: Decodable { let text: String; let warning: String? }
        let decoded = try JSONDecoder().decode(TranscribeResponse.self, from: data)
        return decoded.text
    }

    /// Returns raw WAV bytes (`voice-service/main.py`'s `/speak` response),
    /// ready to hand to `AVAudioPlayer`.
    public func synthesize(text: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "speak"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["text": text])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceServiceClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw VoiceServiceClientError.httpError(status: http.statusCode, body: bodyText)
        }
        return data
    }
}

public enum VoiceServiceClientError: Error, CustomStringConvertible {
    case invalidResponse
    case httpError(status: Int, body: String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "voice-service returned a non-HTTP response."
        case .httpError(let status, let body):
            return "voice-service returned HTTP \(status): \(body)"
        }
    }
}
