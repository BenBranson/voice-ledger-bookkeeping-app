import Foundation
import Core

/// docs/phase-0/04_DATA_MODEL.md §4.9: "report column composition varies by
/// minor version and locale" — this decodes only the shape verified live
/// against a real `BalanceSheet` (4 levels of nested sections:
/// `ASSETS > Current Assets > Bank Accounts > Checking`). A row is EITHER a
/// section (`Header` + nested `Rows`, optional `Summary` total) OR a leaf
/// data line (`ColData` + `type == "Data"` directly on the row) — QBO
/// doesn't discriminate these with a clean enum tag, so every field here is
/// optional and the flattening logic in `QBOSyncClient` figures out which
/// shape it's looking at.
public struct QBORawReport: Decodable, Sendable {
    public let rows: QBORawReportRowList
    public let header: Header?

    /// Only the field the monthly report needs: QBO states the report's
    /// accounting basis ("Accrual"/"Cash") in its header.
    public struct Header: Decodable, Sendable {
        public let reportBasis: String?
        /// QBO's `Option` list. `NoReportData = true` (verified live 2026-10-02 on a
        /// month with no activity yet) means every total is zero; QBO still sends
        /// the summary rows, but with no amount.
        public let option: [Option]?
        public struct Option: Decodable, Sendable {
            public let name: String?
            public let value: String?
            enum CodingKeys: String, CodingKey { case name = "Name", value = "Value" }
        }
        public var noReportData: Bool { option?.contains { $0.name == "NoReportData" && $0.value == "true" } ?? false }
        enum CodingKeys: String, CodingKey { case reportBasis = "ReportBasis", option = "Option" }
    }

    enum CodingKeys: String, CodingKey {
        case rows = "Rows"
        case header = "Header"
    }
}

public struct QBORawReportRowList: Decodable, Sendable {
    public let row: [QBORawReportRow]?

    enum CodingKeys: String, CodingKey {
        case row = "Row"
    }
}

public struct QBORawReportRow: Decodable, Sendable {
    /// Present on a section row.
    public let header: QBORawReportRowHeader?
    /// Present on a section row — its nested children.
    public let rows: QBORawReportRowList?
    /// Present on a section row that has a total line (not every section
    /// does — a leaf-only section may have no `Summary`).
    public let summary: QBORawReportRowHeader?
    /// Present on a leaf data row, directly at this level (not nested).
    public let colData: [QBORawReportColData]?
    public let type: String?

    enum CodingKeys: String, CodingKey {
        case header = "Header"
        case rows = "Rows"
        case summary = "Summary"
        case colData = "ColData"
        case type
    }
}

public struct QBORawReportRowHeader: Decodable, Sendable {
    public let colData: [QBORawReportColData]

    enum CodingKeys: String, CodingKey {
        case colData = "ColData"
    }
}

public struct QBORawReportColData: Decodable, Sendable {
    public let value: String
    public let id: String?

    enum CodingKeys: String, CodingKey {
        case value, id
    }
}
