import Testing
@testable import Core
import Foundation

@Suite("Engagement agreement")
struct EngagementAgreementTests {
    let date = AccountingDate(year: 2026, month: 10, day: 1)

    func intake(cleanup: Bool = false, payroll: Bool = false) -> ClientIntake {
        var i = ClientIntake(legalBusinessName: "Apex Peak Logistics, LLC", entityType: "Texas limited liability company", bankAccountCountAnswer: "2 checking", creditCardCountAnswer: "one",
                             pointOfContactName: "Marcus Vance", pointOfContactRole: "Managing Member", pointOfContactEmail: "marcus@example.com", hourlyRateText: "75")
        i.needsCleanup = cleanup
        i.monthlyFlags.payrollProcessing = payroll
        i.cleanupIssues.negativeBalances = true
        return i
    }

    func text(_ a: EngagementAgreement) -> String { EngagementAgreementTemplate.canonicalText(a) }

    @Test("Built from the intake: the quoted fees, contact, and account counts")
    func fromIntake() {
        let i = intake(cleanup: true)
        let a = EngagementAgreement.from(intake: i, effectiveDate: date)
        #expect(a.terms.package == .monthlyAndCleanup)
        #expect(a.terms.monthlyFee == i.monthlyQuote.monthlyInvestment)
        #expect(a.terms.cleanupFee == i.cleanupQuote.midpoint)
        #expect(a.terms.bankAccounts == 2)
        #expect(a.terms.creditCards == 2) // "one" has no digits → default
        #expect(a.terms.cleanupKnownIssues == ["Accounts carrying negative balances"])
        #expect(a.problems.isEmpty)
        #expect(a.firm.email == "benjamin@benjaminbransonbookkeeping.com")
    }

    @Test("Scope follows what the client pays for: add-ons included, everything else excluded")
    func scope() {
        let plain = text(EngagementAgreement.from(intake: intake(), effectiveDate: date))
        #expect(plain.contains("- Payroll processing, payroll tax deposits and filings, and Forms W-2 or 1099."))
        #expect(!plain.contains("Payroll support:"))
        #expect(!plain.contains("Historical Clean-Up Project"))
        let payroll = text(EngagementAgreement.from(intake: intake(payroll: true), effectiveDate: date))
        #expect(payroll.contains("Payroll support:"))
        #expect(payroll.contains("- Payroll tax deposits and filings, and Forms W-2 or 1099."))
    }

    @Test("Clean-up only has no monthly fee and ends on delivery")
    func cleanupOnly() {
        var a = EngagementAgreement.from(intake: intake(cleanup: true), effectiveDate: date)
        a.terms.package = .cleanupOnly
        let t = text(a)
        #expect(!t.contains("Monthly fee."))
        #expect(t.contains("ends when the clean-up project is delivered"))
        #expect(!EngagementAgreementTemplate.feeSummary(a).contains { $0.label.hasPrefix("Monthly") })
    }

    @Test("Document ID changes with any term and is stable otherwise")
    func documentID() {
        let a = EngagementAgreement.from(intake: intake(), effectiveDate: date)
        var b = a
        #expect(EngagementAgreementTemplate.documentID(a) == EngagementAgreementTemplate.documentID(b))
        b.terms.monthlyFee = b.terms.monthlyFee + Money(minorUnits: 100, currency: .usd)
        #expect(EngagementAgreementTemplate.documentID(a) != EngagementAgreementTemplate.documentID(b))
        #expect(EngagementAgreementTemplate.documentID(a).count == 19)
    }

    @Test("Missing essentials block issuing")
    func problems() {
        var a = EngagementAgreement.from(intake: intake(), effectiveDate: date)
        a.client.legalName = " "
        a.terms.monthlyFee = .zero
        #expect(a.problems.count == 2)
    }

    @Test("Liability and indemnity language is marked conspicuous (Texas fair-notice rule)")
    func conspicuous() {
        let sections = EngagementAgreementTemplate.sections(EngagementAgreement.from(intake: intake(), effectiveDate: date))
        let loud = sections.flatMap(\.blocks).filter { if case .conspicuous = $0 { return true }; return false }
        #expect(loud.count == 3)
    }
}
