import SwiftUI

/// Status hues — `private` to this file, on purpose.
///
/// docs/design/DESIGN_SYSTEM.md, Decision 1: the original environment badge
/// borrowed `VLColor.coral` and `VLColor.amber` directly, which meant
/// production (a *permanent* state once live) sat on screen wearing the same
/// hue reserved for urgent findings — exactly the kind of collision that
/// trains a user to stop seeing the color that's supposed to mean something.
///
/// The fix isn't a comment asking people not to do that again. These three
/// hues are declared `private` here, so no other file in this module —
/// including `VLEnvironment.swift` — can spell the literal green, amber, or
/// coral value. The only way to obtain a status color from outside this file
/// is `VLStatus.color`, which always arrives bundled with an icon and a
/// label. A future badge that wants "urgent-looking" has to reach for
/// `VLStatus.urgent` itself — and using a finding-severity case to color an
/// environment marker is obviously wrong the moment it's spelled out, which
/// is the whole point.
private enum StatusHue {
    static let verified = Color(hex: 0x3ECF8E)
    static let reviewNeeded = Color(hex: 0xF4B860)
    static let urgent = Color(hex: 0xF06472)
    /// A dedicated status blue — NOT `VLColor.cyan`/`cyanBright` (accent
    /// vocabulary) and NOT `VLColor.blue` (fails 4.5:1 as text on
    /// surfaceCard, see VLColor.swift). Measures 5.92:1 on surfaceCard.
    /// Visually distinguishable from both accent hues so "informational"
    /// doesn't silently read as "selected" or "active."
    static let informational = Color(hex: 0x4FA3E8)
}

/// The accounting status vocabulary — the ONLY vocabulary permitted to
/// communicate what a check, finding, or page state means.
///
/// This mirrors the color/severity table in docs/VOICE_LEDGER_SPEC.md and the
/// derivation in docs/phase-0/05_FINDING_SCHEMA.md §5.7. It exists as a type
/// rather than as a style guide because the rule it encodes —
/// **green means verified, not merely "nothing found"** (CLAUDE.md rule 5) —
/// is the single most damaging thing this app could get wrong, and a rule
/// that lives only in prose is a rule that erodes.
///
/// Every case carries a color, an SF Symbol, and a written label. There is no
/// initializer that yields a color without a label, because the spec requires
/// status never be communicated through color alone.
public enum VLStatus: String, Sendable, CaseIterable {

    /// Green + checkmark. **Four preconditions, all required:** the required
    /// data was present, the check actually completed, the result is current
    /// (not stale), and no exception was found.
    ///
    /// A rule returning zero findings is NOT sufficient — that is
    /// `.notChecked` or `.coverageIncomplete` if the data wasn't there.
    /// See docs/phase-0/08_RULE_ENGINE.md §8.1: `.cannotEvaluate` is a
    /// distinct outcome from `.pass` precisely so this can't collapse.
    case verified

    /// Yellow + magnifier. A human needs to look at this.
    case reviewNeeded

    /// Red + alert triangle. Urgent or materially risky.
    case urgent

    /// Blue + info. A recommendation or opportunity — not a problem.
    case informational

    /// Purple + speech bubble. Waiting on the client.
    case awaitingClient

    /// Gray + clock. Not checked, stale, or unavailable. This is the honest
    /// default — when in doubt, a check is gray, never green.
    case notChecked

    /// Gray outline + upload/hand. Requires a file import or manual QBO work
    /// before it can become actionable at all.
    case actionRequired

    /// The color for this status. Never used without `iconName` and `label`.
    public var color: Color {
        switch self {
        case .verified: return StatusHue.verified
        case .reviewNeeded: return StatusHue.reviewNeeded
        case .urgent: return StatusHue.urgent
        case .informational: return StatusHue.informational
        case .awaitingClient: return VLColor.violet
        case .notChecked: return VLColor.textMuted
        case .actionRequired: return VLColor.textMuted
        }
    }

