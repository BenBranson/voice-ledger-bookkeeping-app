import Foundation
import CryptoKit

/// Client engagement agreement (owner request 2026-09-29): generated from a
/// saved intake and the agreed price, read and signed by the client.
///
/// Every clause comes from this fixed, versioned template — never from an
/// AI — so two agreements with the same inputs are word-for-word identical,
/// and the `documentID` (SHA-256 of the full text) proves which text a
/// client signed. Scope is derived from the intake's pricing choices: an
/// add-on the client is paying for is listed as included; anything not
/// paid for is listed as excluded.

public struct FirmProfile: Codable, Sendable, Equatable {
    public var firmName: String
    public var ownerName: String
    public var ownerTitle: String
    public var city: String
    public var state: String
    public var county: String
    public var email: String
    public var phone: String

    public init(firmName: String = "Benjamin Branson Bookkeeping", ownerName: String = "Benjamin Branson", ownerTitle: String = "Owner",
                city: String = "Odessa", state: String = "Texas", county: String = "Ector County",
                email: String = "benjamin@benjaminbransonbookkeeping.com", phone: String = "432-231-3049") {
        self.firmName = firmName
        self.ownerName = ownerName
        self.ownerTitle = ownerTitle
        self.city = city
        self.state = state
        self.county = county
        self.email = email
        self.phone = phone
    }
}

public struct AgreementClient: Codable, Sendable, Equatable {
    public var legalName: String
    public var entityType: String
    public var contactName: String
    public var contactTitle: String
    public var contactEmail: String
    public var contactPhone: String
    public var paymentProcessors: String

    public init(legalName: String = "", entityType: String = "", contactName: String = "", contactTitle: String = "", contactEmail: String = "", contactPhone: String = "", paymentProcessors: String = "") {
        self.legalName = legalName
        self.entityType = entityType
        self.contactName = contactName
        self.contactTitle = contactTitle
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.paymentProcessors = paymentProcessors
    }
}

public enum EngagementPackage: String, Codable, Sendable, CaseIterable, Identifiable {
    case monthly, monthlyAndCleanup, cleanupOnly
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .monthly: return "Standard Monthly Retainer"
        case .monthlyAndCleanup: return "Monthly Retainer + Historical Clean-Up"
        case .cleanupOnly: return "Historical Clean-Up Only"
        }
    }
    public var includesMonthly: Bool { self != .cleanupOnly }
    public var includesCleanup: Bool { self != .monthly }
}

public enum CleanupPaymentSchedule: String, Codable, Sendable, CaseIterable, Identifiable {
    case fullAtSigning, halfAndHalf
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fullAtSigning: return "100% due at signing"
        case .halfAndHalf: return "50% at signing, 50% on completion"
        }
    }
}

public struct AgreementTerms: Codable, Sendable, Equatable {
    public var package: EngagementPackage
    public var effectiveDate: AccountingDate
    public var monthlyFee: Money
    public var cleanupFee: Money
    public var hourlyRate: Money
    public var cleanupPayment: CleanupPaymentSchedule
    public var cleanupMonthsLabel: String
    public var cleanupKnownIssues: [String]
    public var bankAccounts: Int
    public var creditCards: Int
    public var volumeTierLabel: String
    public var payrollSupport: Bool
    public var salesTaxSupport: Bool
    public var inventorySupport: Bool
    public var billingDay: Int
    public var reportBusinessDay: Int
    public var statementsDueDay: Int
    public var responseBusinessDays: Int
    public var noticeDays: Int
    public var liabilityCapMonths: Int
    public var latePauseDays: Int

