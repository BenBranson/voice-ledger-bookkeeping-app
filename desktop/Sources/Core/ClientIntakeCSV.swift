import Foundation

/// The column mapping for the intake roster file — a single CSV the
/// bookkeeper can open directly in Google Sheets or Excel, per explicit
/// request. Lives in Core, next to `ClientIntake` itself, so the export
/// side and the parse side can never drift apart (a column added to one
/// without the other would be a compile-time-invisible bug otherwise).
///
/// Actual CSV text encode/decode (quoting, line splitting) is deliberately
/// NOT here — that's `Exporting.CSVReportExporter` (writing) and
/// `IntegrationsImports.CSVParser` (reading), both of which Core must
/// never depend on. This type only maps a `ClientIntake` to/from a plain
/// `[String: String]` row-by-column-name — parsing by NAME, not position,
/// since the whole point of a hand-editable file is that a column could
/// get reordered (or a new one added) by whoever's editing it in Sheets.
public enum ClientIntakeCSV {
    public static let columns: [String] = [
        "id", "savedAt",
        "legalBusinessName", "entityType", "industry", "primaryRevenueSources", "yearsInBusiness",
        "accountingSoftware", "bankAccountCountAnswer", "creditCardCountAnswer", "monthlyTransactionCountAnswer",
        "booksUpToDateAnswer", "whoManagesARAP", "paymentProcessors",
        "pointOfContactName", "pointOfContactRole", "pointOfContactEmail", "pointOfContactPhone", "communicationPreference",
        "frustrations", "desiredMetrics", "financialsUse",
        "hourlyRateText", "volumeTier",
        "payrollProcessing", "salesTaxManagement", "multipleBankAccounts", "inventoryTracking",
        "needsCleanup", "monthsBehind",
        "multipleUncategorized", "personalBusinessMixed", "payrollNotReconciled", "salesTaxNotFiled", "inventoryTrackingIssues", "negativeBalances", "duplicatedAccounts",
        "includeFindingsSummary",
        // Informational only — recomputed from the fields above on load,
        // never trusted as input. Present so a human skimming the file in
        // Sheets sees the quote without opening the app.
        "monthlyInvestment"
    ]

    /// A fresh formatter per call, not a shared `static let` — `Codable`'s
    /// synthesized `Sendable`-checking (Swift 6 strict concurrency) flags
    /// `ISO8601DateFormatter` as non-`Sendable` shared mutable state; a
    /// throwaway local instance sidesteps that without needing a lock or
    /// an actor for what's a cheap, infrequent (per-save) formatting call.
    private static var isoFormatter: ISO8601DateFormatter { ISO8601DateFormatter() }

    public static func fields(for intake: ClientIntake) -> [String: String] {
        [
            "id": intake.id,
            "savedAt": isoFormatter.string(from: intake.savedAt),
            "legalBusinessName": intake.legalBusinessName,
            "entityType": intake.entityType,
            "industry": intake.industry,
            "primaryRevenueSources": intake.primaryRevenueSources,
            "yearsInBusiness": intake.yearsInBusiness,
            "accountingSoftware": intake.accountingSoftware,
            "bankAccountCountAnswer": intake.bankAccountCountAnswer,
            "creditCardCountAnswer": intake.creditCardCountAnswer,
            "monthlyTransactionCountAnswer": intake.monthlyTransactionCountAnswer,
            "booksUpToDateAnswer": intake.booksUpToDateAnswer,
            "whoManagesARAP": intake.whoManagesARAP,
            "paymentProcessors": intake.paymentProcessors,
            "pointOfContactName": intake.pointOfContactName,
            "pointOfContactRole": intake.pointOfContactRole,
            "pointOfContactEmail": intake.pointOfContactEmail,
            "pointOfContactPhone": intake.pointOfContactPhone,
            "communicationPreference": intake.communicationPreference,
            "frustrations": intake.frustrations,
            "desiredMetrics": intake.desiredMetrics,
            "financialsUse": intake.financialsUse,
            "hourlyRateText": intake.hourlyRateText,
            "volumeTier": String(intake.volumeTier.rawValue),
            "payrollProcessing": bool(intake.monthlyFlags.payrollProcessing),
            "salesTaxManagement": bool(intake.monthlyFlags.salesTaxManagement),
            "multipleBankAccounts": bool(intake.monthlyFlags.multipleBankAccounts),
            "inventoryTracking": bool(intake.monthlyFlags.inventoryTracking),
            "needsCleanup": bool(intake.needsCleanup),
            "monthsBehind": String(intake.monthsBehind.rawValue),
            "multipleUncategorized": bool(intake.cleanupIssues.multipleUncategorized),
            "personalBusinessMixed": bool(intake.cleanupIssues.personalBusinessMixed),
            "payrollNotReconciled": bool(intake.cleanupIssues.payrollNotReconciled),
            "salesTaxNotFiled": bool(intake.cleanupIssues.salesTaxNotFiled),
            "inventoryTrackingIssues": bool(intake.cleanupIssues.inventoryTrackingIssues),
            "negativeBalances": bool(intake.cleanupIssues.negativeBalances),
            "duplicatedAccounts": bool(intake.cleanupIssues.duplicatedAccounts),
            "includeFindingsSummary": bool(intake.includeFindingsSummary),
            "monthlyInvestment": intake.monthlyQuote.monthlyInvestment.description
        ]
    }

