import Foundation

/// Browser links straight to the QBO record behind a finding (owner request
/// 2026-09-29). Navigation only, never a write. QBO opens whichever company
/// the browser is signed into, and these paths are QBO's web routes as
/// commonly documented — owner-verified, not API-verified.
public enum QBOWebLink {
    public static func base(isSandbox: Bool) -> String {
        isSandbox ? "https://app.sandbox.qbo.intuit.com/app" : "https://app.qbo.intuit.com/app"
    }

    static func route(for kind: QBOEntityKind) -> String? {
        switch kind {
        case .purchase: return "expense"
        case .bill: return "bill"
        case .invoice: return "invoice"
        case .payment: return "recvpayment"
        case .billPayment: return "billpayment"
        case .journalEntry: return "journal"
        case .vendorCredit: return "vendorcredit"
        default: return nil
        }
    }

    public static func url(forRecordID id: String, transactions: [LedgerTransaction], accounts: [LedgerAccount], isSandbox: Bool) -> URL? {
        let base = base(isSandbox: isSandbox)
        if let account = accounts.first(where: { $0.id == id }) {
            guard account.accountType.isAssetOrLiability || account.accountType == .equity else {
                return URL(string: "\(base)/chartofaccounts")
            }
            return URL(string: "\(base)/register?accountId=\(account.id)")
        }
        guard let txn = transactions.first(where: { $0.id == id }), case .qboAPI = txn.provenance,
              let route = route(for: txn.entityKind) else { return nil }
        return URL(string: "\(base)/\(route)?txnId=\(txn.id)")
    }

    /// Rules whose fix is entering a NEW transaction by hand in QBO (a bank
    /// line with nothing posted for it). Owner decision 2026-09-29: scanned
    /// or imported figures never go into QBO automatically — Voice Ledger
    /// links to QBO's own entry form and the bookkeeper types it in.
    public static let manualEntryRules: Set<String> = ["VL-RECON-MISSING-001"]

    public static let accountEvidenceRules: Set<String> = [
        "VL-BS-NEGBAL-001", "VL-OBE-BALANCE-001", "VL-BS-SUSPENSE-001", "VL-BS-EQUITY-DR-001", "VL-RECON-DIFF-001"
    ]

    /// QBO's blank "new expense" form.
    public static func newExpense(isSandbox: Bool) -> URL { URL(string: "\(base(isSandbox: isSandbox))/expense")! }

    /// QBO's Banking page, where the bank feed's "For Review" queue lives.
    public static func bankFeed(isSandbox: Bool) -> URL { URL(string: "\(base(isSandbox: isSandbox))/banking")! }

    public static func url(for finding: Finding, transactions: [LedgerTransaction], accounts: [LedgerAccount], isSandbox: Bool) -> URL? {
        if manualEntryRules.contains(finding.ruleID.rawValue) { return newExpense(isSandbox: isSandbox) }
        // These rules' evidence ID is always a QBO Account ID, so the
        // register link works even before this session's sync has loaded
        // the chart of accounts (owner screenshot 2026-09-29).
        if accountEvidenceRules.contains(finding.ruleID.rawValue), let id = finding.evidence.first?.transactionID, id.allSatisfy(\.isNumber) {
            return URL(string: "\(base(isSandbox: isSandbox))/register?accountId=\(id)")
        }
        for item in finding.evidence {
            if let url = url(forRecordID: item.transactionID, transactions: transactions, accounts: accounts, isSandbox: isSandbox) {
                return url
            }
        }
        return nil
    }

    public static func salesTaxCenter(isSandbox: Bool) -> URL {
        URL(string: "\(base(isSandbox: isSandbox))/salestax")!
    }
}
