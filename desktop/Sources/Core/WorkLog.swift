import Foundation

/// "Bookkeeping work completed" for the monthly client report (owner
/// request 2026-09-29): one row per discrepancy the bookkeeper acted on —
/// what was found, what was done (the note entered at "Verify Fixed" or
/// "Dismiss"), who and when, which month's books it affected, whether QBO
/// confirmed it, and its effect on the reported numbers. The history is
/// never deleted; a written note alone never counts as "verified".
public struct WorkItem: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case correctedVerified, awaitingVerification, awaitingClient, notAnError
    }

    public let findingID: String
    public let title: String
    public let found: String
    public let action: String
    public let doneBy: String
    public let doneAtLabel: String
    public let affectedPeriodLabel: String
    public let status: Status
    public let statusLabel: String
    public let impact: String
    public let amountText: String
}

public enum WorkLog {
    static let actionKinds: Set<ActivityKind> = [.manualCompletionAttested, .findingDismissed, .apiWriteApplied, .findingResolved]

    /// Work affecting `period`'s books, or recorded during `period`.
    public static func items(activityLog: [ActivityLogEntry], findings: [Finding], period: AccountingPeriod) -> [WorkItem] {
        let findingsByID = Dictionary(findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = activityLog.filter { actionKinds.contains($0.kind) && $0.findingID != nil }
        let grouped = Dictionary(grouping: entries) { $0.findingID! }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateStyle = .medium

        var items: [(Date, WorkItem)] = []
        for (findingID, history) in grouped {
            guard let finding = findingsByID[findingID] else { continue }
            let sorted = history.sorted { $0.recordedAt < $1.recordedAt }
            let human = sorted.last { $0.kind != .findingResolved } ?? sorted.last!
            let recorded = AccountingDate(date: human.recordedAt)
            guard finding.period == period || period.contains(recorded) else { continue }

            let note = human.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status: WorkItem.Status
            switch finding.status {
            case .resolved: status = .correctedVerified
            case .dismissed: status = .notAnError
            default:
                if human.kind == .apiWriteApplied { status = .correctedVerified }
                else if note.hasPrefix(ResolutionType.clientClarificationNeeded.label) { status = .awaitingClient }
                else { status = .awaitingVerification }
            }
            let actor: String = {
                if case .user(let name) = human.actor { return name }
                return "Voice Ledger"
            }()
            items.append((human.recordedAt, WorkItem(
                findingID: findingID,
                title: finding.title,
                found: finding.narrative ?? finding.title,
                action: note.isEmpty ? (human.kind == .apiWriteApplied ? "Applied the approved fix to QuickBooks" : "No note recorded") : note,
                doneBy: actor,
                doneAtLabel: dateFormatter.string(from: human.recordedAt),
                affectedPeriodLabel: "\(MonthlyReportBuilder.monthNames[finding.period.month - 1]) \(finding.period.year)",
                status: status,
                statusLabel: label(status),
                impact: impact(ruleID: finding.ruleID.rawValue, amount: finding.dollarExposure, status: status),
                amountText: finding.dollarExposure.accountingDescription
            )))
        }
        return items.sorted { $0.0 > $1.0 }.map(\.1)
    }

    public static func label(_ status: WorkItem.Status) -> String {
        switch status {
        case .correctedVerified: return "Corrected and verified"
        case .awaitingVerification: return "Awaiting verification"
        case .awaitingClient: return "Awaiting client"
        case .notAnError: return "Not an error"
        }
    }

    /// The effect on the reported numbers — deliberately separate from
    /// business performance: fixing the books changes what's reported, it
    /// doesn't earn or recover money.
    public static func impact(ruleID: String, amount: Money, status: WorkItem.Status) -> String {
        let a = amount.accountingDescription
        switch status {
        case .notAnError: return "No change to the numbers — reviewed and confirmed as valid."
        case .awaitingVerification: return "Not yet confirmed in QuickBooks; numbers unchanged until it is."
        case .awaitingClient: return "Waiting on the client's answer; numbers unchanged for now."
        case .correctedVerified: break
        }
        switch ruleID {
        case "VL-DUP-INV-001":
            return "Revenue was overstated by \(a); removing the duplicate lowers reported revenue. No cash was affected."
        case "VL-DUP-PAY-001":
            return "Customer payments were overstated by \(a); removing the duplicate corrects receivables. No cash was affected."
        case "VL-DUP-EXP-001", "VL-DUP-EXP-002", "VL-DUP-BILL-001", "VL-DUP-NEAR-001":
            return "Expenses were overstated by \(a); removing the duplicate raises reported profit by that amount. No cash was recovered."
        case "VL-DUP-VEND-001":
            return "Merged duplicate vendor records so spending by vendor is accurate. Totals unchanged."
        case "VL-PERSONAL-001":
            return "Separated \(a) of owner/personal activity from business expenses."
        case "VL-CAT-UNCAT-001", "VL-CAT-MISCODE-001", "VL-CC-PAYMENT-001", "VL-PAYROLL-LUMP-001", "VL-VENDOR-MISMATCH-001", "VL-MISSING-PAYEE-001", "VL-TRANSPOSITION-001":
            return "Moved \(a) to the correct account; category totals are now accurate. Total profit may be unchanged."
        case "VL-BS-UNDEP-001":
            return "Recorded the \(a) deposit; the bank balance now reflects money actually received."
        case "VL-VENDCREDIT-UNAPPLIED-001":
            return "Applied a \(a) vendor credit; amounts owed to vendors are now accurate."
        case "VL-RECON-MISSING-001", "VL-RECON-AMBIGUOUS-001", "VL-RECON-DIFF-001", "VL-FORCED-RECON-001":
            return "Brought the books in line with the bank statement (\(a)); the bank balance can now be relied on."
        default:
            if ruleID.hasPrefix("VL-BS-") || ruleID == "VL-OBE-BALANCE-001" || ruleID == "VL-REPORT-TIE-001" {
                return "Corrected a \(a) balance sheet misstatement; balances now reflect what the business actually has and owes."
            }
            return "Corrected in the books (\(a))."
        }
    }
}