    public init(package: EngagementPackage = .monthly, effectiveDate: AccountingDate, monthlyFee: Money = .zero, cleanupFee: Money = .zero, hourlyRate: Money = Money(minorUnits: 10_000, currency: .usd),
                cleanupPayment: CleanupPaymentSchedule = .halfAndHalf, cleanupMonthsLabel: String = "", cleanupKnownIssues: [String] = [],
                bankAccounts: Int = 2, creditCards: Int = 2, volumeTierLabel: String = "Under 200",
                payrollSupport: Bool = false, salesTaxSupport: Bool = false, inventorySupport: Bool = false,
                billingDay: Int = 1, reportBusinessDay: Int = 15, statementsDueDay: Int = 5, responseBusinessDays: Int = 3,
                noticeDays: Int = 30, liabilityCapMonths: Int = 3, latePauseDays: Int = 10) {
        self.package = package
        self.effectiveDate = effectiveDate
        self.monthlyFee = monthlyFee
        self.cleanupFee = cleanupFee
        self.hourlyRate = hourlyRate
        self.cleanupPayment = cleanupPayment
        self.cleanupMonthsLabel = cleanupMonthsLabel
        self.cleanupKnownIssues = cleanupKnownIssues
        self.bankAccounts = bankAccounts
        self.creditCards = creditCards
        self.volumeTierLabel = volumeTierLabel
        self.payrollSupport = payrollSupport
        self.salesTaxSupport = salesTaxSupport
        self.inventorySupport = inventorySupport
        self.billingDay = billingDay
        self.reportBusinessDay = reportBusinessDay
        self.statementsDueDay = statementsDueDay
        self.responseBusinessDays = responseBusinessDays
        self.noticeDays = noticeDays
        self.liabilityCapMonths = liabilityCapMonths
        self.latePauseDays = latePauseDays
    }
}

public struct EngagementAgreement: Codable, Sendable, Equatable {
    public var firm: FirmProfile
    public var client: AgreementClient
    public var terms: AgreementTerms
    /// The intake this agreement was built from, when there is one.
    public var intakeID: String?

    public init(firm: FirmProfile, client: AgreementClient, terms: AgreementTerms, intakeID: String? = nil) {
        self.firm = firm
        self.client = client
        self.terms = terms
        self.intakeID = intakeID
    }

    /// Builds the agreement from a saved intake: contact details, the
    /// quoted monthly fee, the cleanup midpoint as the fixed project fee,
    /// the add-ons the client is paying for, and the account counts.
    public static func from(intake: ClientIntake, firm: FirmProfile = FirmProfile(), effectiveDate: AccountingDate) -> EngagementAgreement {
        func count(_ answer: String, default value: Int) -> Int {
            let digits = answer.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
            return digits.map { max(1, $0) } ?? value
        }
        let issues = intake.cleanupIssues
        let known: [String] = [
            issues.multipleUncategorized ? "Uncategorized transactions" : nil,
            issues.personalBusinessMixed ? "Personal and business activity mixed together" : nil,
            issues.payrollNotReconciled ? "Payroll accounts not reconciled" : nil,
            issues.salesTaxNotFiled ? "Sales tax liability accounts not reconciled" : nil,
            issues.inventoryTrackingIssues ? "Inventory records inconsistent with the books" : nil,
            issues.negativeBalances ? "Accounts carrying negative balances" : nil,
            issues.duplicatedAccounts ? "Duplicated accounts in the chart of accounts" : nil
        ].compactMap { $0 }
        let terms = AgreementTerms(
            package: intake.needsCleanup ? .monthlyAndCleanup : .monthly,
            effectiveDate: effectiveDate,
            monthlyFee: intake.monthlyQuote.monthlyInvestment,
            cleanupFee: intake.needsCleanup ? intake.cleanupQuote.midpoint : .zero,
            hourlyRate: intake.hourlyRate.minorUnits > 0 ? intake.hourlyRate : Money(minorUnits: 10_000, currency: .usd),
            cleanupMonthsLabel: intake.monthsBehind.label,
            cleanupKnownIssues: known,
            bankAccounts: count(intake.bankAccountCountAnswer, default: 2),
            creditCards: count(intake.creditCardCountAnswer, default: 2),
            volumeTierLabel: intake.volumeTier.label,
            payrollSupport: intake.monthlyFlags.payrollProcessing,
            salesTaxSupport: intake.monthlyFlags.salesTaxManagement,
            inventorySupport: intake.monthlyFlags.inventoryTracking
        )
        let client = AgreementClient(legalName: intake.legalBusinessName, entityType: intake.entityType, contactName: intake.pointOfContactName,
                                     contactTitle: intake.pointOfContactRole, contactEmail: intake.pointOfContactEmail, contactPhone: intake.pointOfContactPhone,
                                     paymentProcessors: intake.paymentProcessors)
        return EngagementAgreement(firm: firm, client: client, terms: terms, intakeID: intake.id)
    }

