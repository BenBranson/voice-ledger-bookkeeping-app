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
/// else `.manualQBO`/`.stagedAPI` already requires. **Not built**: the
/// "answer attached permanently to the finding" half — persisting a
/// client's reply and associating it with the finding needs a real
/// two-way channel (email, a client portal) this app has none of yet, and
/// a schema decision about whether that lives on `Finding` itself or a
/// separate record. Recording that a question WAS drafted and sent is
/// covered by `ActivityKind.clientQuestionDrafted` in the Activity Log —
/// that's the extent of what's tracked today.
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
        lines.append("\(finding.title) — \(finding.dollarExposure.description)")
        if let principle = ruleIdentity?.accountingPrinciple {
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
