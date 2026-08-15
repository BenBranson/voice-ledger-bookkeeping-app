# 5. Universal Finding Schema — Swift Types

The spec's Universal Finding Record, expressed as Swift. Illustrative — reviewed
here, implemented in Phase 1.

Two things drove the shape beyond a direct transliteration:

1. **Detection and resolution are separate axes** (spec) and the type system
   should make it impossible to conflate them.
2. **Provenance is not optional.** A finding without provenance cannot be
   trusted, so there is no initializer that omits it.

---

## 5.1 The finding

```swift
struct Finding: Identifiable, Hashable, Codable, Sendable {

    // ── Identity ────────────────────────────────────────────────────────────
    let id: FindingID
    let realmID: RealmID                  // §7 — isolation key, never optional
    let period: AccountingPeriod
    let page: WorkflowPage                // which of the 12 pages owns it

    // ── Origin ──────────────────────────────────────────────────────────────
    let ruleID: RuleID
    let ruleVersion: RuleVersion          // §8 — bump invalidates prior findings
    let detectedAt: Date
    let minorVersion: Int?                // QBO minor version in force (§2.7)

    // ── Classification — all deterministic, all from code (CLAUDE.md #1) ────
    let title: String                     // rendered by code, not by Claude
    let category: FindingCategory
    let severity: Severity
    let confidence: Confidence
    let dollarExposure: Money?            // nil when not quantifiable
    let materiality: MaterialityAssessment

    // ── Capability — two independent axes ───────────────────────────────────
    let detectionCapability: DetectionCapability
    let resolutionCapability: ResolutionCapability
    let resolutionConstraint: ResolutionConstraint?   // §2 row 4.6

    // ── Evidence ────────────────────────────────────────────────────────────
    let affectedTransactions: [LedgerTransactionRef]
    let evidence: [EvidenceItem]
    let provenance: Provenance            // §4.5 — never optional
    let riskIfIgnored: RiskStatement

    // ── Proposed actions ────────────────────────────────────────────────────
    let recommendedActions: [ProposedAction]   // ordered; first is recommended
    let preApprovalChecklist: [String]         // "view both transactions in QBO"

    // ── Claude-authored prose — always separable, always optional ───────────
    var explanation: GeneratedProse?
    var clientQuestion: GeneratedProse?

    // ── Lifecycle ───────────────────────────────────────────────────────────
    var status: FindingStatus
    var assignedTo: String?
    var resolution: Resolution?
    var qboBeforeSnapshot: EntitySnapshot?
    var qboAfterSnapshot: EntitySnapshot?
}
```

**Note what is *not* here: a `color`.** Color is derived, never stored — see
§5.7. Storing it would let a finding's color drift from its actual state, which
is the exact failure `CLAUDE.md` rule 5 forbids.

**`explanation` is `Optional` and mutable.** With the AI kill switch on, every
finding is fully functional with `explanation == nil`: severity, dollar exposure,
evidence, and proposed actions are all deterministic. That optionality is the
type-level proof that the kill switch is real rather than aspirational (spec,
Claude API Connection).

---

## 5.2 The two capability axes

```swift
/// Can we find this problem, and how?
enum DetectionCapability: String, Codable, Sendable, CaseIterable {
    case automatic        // rules run on API data, no human input
    case assisted         // rules run but need human interpretation to be actionable
    case importRequired   // needs a file or screenshot before it can be detected
    case unavailable      // cannot be detected by this app at all
}

/// Can we fix it, and how?
enum ResolutionCapability: String, Codable, Sendable, CaseIterable {
    case automaticAPI     // reserved; nothing uses it (see note)
    case stagedAPI        // staged locally, human-approved, then written via API
    case manualQBO        // you do it in QBO; we guide and record
    case unsupported      // no path exists
}
```

**`automaticAPI` exists in the enum but nothing may use it in Phase 1.**
`CLAUDE.md` rule 2 requires an explicit human approval step before any production
write. A finding classified `automaticAPI` would be a rule violation, so the
engine asserts against it. It stays in the enum because the spec names it and
because removing it would hide the distinction; a lint rule and a test enforce
that the case is never constructed.

```swift
/// Why a resolution is narrower than the API technically permits.
/// §2 row 4.6: capable but prohibited.
enum ResolutionConstraint: Hashable, Codable, Sendable {
    case policyProhibited(reason: String)   // API can, we won't — reason travels with the finding
    case closedPeriod(closeDate: AccountingDate)
    case capabilityUnverified(matrixRowID: String)   // CLAUDE.md #6 — not sandbox-proven
    case subscriptionRequired(feature: String)       // e.g. Class needs Plus+
    case linkedTransactions([LedgerTransactionRef])
}
```