    /// Problems that must be fixed before the agreement can be issued.
    public var problems: [String] {
        var out: [String] = []
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if blank(client.legalName) { out.append("Client legal business name is missing.") }
        if blank(client.contactName) { out.append("Client signer's name is missing.") }
        if blank(firm.email) { out.append("Your business email (for notices) is missing.") }
        if terms.package.includesMonthly && terms.monthlyFee.minorUnits <= 0 { out.append("Monthly fee must be more than $0.") }
        if terms.package.includesCleanup && terms.cleanupFee.minorUnits <= 0 { out.append("Clean-up fee must be more than $0.") }
        if terms.hourlyRate.minorUnits <= 0 { out.append("Hourly rate for extra work must be more than $0.") }
        if !(1...28).contains(terms.billingDay) { out.append("Billing day must be between 1 and 28.") }
        return out
    }
}

// MARK: - Template

public struct AgreementSection: Sendable, Equatable {
    public enum Block: Sendable, Equatable {
        case paragraph(String)
        /// Rendered bold: Texas requires limitation-of-liability and
        /// indemnity language to be conspicuous (the "fair notice" rule).
        case conspicuous(String)
        case bullets([String])
        case labeled(String, String)
    }
    public let number: Int
    public let title: String
    public let blocks: [Block]
}

public struct FeeLine: Sendable, Equatable {
    public let label: String
    public let value: String
}

public enum EngagementAgreementTemplate {
    public static let version = "BBB-EA 2026.10"
    public static let title = "Bookkeeping Services Agreement"

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    public static func longDate(_ d: AccountingDate) -> String { "\(months[d.month - 1]) \(d.day), \(d.year)" }

