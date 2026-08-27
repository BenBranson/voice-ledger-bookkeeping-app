import Testing
import Foundation
import Core
@testable import IntegrationsQuickBooks

/// No network access — decodes synthetic JSON in the real shape confirmed
/// against the live sandbox 2026-08-27 (`backend/spike/checkTaxEntities.ts`,
/// `voiceledger-devtool tax-check`).
@Suite("QBORawTax decoding")
struct QBORawTaxTests {
    @Test("Decodes a real-shaped TaxCode query response")
    func decodesTaxCode() throws {
        let json = """
        {
          "QueryResponse": {
            "TaxCode": [
              {"Name":"TAX","Description":"TAX","Taxable":true,"TaxGroup":false,"Id":"TAX"},
              {"Name":"NON","Description":"NON","Taxable":false,"TaxGroup":false,"Id":"NON"}
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOTaxCodeQueryResponse.self, from: Data(json.utf8))
        let codes = try #require(response.queryResponse.taxCode)
        #expect(codes.count == 2)
        #expect(codes[0].id == "TAX")
        #expect(codes[0].name == "TAX")
        #expect(codes[0].taxable == true)
        #expect(codes[1].taxable == false)
    }

    @Test("Decodes a real-shaped TaxRate query response, including nested AgencyRef.value")
    func decodesTaxRate() throws {
        let json = """
        {
          "QueryResponse": {
            "TaxRate": [
              {"Name":"AZ State tax","Description":"Sales Tax","Active":true,"RateValue":7.1,"AgencyRef":{"value":"1"},"Id":"1","SyncToken":"0"}
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOTaxRateQueryResponse.self, from: Data(json.utf8))
        let rate = try #require(response.queryResponse.taxRate?.first)
        #expect(rate.id == "1")
        #expect(rate.name == "AZ State tax")
        #expect(rate.rateValue == 7.1)
        #expect(rate.active == true)
        #expect(rate.agencyID == "1")
    }

    @Test("A TaxRate with no AgencyRef at all decodes agencyID as nil, not a crash")
    func decodesTaxRateWithoutAgencyRef() throws {
        let json = """
        {
          "QueryResponse": {
            "TaxRate": [
              {"Name":"No Agency","Active":true,"RateValue":5.0,"Id":"9"}
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOTaxRateQueryResponse.self, from: Data(json.utf8))
        let rate = try #require(response.queryResponse.taxRate?.first)
        #expect(rate.agencyID == nil)
    }

    @Test("Decodes a real-shaped TaxAgency query response")
    func decodesTaxAgency() throws {
        let json = """
        {
          "QueryResponse": {
            "TaxAgency": [
              {"TaxTrackedOnPurchases":false,"TaxTrackedOnSales":true,"Id":"1","DisplayName":"Arizona Dept. of Revenue"}
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOTaxAgencyQueryResponse.self, from: Data(json.utf8))
        let agency = try #require(response.queryResponse.taxAgency?.first)
        #expect(agency.id == "1")
        #expect(agency.displayName == "Arizona Dept. of Revenue")
    }

    @Test("A TaxCode with extra nested fields (e.g. SalesTaxRateList) still decodes cleanly, ignoring unknown keys")
    func decodesTaxCodeWithExtraNestedFields() throws {
        let json = """
        {
          "QueryResponse": {
            "TaxCode": [
              {"Name":"California","Active":true,"Hidden":false,"Taxable":true,"TaxGroup":true,"Id":"2",
               "SalesTaxRateList":{"TaxRateDetail":[{"TaxRateRef":{"value":"3","name":"California"},"TaxTypeApplicable":"SalesTaxRateType"}]}}
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOTaxCodeQueryResponse.self, from: Data(json.utf8))
        let code = try #require(response.queryResponse.taxCode?.first)
        #expect(code.id == "2")
        #expect(code.taxable == true)
    }
}
