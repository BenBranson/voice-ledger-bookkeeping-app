import Testing
import Foundation
import Core
@testable import IntegrationsQuickBooks

/// Real-shaped fixture, mirroring the live sandbox `BalanceSheet` report
/// checked before this was built: a section (`ASSETS`) containing a
/// nested section (`Current Assets` > `Bank Accounts`) with two leaf
/// accounts and a `Summary` total.
@Suite("QBOSyncClient report flattening")
struct QBOReportTests {
    static let sampleJSON = """
    {
      "Rows": {
        "Row": [
          {
            "Header": { "ColData": [{ "value": "ASSETS" }, { "value": "" }] },
            "Rows": {
              "Row": [
                {
                  "Header": { "ColData": [{ "value": "Bank Accounts" }, { "value": "" }] },
                  "Rows": {
                    "Row": [
                      { "ColData": [{ "value": "Checking", "id": "35" }, { "value": "1201.00" }], "type": "Data" },
                      { "ColData": [{ "value": "Savings", "id": "36" }, { "value": "800.00" }], "type": "Data" }
                    ]
                  },
                  "Summary": { "ColData": [{ "value": "Total Bank Accounts" }, { "value": "2001.00" }] }
                }
              ]
            },
            "Summary": { "ColData": [{ "value": "TOTAL ASSETS" }, { "value": "2001.00" }] }
          }
        ]
      }
    }
    """

    @Test("Flattens a real-shaped nested BalanceSheet report into depth-tagged lines")
    func flattensNestedReport() throws {
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(Self.sampleJSON.utf8))
        let lines = QBOSyncClient.flatten(report.rows, depth: 0)

        // ASSETS (header, depth 0) -> Bank Accounts (header, depth 1) ->
        // Checking (data, depth 2) -> Savings (data, depth 2) ->
        // Total Bank Accounts (summary, depth 1) -> TOTAL ASSETS (summary, depth 0)
        #expect(lines.count == 6)
        #expect(lines[0].label == "ASSETS")
        #expect(lines[0].depth == 0)
        #expect(lines[0].amount == nil)

        #expect(lines[1].label == "Bank Accounts")
        #expect(lines[1].depth == 1)

        #expect(lines[2].label == "Checking")
        #expect(lines[2].depth == 2)
        #expect(lines[2].amount == Money(minorUnits: 120_100, currency: .usd))
        #expect(lines[2].isSummary == false)

        #expect(lines[3].label == "Savings")
        #expect(lines[3].amount == Money(minorUnits: 80_000, currency: .usd))

        #expect(lines[4].label == "Total Bank Accounts")
        #expect(lines[4].depth == 1)
        #expect(lines[4].isSummary == true)
        #expect(lines[4].amount == Money(minorUnits: 200_100, currency: .usd))