    public static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    static func words(_ n: Int) -> String {
        let names = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return n >= 0 && n < names.count ? "\(names[n]) (\(n))" : "\(n)"
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    public static func preamble(_ a: EngagementAgreement) -> String {
        let entity = a.client.entityType.trimmingCharacters(in: .whitespaces)
        let article = entity.lowercased().first.map { "aeiou".contains($0) } == true ? "an" : "a"
        return "This \(title) (the \"Agreement\") is entered into as of \(longDate(a.terms.effectiveDate)) (the \"Effective Date\") between \(a.firm.firmName), of \(a.firm.city), \(a.firm.state) (\"Bookkeeper\"), and \(a.client.legalName)\(entity.isEmpty ? "" : ", \(article) \(entity)") (\"Client\"). Bookkeeper and Client agree as follows."
    }

    /// The agreed fees, shown in a summary box at the top of the agreement.
    public static func feeSummary(_ a: EngagementAgreement) -> [FeeLine] {
        let t = a.terms
        var lines = [FeeLine(label: "Services selected", value: t.package.label)]
        if t.package.includesMonthly {
            lines.append(FeeLine(label: "Monthly bookkeeping fee", value: "\(t.monthlyFee.accountingDescription) per month, billed in advance on the \(ordinal(t.billingDay)) of each month"))
        }
        if t.package.includesCleanup {
            lines.append(FeeLine(label: "Historical clean-up (fixed fee)", value: "\(t.cleanupFee.accountingDescription), one time — \(t.cleanupPayment.label)"))
        }
        lines.append(FeeLine(label: "Additional work (only with your written approval)", value: "\(t.hourlyRate.accountingDescription) per hour"))
        lines.append(FeeLine(label: "Payment method", value: "ACH auto-debit or pre-authorized credit card"))
        lines.append(FeeLine(label: "Effective date", value: longDate(t.effectiveDate)))
        return lines
    }

    public static func sections(_ a: EngagementAgreement) -> [AgreementSection] {
        let t = a.terms
        let firm = a.firm.firmName
        var list: [(String, [AgreementSection.Block])] = []

        // Services
        var engagement: [AgreementSection.Block] = [.paragraph("Client engages Bookkeeper to provide the services described in this Agreement for the package selected: \(t.package.label). Bookkeeper will perform the services with reasonable care, in a professional manner, and in accordance with generally accepted bookkeeping practices.")]
        engagement.append(.paragraph("Bookkeeper works in QuickBooks Online. Services are limited to the accounts, volume, and work described below; anything else is outside the scope of this Agreement unless added in writing."))
        list.append(("Engagement and Services Selected", engagement))

        if t.package.includesMonthly {
            let processors = a.client.paymentProcessors.trimmingCharacters(in: .whitespaces)
            var included = [
                "Importing, reviewing, and categorizing business income and expense transactions in QuickBooks Online.",
                "Monthly reconciliation of the in-scope bank and credit card accounts against their official statements\(processors.isEmpty ? "" : ", and of merchant and payment-processor activity (\(processors))")",
                "General ledger maintenance, including standard month-end journal entries (such as recurring accruals and transfers) and review of balance sheet accounts for accuracy.",
                "A month-end financial package — Profit & Loss, Balance Sheet, and Statement of Cash Flows — together with a plain-English monthly financial report, delivered by the \(ordinal(t.reportBusinessDay)) business day of the following month, provided Client has met its responsibilities under this Agreement."
            ]
            if t.payrollSupport { included.append("Payroll support: preparing each payroll in Client's payroll provider from hours and pay rates Client supplies, for Client's approval before it is submitted, and recording and reconciling payroll in the books. Client approves every payroll. Payroll tax deposits and payroll tax filings are made by Client's payroll provider and remain Client's responsibility.") }
            if t.salesTaxSupport { included.append("Sales tax tracking: reconciling sales tax collected and payable accounts and providing a monthly sales tax summary for Client's return. Preparing, filing, and paying sales tax returns remain Client's responsibility.") }
            if t.inventorySupport { included.append("Inventory accounting: recording inventory purchases and cost of goods sold from Client's inventory counts or inventory system reports. Physical counts and valuation are Client's responsibility.") }
            list.append(("Monthly Bookkeeping Services", [
                .paragraph("The monthly fee covers up to \(plural(t.bankAccounts, "business bank account", "business bank accounts")) and \(plural(t.creditCards, "business credit card", "business credit cards")), at a volume of \(t.volumeTierLabel.lowercased()) transactions per month in total."),
                .paragraph("Each month, Bookkeeper will provide:"),
                .bullets(included)
            ]))
        }

        if t.package.includesCleanup {
            var cleanup: [AgreementSection.Block] = [
                .paragraph("Bookkeeper will bring Client's books current as a one-time project covering approximately \(t.cleanupMonthsLabel.isEmpty ? "the agreed period" : t.cleanupMonthsLabel) of prior activity. The project includes categorizing uncategorized activity, reconciling the in-scope bank and credit card accounts for the period, correcting errors found in the balance sheet, and delivering financial statements for the period once complete.")
            ]
            if !t.cleanupKnownIssues.isEmpty {
                cleanup.append(.paragraph("Known issues identified during intake, which the fixed fee covers:"))
                cleanup.append(.bullets(t.cleanupKnownIssues))
            }
            cleanup.append(.paragraph("The clean-up fee is fixed for the scope described above. If Bookkeeper finds that the work is materially larger — for example, more months of missing activity, additional accounts, or missing statements that must be reconstructed — Bookkeeper will stop and give Client a written estimate for the additional work before continuing. Nothing additional will be billed without Client's written approval."))
            cleanup.append(.paragraph("Completion timing depends on Client providing statements, records, and answers promptly."))
            list.append(("Historical Clean-Up Project", cleanup))
        }

        var excluded = [
            "Accounts receivable work: creating or sending invoices, payment reminders, or collections.",
            "Accounts payable work: entering or scheduling vendor bills, cutting checks, or making payments.",
            "Preparing, signing, or filing any income, franchise, or other tax return, federal or state.",
            "Audits, reviews, compilations, or any other attest or assurance engagement; forensic accounting; or fraud investigation.",
            "Legal, investment, or financial-planning advice.",
            "Initiating, approving, or moving any money on Client's behalf. Bookkeeper has no signing authority on Client's accounts."
        ]
        if !(t.package.includesMonthly && t.payrollSupport) { excluded.insert("Payroll processing, payroll tax deposits and filings, and Forms W-2 or 1099.", at: 2) }
        else { excluded.insert("Payroll tax deposits and filings, and Forms W-2 or 1099.", at: 2) }
        if !(t.package.includesMonthly && t.salesTaxSupport) { excluded.insert("Sales tax tracking, returns, filings, or payments.", at: 3) }
        else { excluded.insert("Preparing, filing, or paying sales tax returns.", at: 3) }
        list.append(("Services Not Included", [
            .paragraph("Unless added by a written amendment signed or confirmed by email by both parties, the following are not part of this Agreement:"),
            .bullets(excluded)
        ]))

        list.append(("Client Responsibilities", [
            .paragraph("Accurate and timely books depend on Client's cooperation. Client agrees to:"),
            .bullets([
                "Keep read-only bank and card connections active in QuickBooks Online, or provide complete bank and credit card statements by the \(ordinal(t.statementsDueDay)) calendar day of each month.",
                "Answer questions about transactions and provide requested receipts or documents within \(words(t.responseBusinessDays)) business days.",
                "Provide information that is complete and accurate, and tell Bookkeeper promptly about new bank accounts, credit cards, loans, payment processors, or significant changes in the business.",
                "Keep original receipts, invoices, and other source documents for as long as the law requires.",
                "Review the monthly reports and raise any question or error within 30 days of delivery."
            ]),
            .paragraph("If statements or answers are late, delivery of the monthly reports will be delayed by at least the same amount of time. Delays caused by Client do not pause or reduce the monthly fee.")
        ]))

        list.append(("System Access and How Changes Are Made", [
            .paragraph("Client will give Bookkeeper accountant-user access to QuickBooks Online and, where available, read-only access to bank and payment-processor activity. Client may remove this access at any time; doing so ends the services that depend on it."),
            .paragraph("Bookkeeper reviews Client's books using Voice Ledger, bookkeeping software that reads QuickBooks Online data in read-only mode by default. Corrections are prepared and reviewed before they are posted to Client's books. Bookkeeper will never ask for or hold Client's online banking passwords, and will not initiate payments, transfers, or other movements of money.")
        ]))

        var fees: [AgreementSection.Block] = []
        if t.package.includesMonthly {
            fees.append(.labeled("Monthly fee.", "\(t.monthlyFee.accountingDescription) per month, billed in advance on the \(ordinal(t.billingDay)) day of each month. The first month's fee is due on the Effective Date."))
        }
        if t.package.includesCleanup {
            let schedule = t.cleanupPayment == .fullAtSigning
                ? "The full amount is due when this Agreement is signed."
                : "Half (\(Money(minorUnits: t.cleanupFee.minorUnits / 2, currency: .usd).accountingDescription)) is due when this Agreement is signed and the balance (\(Money(minorUnits: t.cleanupFee.minorUnits - t.cleanupFee.minorUnits / 2, currency: .usd).accountingDescription)) is due when the clean-up is delivered."
            fees.append(.labeled("Clean-up fee.", "\(t.cleanupFee.accountingDescription), fixed, for the clean-up scope described above. \(schedule)"))
        }
        fees.append(.labeled("Additional work.", "Work outside this Agreement is billed at \(t.hourlyRate.accountingDescription) per hour or at a fixed price agreed in advance, and only after Client approves it in writing or by email."))
        fees.append(.labeled("Payment method.", "Fees are paid by ACH auto-debit or a pre-authorized credit card under a separate payment authorization."))
        fees.append(.labeled("Late payment.", "If a payment is more than \(t.latePauseDays) days late, Bookkeeper may pause work until it is paid. Work resumes once the account is current."))
        if t.package.includesMonthly {
            fees.append(.labeled("Fee review.", "The monthly fee is based on the accounts and volume described above. If Client's transaction volume stays above that level for two consecutive months, or the scope changes, Bookkeeper may propose a new fee with at least \(t.noticeDays) days' written notice. Client may accept the new fee or end this Agreement under its termination terms."))
        }
        fees.append(.labeled("Software.", "Client pays for its own QuickBooks Online subscription and any other software Client uses. Bookkeeper's fees do not include these costs."))
        list.append(("Fees and Payment", fees))

        var term: [AgreementSection.Block] = []
        if t.package.includesMonthly {
            term.append(.paragraph("This Agreement begins on the Effective Date and continues month to month until either party ends it with \(t.noticeDays) days' written notice by email."))
        } else {
            term.append(.paragraph("This Agreement begins on the Effective Date and ends when the clean-up project is delivered and paid for, unless ended earlier under this section."))
        }
        term.append(.paragraph("Either party may end this Agreement immediately by written notice if the other party materially breaches it and does not fix the breach within ten (10) days of written notice, or if fees are more than thirty (30) days past due."))
        term.append(.paragraph("When this Agreement ends, Client pays for services through the end of the notice period and for any clean-up work completed at the hourly rate, up to the fixed clean-up fee. Once all fees are paid, Bookkeeper will deliver the completed work and reports for the paid period, and Client should remove Bookkeeper's system access."))
        list.append(("Term and Termination", term))

        list.append(("Confidentiality and Data Protection", [
            .paragraph("Bookkeeper will keep Client's financial and business information confidential, use it only to provide the services, and share it only with Client's authorized representatives, with others Client directs (such as Client's tax preparer), or as required by law."),
            .paragraph("To provide the services, Bookkeeper uses professional software and cloud services, including QuickBooks Online, Voice Ledger, secure email, and secure file storage. Bookkeeper may use artificial-intelligence tools to help draft written explanations and summaries. Every dollar figure is calculated by bookkeeping software from Client's records and reviewed by Bookkeeper; AI tools are not relied on to calculate figures. These providers process data under their own security and privacy terms. Client consents to this use."),
            .paragraph("Bookkeeper will notify Client promptly if Bookkeeper learns of unauthorized access to Client's information in Bookkeeper's possession.")
        ]))

        list.append(("Ownership of Records", [
            .paragraph("Client owns its books, records, and the reports delivered to it. Bookkeeper's internal working notes and software remain Bookkeeper's property. Client is responsible for keeping its own source documents; Bookkeeper is not a custodian of Client's original records.")
        ]))

        list.append(("Professional Standards and Disclaimers", [
            .labeled("Not an audit.", "\(firm) is a bookkeeping practice and is not a certified public accounting (CPA) firm. The services are not an audit, review, compilation, or examination of financial statements, and Bookkeeper provides no opinion or other assurance on them."),
            .labeled("Fraud.", "The services are not designed to detect, and cannot be relied on to find, fraud, theft, embezzlement, or illegal acts. Bookkeeper will tell Client about anything suspicious that Bookkeeper happens to notice."),
            .labeled("Management's responsibility.", "Client's management is responsible for the accuracy and completeness of the information and records it provides, for its internal controls, and for its business and tax decisions. Bookkeeper relies on Client's information without independently verifying it and is not responsible for penalties, interest, assessments, or lost deductions caused by incomplete, inaccurate, or late information from Client."),
            .labeled("No tax or legal advice.", "Bookkeeper does not provide tax, legal, or investment advice. Client is responsible for engaging a CPA or enrolled agent for tax planning, year-end adjustments, and tax returns."),
            .labeled("Use of reports.", "Reports are prepared for Client's internal management use. If Client shares them with lenders, investors, or others, it does so at its own discretion, and Bookkeeper gives no assurance to any third party.")
        ]))

        list.append(("Correction of Errors and Limitation of Liability", [
            .paragraph("If Bookkeeper makes an error in its work, Bookkeeper will correct it at no additional charge, provided Client reports it within sixty (60) days of receiving the affected report."),
            .conspicuous("TO THE FULLEST EXTENT PERMITTED BY LAW, BOOKKEEPER'S TOTAL LIABILITY FOR ALL CLAIMS ARISING OUT OF OR RELATED TO THIS AGREEMENT OR THE SERVICES, WHETHER IN CONTRACT, TORT, NEGLIGENCE, OR ANY OTHER THEORY, WILL NOT EXCEED THE FEES CLIENT PAID BOOKKEEPER DURING THE \(t.liabilityCapMonths == 3 ? "THREE (3)" : "\(t.liabilityCapMonths)") MONTHS BEFORE THE EVENT GIVING RISE TO THE CLAIM."),
            .conspicuous("IN NO EVENT WILL BOOKKEEPER BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING LOST PROFITS, LOST REVENUE, OR BUSINESS INTERRUPTION, EVEN IF ADVISED THAT THEY WERE POSSIBLE."),
            .paragraph("These limits do not apply to losses caused by Bookkeeper's gross negligence, willful misconduct, or fraud.")
        ]))

        list.append(("Indemnification", [
            .conspicuous("CLIENT WILL INDEMNIFY AND HOLD HARMLESS BOOKKEEPER FROM THIRD-PARTY CLAIMS, PENALTIES, AND REASONABLE COSTS ARISING FROM INFORMATION CLIENT PROVIDED THAT WAS INACCURATE OR INCOMPLETE, OR FROM CLIENT'S USE OF THE REPORTS, EXCEPT TO THE EXTENT CAUSED BY BOOKKEEPER'S GROSS NEGLIGENCE OR WILLFUL MISCONDUCT.")
        ]))

        list.append(("Independent Contractor", [
            .paragraph("Bookkeeper is an independent contractor, not an employee, officer, or agent of Client, and has no authority to sign for or bind Client. Bookkeeper controls how and when the services are performed, consistent with this Agreement.")
        ]))

        list.append(("Disputes and Governing Law", [
            .paragraph("The parties will first try in good faith to resolve any dispute by direct discussion for at least thirty (30) days. This Agreement is governed by the laws of the State of \(a.firm.state), and any lawsuit relating to it will be brought in the state courts located in \(a.firm.county), \(a.firm.state).")
        ]))

        list.append(("Electronic Signatures and Records", [
            .paragraph("The parties agree to do business electronically. This Agreement, notices, and amendments may be signed and delivered electronically under the federal ESIGN Act and the Texas Uniform Electronic Transactions Act (Tex. Bus. & Com. Code ch. 322). A typed name or a drawn electronic signature has the same effect as a handwritten signature. This Agreement may be signed in counterparts. Client may request a paper copy at any time at no charge.")
        ]))

        list.append(("General Terms", [
            .bullets([
                "This Agreement is the entire agreement between the parties about the services and replaces any earlier proposal or discussion.",
                "Changes must be in writing and signed, or confirmed by email, by both parties.",
                "Notices must be sent by email to the addresses in the signature section (or any updated address a party provides in writing).",
                "If any part of this Agreement is found unenforceable, the rest remains in effect, and the unenforceable part will be enforced to the greatest extent allowed.",
                "Neither party may assign this Agreement without the other's written consent, except that Bookkeeper may assign it to a successor of its bookkeeping practice.",
                "Neither party is responsible for delays caused by events beyond its reasonable control.",
                "A party's failure to enforce a term is not a waiver of it.",
                "Sections on fees owed, confidentiality, ownership of records, disclaimers, limitation of liability, indemnification, and disputes survive the end of this Agreement.",
                "The person signing for Client confirms that they are authorized to sign this Agreement on Client's behalf."
            ])
        ]))

        return list.enumerated().map { AgreementSection(number: $0.offset + 1, title: $0.element.0, blocks: $0.element.1) }
    }

    /// Full canonical text: parties, fees, every clause, and the signers'
    /// contact details. The document ID is its SHA-256.
    public static func canonicalText(_ a: EngagementAgreement) -> String {
        var out = ["\(title) — template \(version)", preamble(a), "FEES"]
        out += feeSummary(a).map { "\($0.label): \($0.value)" }
        for s in sections(a) {
            out.append("\(s.number). \(s.title)")
            for b in s.blocks {
                switch b {
                case .paragraph(let p), .conspicuous(let p): out.append(p)
                case .bullets(let items): out += items.map { "- \($0)" }
                case .labeled(let l, let p): out.append("\(l) \(p)")
                }
            }
        }
        out.append("Bookkeeper: \(a.firm.firmName), \(a.firm.ownerName), \(a.firm.ownerTitle), \(a.firm.email), \(a.firm.phone)")
        out.append("Client: \(a.client.legalName), \(a.client.contactName), \(a.client.contactTitle), \(a.client.contactEmail)")
        return out.joined(separator: "\n")
    }

    /// 64-hex SHA-256 of the canonical text.
    public static func documentHash(_ a: EngagementAgreement) -> String {
        SHA256.hash(data: Data(canonicalText(a).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The short, readable form printed on every page: `A1B2-C3D4-E5F6-0718`.
    public static func documentID(_ a: EngagementAgreement) -> String {
        let hex = documentHash(a).prefix(16).uppercased()
        return stride(from: 0, to: 16, by: 4).map { i in
            String(hex[hex.index(hex.startIndex, offsetBy: i)..<hex.index(hex.startIndex, offsetBy: i + 4)])
        }.joined(separator: "-")
    }
}
