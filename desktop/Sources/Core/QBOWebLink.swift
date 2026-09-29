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

    public static func url(for finding: Finding, transactions: [LedgerTransaction], accounts: [LedgerAccount], isSandbox: Bool) -> URL? {
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
