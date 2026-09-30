import Testing
@testable import Voice

struct SpeechEndpointDetectorTests {
    @Test func elevatedRoomNoiseDoesNotHoldCommandFor45Seconds() {
        var detector = SpeechEndpointDetector()
        var stoppedAt: Double?
        for frame in 1...500 {
            let time = Double(frame) * 0.02
            let level: Float = time < 0.5 ? 0.03 : time < 2 ? 0.3 : 0.03
            if detector.update(level: level, elapsed: time) { stoppedAt = time; break }
        }
        #expect(detector.hasSpeech)
        #expect(stoppedAt != nil)
        #expect((stoppedAt ?? 45) < 3.6)
        #expect(detector.stopReason == "speech ended")
    }

    @Test func pausesWithinASentenceDoNotEndRecording() {
        var detector = SpeechEndpointDetector()
        for frame in 1...300 {
            let time = Double(frame) * 0.02
            let level: Float = (time > 2 && time < 2.8) ? 0.03 : 0.3
            let stopped = detector.update(level: level, elapsed: time)
            #expect(!stopped)
        }
    }

    @Test func quietVoiceStillDetected() {
        var detector = SpeechEndpointDetector()
        var stopped = false
        for frame in 1...200 {
            stopped = detector.update(level: frame < 75 ? 0.025 : 0.002, elapsed: Double(frame) * 0.02)
            if stopped { break }
        }
        #expect(stopped)
        #expect(detector.hasSpeech)
    }

    @Test func singleLoudClickDoesNotCutOffQuietSpeech() {
        var detector = SpeechEndpointDetector()
        for frame in 1...300 {
            let stopped = detector.update(level: frame == 50 ? 1 : 0.03, elapsed: Double(frame) * 0.02)
            #expect(!stopped)
        }
    }

    @Test func silenceNeverBecomesSpeechAndLimitRemainsBounded() {
        var detector = SpeechEndpointDetector()
        for frame in 1..<2250 {
            let stopped = detector.update(level: 0.002, elapsed: Double(frame) * 0.02)
            #expect(!stopped)
        }
        let stopped = detector.update(level: 0.002, elapsed: 45)
        #expect(stopped)
        #expect(!detector.hasSpeech)
        #expect(detector.stopReason == "recording limit")
    }
}
