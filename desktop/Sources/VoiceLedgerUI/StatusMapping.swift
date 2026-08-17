import Core
import DesignSystem

/// The one place `Severity`/`Coverage`/`Confidence` (Core, no SwiftUI) become
/// `VLStatus` (DesignSystem, pure presentation). Neither Core nor
/// DesignSystem may depend on the other (Package.swift's boundary comments),
/// so this mapping has to live in the UI layer — it cannot live in either.
public enum StatusMapping {
    /// `CLAUDE.md` rule 5, made concrete: green requires complete coverage
    /// AND zero findings. A `.findings` outcome is never green regardless of
    /// severity — it renders per-finding severity instead (see
    /// `severityStatus`).
    public static func status(for outcome: RuleOutcome) -> VLStatus {
        switch outcome {
        case .pass(let coverage, _):
            return coverage == .complete ? .verified : .notChecked
        case .findings:
            return .reviewNeeded // the page itself is "needs review"; each finding has its own severity color
        case .cannotEvaluate:
            return .notChecked
        }
    }

    public static func coverageGap(for outcome: RuleOutcome) -> VLCoverageGap? {
        switch outcome {
        case .cannotEvaluate(.partialCoverage(let reason)):
            return .partialCoverage(reason: reason)
        default:
            return nil
        }
    }

    public static func severityStatus(_ severity: Severity) -> VLStatus {
        switch severity {
        case .high: return .urgent
        case .low: return .informational
        }
    }

    public static func resolutionStatus(_ kind: ResolutionKind) -> VLStatus {
        switch kind {
        case .manualQBO: return .actionRequired
        case .stagedAPI: return .reviewNeeded
        }
    }
}