        #expect(lines[5].label == "TOTAL ASSETS")
        #expect(lines[5].depth == 0)
        #expect(lines[5].isSummary == true)
    }

    @Test("A parent account's own postings on its header row become an '(other)' leaf, so leaves add up to the section total (live shape 2026-09-29)")
    func parentOwnPostings() throws {
        let json = """
        { "Rows": { "Row": [ {
          "Header": { "ColData": [{ "value": "Landscaping Services", "id": "45" }, { "value": "2875.69" }] },
          "Rows": { "Row": [ { "ColData": [{ "value": "Installation", "id": "52" }, { "value": "579.91" }], "type": "Data" } ] },
          "Summary": { "ColData": [{ "value": "Total Landscaping Services" }, { "value": "3455.60" }] },
          "type": "Section" } ] } }
        """
        let lines = QBOSyncClient.flatten(try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8)).rows, depth: 0)
        #expect(lines.map(\.label) == ["Landscaping Services", "Landscaping Services (other)", "Installation", "Total Landscaping Services"])
        let leaves = lines.filter { !$0.isSummary && $0.amount != nil }.compactMap(\.amount).reduce(Money.zero, +)
        #expect(leaves == lines.last!.amount)
        #expect(lines[0].amount == nil && lines[0].accountID == "45")
        #expect(lines[1].accountID == nil)
    }

    @Test("Aged payables rebuilt from the detail report when the summary is empty (live shape 2026-09-29)")
    func agingFromDetail() throws {
        func row(_ vendor: String, _ pastDue: String, _ open: String) -> String {
            #"{ "ColData": [{"value":"2026-01-01"},{"value":"Bill"},{"value":""},{"value":"\#(vendor)"},{"value":"2026-01-31"},{"value":"\#(pastDue)"},{"value":"\#(open)"},{"value":"\#(open)"}], "type": "Data" }"#
        }
        let json = #"{ "Rows": { "Row": [ { "Header": { "ColData": [{"value":"91 or more days past due"}] }, "Rows": { "Row": ["# + row("Norton", "147", "1188.00") + "," + row("PG&E", "262", "86.44") + #"] }, "type": "Section" }, { "Header": { "ColData": [{"value":"Current"}] }, "Rows": { "Row": ["# + row("Norton", "-6", "756.93") + "," + row("Permian", "44", "-12.00") + #"] }, "type": "Section" } ] } }"#
        let lines = QBOSyncClient.agingFromDetail(try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8)).rows)
        let norton = try #require(lines.first { $0.label == "Norton" })
        #expect(norton.current == Money(minorUnits: 75_693, currency: .usd))
        #expect(norton.days91AndOver == Money(minorUnits: 118_800, currency: .usd))
        #expect(lines.first { $0.label == "Permian" }?.days31to60 == Money(minorUnits: -1_200, currency: .usd))
        #expect(lines.last?.isSummary == true && lines.last?.total == Money(minorUnits: 201_937, currency: .usd))
    }

    @Test("An empty report (no rows) flattens to an empty list, not a crash")
    func emptyReportFlattensToEmptyList() throws {
        let json = "{ \"Rows\": { \"Row\": [] } }"
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8))
        #expect(QBOSyncClient.flatten(report.rows, depth: 0).isEmpty)
    }

    /// Real-shaped fixture, mirroring the live sandbox `CashFlow` report
    /// checked 2026-08-18 while adding `QBOSyncClient.fetchCashFlow`: same
    /// recursive `Header`/`Rows`/`Summary`/`ColData` + `type == "Data"` leaf
    /// shape as BalanceSheet, plus `group`/`type: "Section"` fields on
    /// section rows that BalanceSheet's fixture doesn't exercise — these
    /// must decode without error even though `flatten` never reads them.
    static let cashFlowSampleJSON = """
    {
      "Rows": {
        "Row": [
          {
            "Header": { "ColData": [{ "value": "OPERATING ACTIVITIES" }, { "value": "" }] },
            "Rows": {
              "Row": [
                {
                  "ColData": [{ "value": "Net Income" }, { "value": "-10015914.49" }],
                  "type": "Data",
                  "group": "NetIncome"
                },
                {
                  "Header": { "ColData": [{ "value": "Adjustments to reconcile Net Income" }, { "value": "" }] },
                  "Rows": {
                    "Row": [
                      { "ColData": [{ "value": "Accounts Receivable (A/R)", "id": "84" }, { "value": "-200.00" }], "type": "Data" },
                      { "ColData": [{ "value": "Accounts Payable (A/P)", "id": "33" }, { "value": "400.00" }], "type": "Data" }
                    ]
                  },
                  "Summary": { "ColData": [{ "value": "Total Adjustments" }, { "value": "200.00" }] },
                  "type": "Section",
                  "group": "OperatingAdjustments"
                }
              ]
            },
            "Summary": { "ColData": [{ "value": "Net cash provided by operating activities" }, { "value": "-10015714.49" }] },
            "type": "Section",
            "group": "OperatingActivities"
          }
        ]
      }
    }
    """

    @Test("Flattens a real-shaped CashFlow report, including a negative leaf amount and section-level group/type fields")
    func flattensCashFlowReport() throws {
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(Self.cashFlowSampleJSON.utf8))
        let lines = QBOSyncClient.flatten(report.rows, depth: 0)

        #expect(lines.count == 7)
        #expect(lines[0].label == "OPERATING ACTIVITIES")
        #expect(lines[1].label == "Net Income")
        #expect(lines[1].amount == Money(minorUnits: -1_001_591_449, currency: .usd))
        #expect(lines[2].label == "Adjustments to reconcile Net Income")
        #expect(lines[3].label == "Accounts Receivable (A/R)")
        #expect(lines[3].amount == Money(minorUnits: -20_000, currency: .usd))
        #expect(lines[4].label == "Accounts Payable (A/P)")
        #expect(lines[4].amount == Money(minorUnits: 40_000, currency: .usd))
        // "Total Adjustments" closes out the nested Adjustments section
        // (depth 1) right after its two children, before the outer
        // OPERATING ACTIVITIES section's own Summary line closes at depth 0.
        #expect(lines[5].label == "Total Adjustments")
        #expect(lines[5].isSummary == true)
        #expect(lines[6].label == "Net cash provided by operating activities")
        #expect(lines[6].isSummary == true)
        #expect(lines[6].amount == Money(minorUnits: -1_001_571_449, currency: .usd))
    }

    /// Real-shaped fixture (trimmed to 3 of the real 54 leaf rows), from the
    /// exact live sandbox `TrialBalance` response checked 2026-08-18 while
    /// adding `QBOSyncClient.fetchTrialBalance`: leaf rows carry NO `type`
    /// field at all (unlike BalanceSheet/P&L/CashFlow's `"type": "Data"`),
    /// and have 3 columns (Account, Debit, Credit) with a value in exactly
    /// one of the two money columns. This is exactly the shape that would
    /// have been silently dropped by the existing `flatten()` (gated on
    /// `type == "Data"`) — the reason `flattenTrialBalance` exists as its
    /// own function rather than a reuse.
    static let trialBalanceSampleJSON = """
    {
      "Rows": {
        "Row": [
          { "ColData": [{ "value": "Checking", "id": "35" }, { "value": "" }, { "value": "3063.76" }] },
          { "ColData": [{ "value": "Savings", "id": "36" }, { "value": "800.00" }, { "value": "" }] },
          {
            "Summary": { "ColData": [{ "value": "TOTAL" }, { "value": "10057055.33" }, { "value": "10057055.33" }] },
            "type": "Section",
            "group": "GrandTotal"
          }
        ]
      }
    }
    """

    @Test("Flattens a real-shaped TrialBalance report — untagged leaf rows with debit-XOR-credit columns, not dropped")
    func flattensTrialBalanceReport() throws {
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(Self.trialBalanceSampleJSON.utf8))
        let lines = QBOSyncClient.flattenTrialBalance(report.rows)

        #expect(lines.count == 3)

        #expect(lines[0].label == "Checking")
        #expect(lines[0].debit == nil)
        #expect(lines[0].credit == Money(minorUnits: 306_376, currency: .usd))
        #expect(lines[0].isSummary == false)

        #expect(lines[1].label == "Savings")
        #expect(lines[1].debit == Money(minorUnits: 80_000, currency: .usd))
        #expect(lines[1].credit == nil)

        #expect(lines[2].label == "TOTAL")
        #expect(lines[2].isSummary == true)
        #expect(lines[2].debit == Money(minorUnits: 1_005_705_533, currency: .usd))
        #expect(lines[2].credit == Money(minorUnits: 1_005_705_533, currency: .usd))
    }

    @Test("An empty TrialBalance (no rows) flattens to an empty list, not a crash")
    func emptyTrialBalanceFlattensToEmptyList() throws {
        let json = "{ \"Rows\": { \"Row\": [] } }"
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8))
        #expect(QBOSyncClient.flattenTrialBalance(report.rows).isEmpty)
    }

    /// Real-shaped fixture, mirroring the live sandbox `AgedReceivables`
    /// response checked 2026-08-18 while adding `QBOSyncClient.flattenAging`:
    /// a bare untagged leaf row (customer with no sub-locations), a nested
    /// section whose leaf rows ARE tagged `"type": "Data"` (customer WITH
    /// sub-locations — "Freeman Sporting Goods" in the real sandbox data),
    /// and a `GrandTotal` summary row. Exercises both leaf shapes
    /// `flattenAging`'s structural rule has to catch in the same report.
    static let agedReceivablesSampleJSON = """
    {
      "Rows": {
        "Row": [
          { "ColData": [{ "value": "Amy's Bird Sanctuary", "id": "1" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "239.00" }, { "value": "239.00" }] },
          {
            "Header": { "ColData": [{ "value": "Freeman Sporting Goods", "id": "7" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "0.00" }] },
            "Rows": {
              "Row": [
                { "ColData": [{ "value": "0969 Ocean View Road", "id": "8" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "477.50" }, { "value": "477.50" }], "type": "Data" },
                { "ColData": [{ "value": "55 Twin Lane", "id": "9" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "85.00" }, { "value": "85.00" }], "type": "Data" }
              ]
            },
            "Summary": { "ColData": [{ "value": "Total Freeman Sporting Goods" }, { "value": "0.00" }, { "value": "0.00" }, { "value": "0.00" }, { "value": "0.00" }, { "value": "562.50" }, { "value": "562.50" }] },
            "type": "Section"
          },
          {
            "Summary": { "ColData": [{ "value": "TOTAL" }, { "value": "1000.00" }, { "value": "-800.00" }, { "value": "0.00" }, { "value": "0.00" }, { "value": "5281.52" }, { "value": "5481.52" }] },
            "type": "Section",
            "group": "GrandTotal"
          }
        ]
      }
    }
    """

    @Test("Flattens a real-shaped AgedReceivables report, catching both a bare untagged leaf row and a type-tagged leaf nested inside a sub-customer section")
    func flattensAgedReceivablesReport() throws {
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(Self.agedReceivablesSampleJSON.utf8))
        let lines = QBOSyncClient.flattenAging(report.rows, depth: 0)

        // Amy's Bird Sanctuary (bare leaf, depth 0) -> Freeman Sporting
        // Goods (header, depth 0) -> its 2 sub-location leaves (depth 1,
        // type-tagged) -> Total Freeman Sporting Goods (summary, depth 0)
        // -> TOTAL (grand total summary, depth 0).
        #expect(lines.count == 6)

        #expect(lines[0].label == "Amy's Bird Sanctuary")
        #expect(lines[0].total == Money(minorUnits: 23_900, currency: .usd))
        #expect(lines[0].depth == 0)
        #expect(lines[0].isSummary == false)

        #expect(lines[1].label == "Freeman Sporting Goods")
        #expect(lines[1].total == nil) // header row's echoed "0.00" is discarded, matching ReportLine's convention

        #expect(lines[2].label == "0969 Ocean View Road")
        #expect(lines[2].depth == 1)
        #expect(lines[2].total == Money(minorUnits: 47_750, currency: .usd))

        #expect(lines[3].label == "55 Twin Lane")
        #expect(lines[3].total == Money(minorUnits: 8_500, currency: .usd))

        #expect(lines[4].label == "Total Freeman Sporting Goods")
        #expect(lines[4].isSummary == true)
        #expect(lines[4].total == Money(minorUnits: 56_250, currency: .usd))

        #expect(lines[5].label == "TOTAL")
        #expect(lines[5].isSummary == true)
        #expect(lines[5].current == Money(minorUnits: 100_000, currency: .usd))
        #expect(lines[5].days1to30 == Money(minorUnits: -80_000, currency: .usd))
        #expect(lines[5].total == Money(minorUnits: 548_152, currency: .usd))
    }

    @Test("An empty aging report (no rows) flattens to an empty list, not a crash")
    func emptyAgingReportFlattensToEmptyList() throws {
        let json = "{ \"Rows\": { \"Row\": [] } }"
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8))
        #expect(QBOSyncClient.flattenAging(report.rows, depth: 0).isEmpty)
    }

    /// Real-shaped fixture, from the exact live sandbox `GeneralLedger`
    /// response checked 2026-08-18 while adding
    /// `QBOSyncClient.fetchGeneralLedger`: one account section (Checking),
    /// its synthetic "Beginning Balance" row, one real posted transaction
    /// row (the forced-reconciliation adjustment from
    /// `VL-FORCED-RECON-001`'s own live verification, reused here since it
    /// was already real data), and the section's closing Summary.
    static let generalLedgerSampleJSON = """
    {
      "Rows": {
        "Row": [
          {
            "Header": { "ColData": [{ "value": "Checking", "id": "35" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }] },
            "Rows": {
              "Row": [
                { "ColData": [{ "value": "Beginning Balance" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "1201.00" }], "type": "Data" },
                { "ColData": [{ "value": "2026-07-31" }, { "value": "Check", "id": "228" }, { "value": "ADJ" }, { "value": "", "id": "" }, { "value": "Reconcile Adjustment" }, { "value": "Reconciliation Discrepancies", "id": "91" }, { "value": "-4264.76" }, { "value": "-3063.76" }], "type": "Data" }
              ]
            },
            "Summary": { "ColData": [{ "value": "Total for Checking" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "" }, { "value": "-4264.76" }, { "value": "" }] },
            "type": "Section"
          }
        ]
      }
    }
    """

    @Test("Flattens a real-shaped GeneralLedger report — account header, Beginning Balance, a real posted transaction, and the closing Summary")
    func flattensGeneralLedgerReport() throws {
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(Self.generalLedgerSampleJSON.utf8))
        let lines = QBOSyncClient.flattenGeneralLedger(report.rows, depth: 0)

        #expect(lines.count == 4)

        #expect(lines[0].label == "Checking")
        #expect(lines[0].isAccountHeader == true)
        #expect(lines[0].depth == 0)

        #expect(lines[1].label == "Beginning Balance")
        #expect(lines[1].isAccountHeader == false)
        #expect(lines[1].depth == 1)
        #expect(lines[1].balance == Money(minorUnits: 120_100, currency: .usd))
        #expect(lines[1].amount == nil)

        #expect(lines[2].label == "2026-07-31")
        #expect(lines[2].transactionType == "Check")
        #expect(lines[2].docNumber == "ADJ")
        #expect(lines[2].name == nil)
        #expect(lines[2].memo == "Reconcile Adjustment")
        #expect(lines[2].split == "Reconciliation Discrepancies")
        #expect(lines[2].amount == Money(minorUnits: -426_476, currency: .usd))
        #expect(lines[2].balance == Money(minorUnits: -306_376, currency: .usd))

        #expect(lines[3].label == "Total for Checking")
        #expect(lines[3].isSummary == true)
        #expect(lines[3].depth == 0)
        #expect(lines[3].amount == Money(minorUnits: -426_476, currency: .usd))
    }

    @Test("An empty GeneralLedger (no rows) flattens to an empty list, not a crash")
    func emptyGeneralLedgerFlattensToEmptyList() throws {
        let json = "{ \"Rows\": { \"Row\": [] } }"
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8))
        #expect(QBOSyncClient.flattenGeneralLedger(report.rows, depth: 0).isEmpty)
    }

    @Test("A leaf row with an empty amount string produces a nil amount, not a crash or zero")
    func emptyAmountStringProducesNilAmount() throws {
        let json = """
        { "Rows": { "Row": [
          { "ColData": [{ "value": "Some Account" }, { "value": "" }], "type": "Data" }
        ] } }
        """
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8))
        let lines = QBOSyncClient.flatten(report.rows, depth: 0)
        #expect(lines.count == 1)
        #expect(lines[0].amount == nil)
    }
}
