import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 6 (Type A + C), duplicate-candidate
/// detection slice: "reads accounts; detects duplicate-account candidates;
/// prepares a merge plan." **The merge plan and account create/rename/
/// deactivate writes are NOT built here** — merges stay manual on purpose
/// (spec: "Merges are permanent, can silently lose reconciliation history,
/// require matching account/detail types, and cannot be undone"), so this
/// is read-only detection + a guided QBO procedure, the same Type C
/// resolution shape as `VL-DUP-EXP-001`'s Branch B.
///
/// **Matching is `FullyQualifiedName`, never leaf `Name`.**
/// `VL-COA-DUPACCT-001`'s investigation (`docs/phase-0/08_RULE_ENGINE.md`
/// §8.8) found naive leaf-name matching on real sandbox data produced 8
/// false-positive pairs — QBO's own industry-template pattern reuses the
/// same leaf name for a legitimate Income account and a matching COGS/
/// Expense sub-account under different parents, and can equally reuse a
/// leaf name across two genuinely different sub-categories of the same
/// type (e.g. two different "Repairs" accounts under different parents).
/// `FullyQualifiedName` carries the full parent path, which distinguishes
/// both cases. See `QBORawAccount.fullyQualifiedName`'s doc comment for why
/// that field is not yet spike-verified present in this sandbox's response
/// — accounts missing it are excluded from detection entirely, never
/// silently compared on leaf name as a fallback.
public struct DuplicateAccountCandidateGroup: Identifiable, Sendable {
    public let id: String
    public let accounts: [LedgerAccount]

    public init(accounts: [LedgerAccount]) {
        self.accounts = accounts.sorted { $0.id < $1.id }
        self.id = self.accounts.map(\.id).joined(separator: "-")
    }
}

public enum ChartOfAccountsCleanup {
    /// Lowercase, strip whitespace and punctuation — the same normalization
    /// `DuplicateVendorRule.normalize` uses, minus the business-entity-
    /// suffix stripping (account names don't carry "Inc"/"LLC" suffixes).
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        s = s.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
        return s.replacingOccurrences(of: " ", with: "")
    }

    /// Groups accounts sharing the same `accountType`, `accountSubType`,
    /// and normalized `fullyQualifiedName` — a group of 2+ under this exact
    /// definition is a candidate for the same QBO ledger slot duplicated,
    /// not a coincidental name collision.
    public static func findDuplicateCandidates(_ accounts: [LedgerAccount]) -> [DuplicateAccountCandidateGroup] {
        struct Key: Hashable {
            let accountType: LedgerAccountType
            let accountSubType: String?
            let normalizedFullyQualifiedName: String
        }
        var byKey: [Key: [LedgerAccount]] = [:]
        for account in accounts {
            guard let fqn = account.fullyQualifiedName else { continue }
            let normalized = normalize(fqn)
            guard !normalized.isEmpty else { continue }
            let key = Key(accountType: account.accountType, accountSubType: account.accountSubType, normalizedFullyQualifiedName: normalized)
            byKey[key, default: []].append(account)
        }
        return byKey.values
            .filter { $0.count > 1 }
            .map { DuplicateAccountCandidateGroup(accounts: $0) }
            .sorted { $0.id < $1.id }
    }
}
