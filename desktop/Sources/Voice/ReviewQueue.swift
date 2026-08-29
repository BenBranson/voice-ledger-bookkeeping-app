import Foundation
import Core

/// A ranked, one-at-a-time walkthrough of open findings — a real, new
/// feature this app didn't have before voice control, not just voice UI
/// over something that already existed. docs/VOICE_LEDGER_HANDOFF.md's
/// reference design (`server/voiceTools.js`'s `buildReviewQueue`) ranked
/// via several signals (severity, confidence, financial impact); this is
/// the honest slice buildable from what `Finding` already carries as real
/// computed fields — severity, then dollar exposure, both descending —
/// not a fabricated priority score.
public enum ReviewQueue {
    /// Only `.open` findings are queued — a resolved/dismissed finding has
    /// nothing left to review.
    public static func build(from findings: [Finding]) -> [String] {
        findings
            .filter { $0.status == .open }
            .sorted { lhs, rhs in
                // `Severity` is already `Comparable` (Core/Finding.swift) —
                // no need to reinvent an ordinal here.
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.dollarExposure > rhs.dollarExposure
            }
            .map(\.id)
    }
}
