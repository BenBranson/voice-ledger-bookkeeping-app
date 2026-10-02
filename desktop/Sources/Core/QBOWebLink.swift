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

    /// A transaction by its entity kind (for card rows).
    public static func transaction(id: String, kind: QBOEntityKind, isSandbox: Bool) -> URL? {
        guard let route = route(for: kind) else { return nil }
        return URL(string: "\(base(isSandbox: isSandbox))/\(route)?txnId=\(id)")
    }

    public static func url(forRecordID id: String, transactions: [LedgerTransaction], accounts: [LedgerAccount], isSandbox: Bool) -> URL? {
        let base = base(isSandbox: isSandbox)
        if let account = accounts.first(where: { $0.id == id }) {
            // Owner rule 2026-10-02: a link opens the exact record or nothing.
            // Income/expense accounts have no register in QBO, and the chart
            // of accounts is a general page, so they get no link here.
            guard account.accountType.isAssetOrLiability || account.accountType == .equity else { return nil }
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

    /// A vendor's page in QBO (their transactions and open balance).
    public static func vendor(id: String, isSandbox: Bool) -> URL? {
        URL(string: "\(base(isSandbox: isSandbox))/vendordetail?nameId=\(id)")
    }

    /// A customer's page in QBO (their invoices, payments and open balance).
    public static func customer(id: String, isSandbox: Bool) -> URL? {
        URL(string: "\(base(isSandbox: isSandbox))/customerdetail?nameId=\(id)")
    }

    /// A transaction by the type name QBO's own reports print in their
    /// Transaction Type column ("Expense", "Bill", "Invoice", ...).
    public static func transaction(id: String, reportTypeName: String?, isSandbox: Bool) -> URL? {
        let route: String?
        switch (reportTypeName ?? "").lowercased() {
        case "expense", "check", "credit card expense", "cash expense", "credit card credit": route = "expense"
        case "bill": route = "bill"
        case "invoice": route = "invoice"
        case "payment": route = "recvpayment"
        case let t where t.hasPrefix("bill payment"): route = "billpayment"
        case "journal entry": route = "journal"
        case "vendor credit": route = "vendorcredit"
        case "deposit": route = "deposit"
        case "transfer": route = "transfer"
        case "sales receipt": route = "salesreceipt"
        case "credit memo": route = "creditmemo"
        case "refund", "refund receipt": route = "refundreceipt"
        default: route = nil
        }
        guard let route, !id.isEmpty else { return nil }
        return URL(string: "\(base(isSandbox: isSandbox))/\(route)?txnId=\(id)")
    }

    public static func salesTaxCenter(isSandbox: Bool) -> URL {
        URL(string: "\(base(isSandbox: isSandbox))/salestax")!
    }
}
