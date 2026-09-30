import Foundation

/// Tracks the drop from sustained speech to room noise, rather than requiring
/// a USB microphone to fall below one absolute volume. Feed from one thread.
public struct SpeechEndpointDetector: Sendable {
    public private(set) var hasSpeech = false
    public private(set) var stopReason: String?
    private var smoothedLevel: Float = 0
    private var sustainedLevel: Float = 0
    private var speechPeak: Float = 0
    private var lastTime: TimeInterval = 0
    private var quietSince: TimeInterval?
    private let silenceDuration: TimeInterval
    private let maximumDuration: TimeInterval

    public init(silenceDuration: TimeInterval = 1.2, maximumDuration: TimeInterval = 45) {
        self.silenceDuration = silenceDuration
        self.maximumDuration = maximumDuration
    }

    /// Elapsed seconds since recording began; levels use the meter's 0...1 scale.
    public mutating func update(level: Float, elapsed: TimeInterval) -> Bool {
        if stopReason != nil { return true }
        let delta = max(0, elapsed - lastTime)
        lastTime = elapsed
        // Smooth the meter, then learn speaking volume over 250 ms so a
        // single click cannot raise the gate above a quiet speaking voice.
        let weight = Float(1 - exp(-delta / 0.08))
        smoothedLevel += (level - smoothedLevel) * weight
        sustainedLevel += (smoothedLevel - sustainedLevel) * Float(1 - exp(-delta / 0.25))
        speechPeak = max(speechPeak, sustainedLevel)
        let threshold = max(Float(0.015), speechPeak * 0.25)
        if smoothedLevel > threshold {
            hasSpeech = true
            quietSince = nil
        } else if hasSpeech {
            if quietSince == nil { quietSince = elapsed }
            if let quietSince, elapsed - quietSince >= silenceDuration {
                stopReason = "speech ended"
                return true
            }
        }
        if elapsed >= maximumDuration {
            stopReason = "recording limit"
            return true
        }
        return false
    }
}
