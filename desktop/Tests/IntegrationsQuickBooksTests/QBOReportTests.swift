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

    @Test("An empty report (no rows) flattens to an empty list, not a crash")
    func emptyReportFlattensToEmptyList() throws {
        let json = "{ \"Rows\": { \"Row\": [] } }"
        let report = try JSONDecoder().decode(QBORawReport.self, from: Data(json.utf8))
        #expect(QBOSyncClient.flatten(report.rows, depth: 0).isEmpty)
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