`capabilityUnverified` is how `CLAUDE.md` rule 6 reaches the UI. A finding whose
resolution depends on a matrix row still marked `ASSUMED` renders its action as
unavailable **with the matrix row cited**, rather than offering a button that
might fail. This makes the rule self-enforcing in the product, not just in
review.

---

## 5.3 Severity, confidence, status — three separate axes

Per spec: severity (how damaging), confidence (how sure), status (what's
happening now) stay separate.

```swift
/// How damaging if real. Assigned by deterministic code only.
enum Severity: Int, Codable, Sendable, Comparable, CaseIterable {
    case informational = 0    // opportunity or recommendation
    case low = 1
    case medium = 2
    case high = 3
    case urgent = 4           // material risk
}

/// How sure the rule is that this is real. Deterministic — a rule computes it
/// from its own matching criteria, never from an LLM's opinion.
enum Confidence: Int, Codable, Sendable, Comparable, CaseIterable {
    case low = 0, medium = 1, high = 2
}

enum FindingStatus: String, Codable, Sendable {
    case new
    case underReview
    case awaitingClient          // purple; the tagged-finding form of "Stop & Ask Client"
    case staged                  // a correction sits in the staging queue
    case submitted               // write sent, outcome not yet confirmed (§10)
    case resolved
    case dismissed
    case needsRevalidation       // rule version bumped, or upstream data changed (§6)
    case superseded              // re-detection replaced it
}
```

**Why `Severity` and `Confidence` are `Int`-backed and `Comparable`:** ranking
risk is a deterministic operation the rules engine performs (spec, Rules Engine
vs. Claude). Comparability belongs in the type.

**Why there is no `.falsePositive`:** dismissal carries a reason
(`DismissalReason`, §5.6) which distinguishes "not actually a problem" from
"known and accepted." Collapsing them loses the information that drives client
memory rules.

---

## 5.4 Evidence

```swift
enum EvidenceItem: Hashable, Codable, Sendable {
    /// A transaction, with the specific fields that triggered the match.
    case transaction(ref: LedgerTransactionRef, highlightedFields: [String])
    /// A computed comparison. `computedBy` names the rule — never Claude.
    case computation(label: String, value: Money, computedBy: RuleID)
    /// A row from an imported document, with a link back to the source region.
    case documentExcerpt(document: ImportedDocumentRef,
                         rowIndex: Int,
                         region: SourceRegion?)
    /// A cell from a normalized report.
    case reportCell(kind: ReportKind, rowPath: [String], column: ColumnKey, value: ReportValue)
    /// An absence. "Statement line X has no matching posting."
    case absence(description: String, searchedIn: String)
}
```

**`.absence` is the case most likely to be forgotten and most needed.** Page 4
and Page 5 findings are frequently about something that *isn't* there. Evidence
for a missing item has to describe what was searched, or the finding is
unreviewable.

```swift
struct RiskStatement: Hashable, Codable, Sendable {
    let deterministicSummary: String     // template-filled by code
    let elaboration: GeneratedProse?     // Claude, optional
}
```

Same pattern as `explanation`: a code-authored core that always exists, with
optional LLM elaboration. Every user-facing string in a finding follows this
shape, so the kill switch degrades the product's prose without degrading its
substance.

---

## 5.5 Proposed actions

```swift
struct ProposedAction: Identifiable, Hashable, Codable, Sendable {
    let id: ProposedActionID
    let label: String                    // "Void the second entry"
    let rationale: String                // deterministic; when this is the right choice
    let mechanism: ActionMechanism
    let consequences: [Consequence]      // computed, not narrated
    let reversal: ReversalPlan
    let requiresCapability: [String]     // matrix row IDs this depends on
}

enum ActionMechanism: Hashable, Codable, Sendable {
    /// Maps to exactly one backend catalog operation (§3.4).
    case stagedWrite(operation: CatalogOperationKind, parameters: StagedWriteParameters)
    /// A Type C guided procedure performed by you, in QBO.
    case guidedManual(procedure: GuidedProcedure)
    /// Ask the client; answer attaches permanently to the finding.
    case askClient(draftQuestion: GeneratedProse?)
    /// Accept and record.
    case dismiss(reason: DismissalReason)
    /// Deliberate no-op with a recorded justification.
    case acceptAsIs(justification: String)
}

struct Consequence: Hashable, Codable, Sendable {
    let domain: ConsequenceDomain    // .reconciliation, .taxPeriod, .reporting, .auditTrail
    let description: String
    let magnitude: Money?
}

enum ReversalPlan: Hashable, Codable, Sendable {
    case reversible(via: CatalogOperationKind)
    case reversibleManually(procedure: GuidedProcedure)
    case irreversible(warning: String)   // hard delete, account merge
}
```

**`ActionMechanism.stagedWrite` names a catalog operation, not a URL.** The
finding cannot describe an arbitrary QBO call even in principle — §3.4's control
reaches all the way into the finding schema. `CatalogOperationKind` is a closed
enum mirroring the backend catalog, so an action referencing an unimplemented
operation is a compile error.