    /// SF Symbols — the system icon family, already available on macOS. Chosen
    /// over adding an icon dependency (the brief named Lucide, which is a web
    /// library and has no place in a native macOS target).
    public var iconName: String {
        switch self {
        case .verified: return "checkmark.circle.fill"
        case .reviewNeeded: return "magnifyingglass.circle.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        case .informational: return "info.circle.fill"
        case .awaitingClient: return "bubble.left.fill"
        case .notChecked: return "clock.fill"
        case .actionRequired: return "square.and.arrow.up.circle"
        }
    }

    /// The written label. Required — status is never color alone.
    public var label: String {
        switch self {
        case .verified: return "Verified"
        case .reviewNeeded: return "Review needed"
        case .urgent: return "Urgent"
        case .informational: return "Recommendation"
        case .awaitingClient: return "Waiting on client"
        case .notChecked: return "Not checked"
        case .actionRequired: return "Action required"
        }
    }

    /// Whether this status renders as an outline treatment rather than a
    /// filled pill — distinguishes "not yet actionable" (`.actionRequired`)
    /// from "checked and stale" (`.notChecked`), which share a hue.
    public var isOutlined: Bool {
        self == .actionRequired
    }
}

/// Why a check could not produce a `.verified` result. Renders as the
/// "Coverage incomplete" copy the spec requires instead of "Passed."
///
/// This is the presentation-side counterpart to
/// `MissingRequirement` in docs/phase-0/08_RULE_ENGINE.md §8.1.
public enum VLCoverageGap: Sendable {
    case noDataYet
    case partialCoverage(reason: String)
    case importRequired(what: String)
    case importStale(filename: String)
    case crossFootFailed
    case screenshotSourcePartial
    case connectionUnhealthy
    case capabilityUnverified(matrixRow: String)
    /// docs/phase-0/10_STAGING_APPROVAL_AUDIT.md §10.6 — a submitted write
    /// whose outcome is unknown. Blocks the affected entity until a
    /// resolution probe settles it. The design brief did not account for
    /// this state; it is arguably the most important one in the app.
    case unresolvedWrite

    public var headline: String {
        switch self {
        case .noDataYet: return "Not checked"
        case .partialCoverage: return "Coverage incomplete"
        case .importRequired: return "Import required"
        case .importStale: return "Import out of date"
        case .crossFootFailed: return "Extraction unreliable"
        case .screenshotSourcePartial: return "Coverage incomplete — screenshot source"
        case .connectionUnhealthy: return "Connection unavailable"
        case .capabilityUnverified: return "Capability not verified"
        case .unresolvedWrite: return "Unresolved write — outcome unknown"
        }
    }

    public var status: VLStatus {
        switch self {
        case .importRequired, .importStale: return .actionRequired
        case .crossFootFailed, .unresolvedWrite: return .reviewNeeded
        default: return .notChecked
        }
    }
}

/// Whether writes are permitted for the active client. Read-Only is the
/// default for every new connection (CLAUDE.md rule 4) and renders as a calm
/// shield — it is the safe state, not a warning.
///
/// This intentionally reuses `StatusHue.reviewNeeded`'s amber for
/// `.writeEnabled` — that reuse is visible and deliberate (both files are
/// literally the same file), unlike the environment-badge collision Decision
/// 1 fixed. Write-Enabled is not an error state and must not use coral,
/// which is reserved for actual risk.
public enum VLAccessMode: Sendable {
    case readOnly
    case writeEnabled

    public var label: String {
        switch self {
        case .readOnly: return "Read-Only"
        case .writeEnabled: return "Write-Enabled"
        }
    }

    public var iconName: String {
        switch self {
        case .readOnly: return "shield.lefthalf.filled"
        case .writeEnabled: return "pencil.circle.fill"
        }
    }

    public var accent: Color {
        switch self {
        case .readOnly: return VLColor.teal
        case .writeEnabled: return StatusHue.reviewNeeded
        }
    }
}