    /// `nil` only when the row has no usable `id` at all (a genuinely
    /// blank/malformed line) — every other missing or unparseable column
    /// falls back to that field's own default rather than failing the
    /// whole row, since a hand-edited spreadsheet will have typos.
    public static func intake(from fields: [String: String]) -> ClientIntake? {
        guard let id = fields["id"], !id.isEmpty else { return nil }
        return ClientIntake(
            id: id,
            savedAt: fields["savedAt"].flatMap { isoFormatter.date(from: $0) } ?? Date(),
            legalBusinessName: fields["legalBusinessName"] ?? "",
            entityType: fields["entityType"] ?? "",
            industry: fields["industry"] ?? "",
            primaryRevenueSources: fields["primaryRevenueSources"] ?? "",
            yearsInBusiness: fields["yearsInBusiness"] ?? "",
            accountingSoftware: fields["accountingSoftware"] ?? "",
            bankAccountCountAnswer: fields["bankAccountCountAnswer"] ?? "",
            creditCardCountAnswer: fields["creditCardCountAnswer"] ?? "",
            monthlyTransactionCountAnswer: fields["monthlyTransactionCountAnswer"] ?? "",
            booksUpToDateAnswer: fields["booksUpToDateAnswer"] ?? "",
            whoManagesARAP: fields["whoManagesARAP"] ?? "",
            paymentProcessors: fields["paymentProcessors"] ?? "",
            pointOfContactName: fields["pointOfContactName"] ?? "",
            pointOfContactRole: fields["pointOfContactRole"] ?? "",
            pointOfContactEmail: fields["pointOfContactEmail"] ?? "",
            pointOfContactPhone: fields["pointOfContactPhone"] ?? "",
            communicationPreference: fields["communicationPreference"] ?? "",
            frustrations: fields["frustrations"] ?? "",
            desiredMetrics: fields["desiredMetrics"] ?? "",
            financialsUse: fields["financialsUse"] ?? "",
            hourlyRateText: fields["hourlyRateText"] ?? "100",
            volumeTier: fields["volumeTier"].flatMap { Int($0) }.flatMap(PricingCalculator.VolumeTier.init(rawValue:)) ?? .light,
            monthlyFlags: .init(
                payrollProcessing: parseBool(fields["payrollProcessing"]),
                salesTaxManagement: parseBool(fields["salesTaxManagement"]),
                multipleBankAccounts: parseBool(fields["multipleBankAccounts"]),
                inventoryTracking: parseBool(fields["inventoryTracking"])
            ),
            needsCleanup: parseBool(fields["needsCleanup"]),
            monthsBehind: fields["monthsBehind"].flatMap { Int($0) }.flatMap(PricingCalculator.MonthsBehindTier.init(rawValue:)) ?? .threeToSix,
            cleanupIssues: .init(
                multipleUncategorized: parseBool(fields["multipleUncategorized"]),
                personalBusinessMixed: parseBool(fields["personalBusinessMixed"]),
                payrollNotReconciled: parseBool(fields["payrollNotReconciled"]),
                salesTaxNotFiled: parseBool(fields["salesTaxNotFiled"]),
                inventoryTrackingIssues: parseBool(fields["inventoryTrackingIssues"]),
                negativeBalances: parseBool(fields["negativeBalances"]),
                duplicatedAccounts: parseBool(fields["duplicatedAccounts"])
            ),
            includeFindingsSummary: fields["includeFindingsSummary"].map(parseBool) ?? true
        )
    }

    private static func bool(_ value: Bool) -> String { value ? "true" : "false" }
    private static func parseBool(_ value: String?) -> Bool { value?.trimmingCharacters(in: .whitespaces).lowercased() == "true" }
}