**`ReversalPlan.irreversible` must be constructible only with a warning string.**
Account merges and hard deletes are permanent (spec, Pages 6 and 7); the type
forces the warning to exist.

---

## 5.6 Resolution and dismissal

```swift
struct Resolution: Hashable, Codable, Sendable {
    let action: ProposedActionID
    let outcome: ResolutionOutcome
    let resolvedBy: String
    let resolvedAt: Date
    let note: String?
    let activityLogEntryID: ActivityLogEntryID     // §10 — always linked
}

enum ResolutionOutcome: Hashable, Codable, Sendable {
    case writeConfirmed(entityID: String, newSyncToken: String)
    case writeFailed(fault: QBOFault)
    case writeUnknown(intentID: IntentID)          // §10 — timed out; needs a probe
    case manualCompletionAttested(procedure: GuidedProcedure, at: Date)
    case dismissed(DismissalReason)
    case clientAnswered(answer: String, at: Date)
}

enum DismissalReason: String, Codable, Sendable {
    case notADuplicate
    case intentionalDuplicate           // two real withdrawals occurred
    case alreadyCorrectedInQBO
    case immaterial
    case clientConfirmedCorrect
    case ruleFalsePositive              // feeds §8's rule-quality metrics
    case deferredToNextPeriod
}
```

**`writeUnknown` is a first-class outcome, not an error.** §10 requires that a
timed-out POST is never blindly retried, which means "we don't know" must be a
representable state that survives an app restart. Omitting it forces callers to
guess, and guessing here means double-voiding a transaction.

**`DismissalReason.intentionalDuplicate` feeds client memory.** Per spec, memory
is learned *with approval* — dismissing with this reason offers, but never
assumes, a rule ("always treat matching Odessa Water charges as separate").

---

## 5.7 Color is derived, never stored

```swift
enum FindingColor: String, Sendable {
    case green        // checked and passed
    case yellow       // human review needed
    case red          // urgent or material risk
    case blue         // recommendation or opportunity
    case purple       // waiting on client
    case gray         // not checked, stale, or unavailable
    case grayOutlined // requires import or manual QBO step — not yet actionable
}
```

Findings themselves are never green: a finding *is* an exception. Green is a
property of a **check** (§8's `.pass`) and of a **page** (§6), which is why
`Finding` has no color field and why the derivation lives on those types instead.

```swift
extension CheckResult {
    /// CLAUDE.md rule 5, encoded once, in one place.
    var color: FindingColor {
        guard connectionHealthy else { return .gray }        // spec: no green under a red connection
        switch outcome {
        case .cannotEvaluate(let reason):
            return reason.requiresImportOrManualStep ? .grayOutlined : .gray
        case .pass(let coverage, let freshness):
            guard coverage == .complete, freshness == .current else { return .gray }
            return .green                                     // the ONLY path to green
        case .findings(let findings):
            if findings.contains(where: { $0.status == .awaitingClient }) { return .purple }
            if findings.contains(where: { $0.severity >= .high })         { return .red }
            if findings.allSatisfy({ $0.severity == .informational })     { return .blue }
            return .yellow
        }
    }
}
```

**There is exactly one `return .green` in the codebase, and it is guarded by four
conditions** — connection healthy, check completed, coverage complete, result
current. A lint rule asserts no other construction site for `.green` exists.
This is `CLAUDE.md` rule 5 made mechanical: "green means verified, not merely
nothing found."

---

## 5.8 Generated prose — always labeled, always separable

```swift
struct GeneratedProse: Hashable, Codable, Sendable {
    let text: String
    let model: String                     // per-task configurable (spec)
    let promptVersion: PromptVersion
    let generatedAt: Date
    let label: ProseLabel                 // rendered visibly, always
    let citedValues: [CitedValue]         // numbers referenced, with their rule source
}

enum ProseLabel: String, Codable, Sendable {
    case draft, guidance
}

/// A number Claude referenced, bound to the rule that computed it.
struct CitedValue: Hashable, Codable, Sendable {
    let label: String
    let value: Money
    let computedBy: RuleID
}
```

**`citedValues` is the enforcement mechanism for "if a question asks for a
number, Claude cites the deterministic value the rules engine already computed"**
(spec). Structured output returns citations as references into the fact packet;
a post-check verifies every currency-shaped string in the generated text appears
in `citedValues`. A number in the prose that the engine did not compute is a
**hard failure** — the prose is discarded and the finding renders without an
explanation rather than with a fabricated figure.

That check is cheap, deterministic, and closes the largest remaining gap in
`CLAUDE.md` rule 1: not "we asked Claude not to calculate," but "prose containing
an uncomputed number cannot render."
