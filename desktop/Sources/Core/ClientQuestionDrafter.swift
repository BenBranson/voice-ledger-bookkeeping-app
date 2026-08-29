import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit section: "Client Question
/// Builder — turns an uncertain finding into a ready-to-send client
/// question, answer attached permanently to the finding." **This is the
/// drafting half only.** The template is deterministic string
/// interpolation over fields the `Finding` and its rule's `RuleIdentity`
/// already carry — no invented content, no Claude call (none exists in
/// this app yet). It is explicitly a starting draft: the UI that calls
/// this always shows the result in an editable field before anything is
/// recorded or sent, same "review before it's real" posture as everything
/// else `.manualQBO`/`.stagedAPI` already requires. **Answer-recording
/// built 2026-08-28** (`AppState.recordClientQuestionAnswer`,
/// `ActivityKind.clientQuestionAnswered`): still no real two-way channel
/// (email, a client portal) — the bookkeeper types in what the client
/// said, the same "recorded, not verified by the app" posture
/// `attestCompletion` already has. Attached to the finding by `findingID`
/// on the Activity Log entry, the same mechanism `.clientQuestionDrafted`
/// already uses, not a separate schema — a real two-way integration later
/// would replace how the answer TEXT arrives, not where it's recorded.
public enum ClientQuestionDrafter {
    /// `clientName` is optional and never inferred — the caller passes
    /// whatever they already know (or nothing), rather than this function
    /// guessing at a name from vendor or company data that means something
    /// different.
    public static func draft(finding: Finding, clientName: String?) -> String {
        let ruleIdentity = RuleRegistry.all.first { $0.identity.id == finding.ruleID }?.identity
        let periodLabel = "\(finding.period.year)-\(String(format: "%02d", finding.period.month))"

        var lines: [String] = []
        lines.append("Hi\(clientName.map { " \($0)" } ?? ""),")
        lines.append("")
        lines.append("While reviewing your books for \(periodLabel), I found something I'd like to confirm with you before making any changes:")
        lines.append("")
        // Gauntlet Loop, Gauntlet B round 3 critic pass (2026-08-23): some
        // rules' titles (e.g. VL-DUP-EXP-001, since its own Gauntlet B pass)
        // already embed the dollar figure — appending it again produced a
        // literal duplicate ("...USD 486.20 — USD 486.20") in the drafted
        // email. Append only when the title doesn't already carry it.
        let exposureText = finding.dollarExposure.description
        lines.append(finding.title.contains(exposureText) ? finding.title : "\(finding.title) — \(exposureText)")
        // Gauntlet Loop, Gauntlet B round 3 critic pass (2026-08-23): prefer
        // the rule's tier-aware, transaction-specific `narrative` over the
        // rule-level (tier-invariant) `accountingPrinciple` when available.
        // `accountingPrinciple` is written once per rule and can describe
        // fields a specific tier never actually checked — confirmed live for
        // VL-DUP-EXP-001's T2 (reference-number match), whose
        // `accountingPrinciple` mentions "date, and payment account" even
        // though T2 checks neither, meaning the OLD drafted text stated a
        // match to the client that didn't happen. `narrative` also names
        // real transaction dates/amounts, giving the client something to
        // identify which two postings are being asked about — the title +
        // dollar figure alone can't, since every match in a duplicate-style
        // rule already requires equal amounts. Falls back to
        // `accountingPrinciple` for the other 16 rules that haven't been
        // given a `narrative` yet — no change to their drafted text.
        if let narrative = finding.narrative {
            lines.append("")
            lines.append(narrative)
        } else if let principle = ruleIdentity?.accountingPrinciple {
            lines.append("")
            lines.append("Why this matters: \(principle)")
        }
        lines.append("")
        lines.append("Could you confirm whether this is correct as recorded, or let me know if it should be handled differently?")
        lines.append("")
        lines.append("Thanks,")

        return lines.joined(separator: "\n")
    }
}
