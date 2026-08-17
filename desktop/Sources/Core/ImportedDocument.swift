import Foundation
import CryptoKit

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.2. Only the subset Tier 1 (CSV)
/// needs — Tier 2/3 fields (declaredKind beyond bankStatement, storageURL,
/// importedBy) are not exercised by this pass and are added when those
/// tiers are built, not speculatively now.
public struct ImportedDocument: Identifiable, Sendable, Hashable {
    public let id: ImportedDocumentID
    public let realmID: RealmID
    public let filename: String
    /// Identity — reimporting the same file is detected (§9.2), not
    /// duplicated. SHA-256 of the raw file bytes.
    public let contentHash: String
    public let format: DocumentFormat
    public let declaredKind: DocumentKind
    public let importedAt: Date

    public init(
        id: ImportedDocumentID,
        realmID: RealmID,
        filename: String,
        contentHash: String,
        format: DocumentFormat,
        declaredKind: DocumentKind,
        importedAt: Date
    ) {
        self.id = id
        self.realmID = realmID
        self.filename = filename
        self.contentHash = contentHash
        self.format = format
        self.declaredKind = declaredKind
        self.importedAt = importedAt
    }

    /// §9.2: "contentHash gives idempotent import." SHA-256, hex-encoded.
    public static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ImportedDocumentID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.2. Only `csv` is exercised by
/// this pass — the other cases exist so `DocumentFormat` is the same closed
/// set the spec defines, not invented piecemeal per tier.
public enum DocumentFormat: Hashable, Codable, Sendable {
    case csv, ofx, qfx, excel
    case pdfWithTextLayer, pdfScanned
    case image(ImageFormat)
}

public enum ImageFormat: String, Hashable, Codable, Sendable {
    case png, jpeg, heic, tiff
}

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.2 — "declaredKind is stated by
/// you, not inferred." Only `bankStatement`/`creditCardStatement` are
/// exercised by this pass.
public enum DocumentKind: String, Codable, Sendable, Hashable {
    case bankStatement, creditCardStatement
    case qboAuditLogExport, qboReport, reconciliationReport
    case booksReviewScreenshot, forReviewQueueScreenshot
    case bankRulesExport, chartOfAccounts, vendorList, customerList
    case priorPeriodWorkpaper, other
}
