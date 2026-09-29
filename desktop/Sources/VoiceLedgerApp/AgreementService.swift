import Foundation
import AppKit
import PDFKit
import Core
import Exporting

/// One prepared engagement agreement and what has happened to it. Stored
/// locally (not per QBO realm — most agreements are signed before a client
/// connects QuickBooks, same reasoning as `IntakeRosterStore`).
struct AgreementRecord: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case prepared, signedInPerson, signedCopyReceived
        var label: String {
            switch self {
            case .prepared: return "Prepared — not yet signed"
            case .signedInPerson: return "Signed in person"
            case .signedCopyReceived: return "Signed copy received"
            }
        }
    }
    struct Event: Codable, Equatable {
        let at: Date
        let text: String
    }

    let id: String
    let createdAt: Date
    let documentID: String
    let documentHash: String
    let preparedOn: AccountingDate
    let agreement: EngagementAgreement
    let folderName: String
    var status: Status
    var signature: AgreementSignature?
    var signedFileName: String?
    var events: [Event]
}

/// What the in-app signing page posts back, read into plain values on
/// the main thread before anything else touches it.
struct SignedPayload: Sendable {
    let documentID: String
    let typedName: String
    let title: String
    let method: String
    let image: String?
    let signedAtLabel: String
    let signedAtISO: String

    init(_ body: [String: Any]) {
        documentID = body["documentId"] as? String ?? ""
        typedName = body["typedName"] as? String ?? ""
        title = body["title"] as? String ?? ""
        method = body["method"] as? String ?? ""
        image = body["image"] as? String
        signedAtLabel = body["signedAtLabel"] as? String ?? ""
        signedAtISO = body["signedAtISO"] as? String ?? ""
    }
}

/// Prepares, stores, emails, and records engagement agreements. Files live
/// in ~/Library/Application Support/VoiceLedger/Agreements (outside
/// ~/Documents, so the PDF engine never needs Documents access).
enum AgreementService {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "VoiceLedger/Agreements")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static var indexURL: URL { root.appending(path: "index.json") }
    static var firmURL: URL { root.appending(path: "firm-profile.json") }

    static func folder(_ record: AgreementRecord) -> URL { root.appending(path: record.folderName) }
    static func baseName(_ a: EngagementAgreement) -> String { "Engagement Agreement - \(safe(a.client.legalName))" }
    static func signingPageURL(_ r: AgreementRecord) -> URL { folder(r).appending(path: "\(baseName(r.agreement)).html") }
    static func reviewPDFURL(_ r: AgreementRecord) -> URL { folder(r).appending(path: "\(baseName(r.agreement)).pdf") }
    static func signedURL(_ r: AgreementRecord) -> URL? { r.signedFileName.map { folder(r).appending(path: $0) } }

    static func safe(_ s: String) -> String {
        let cleaned = s.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Client" : String(cleaned.prefix(80))
    }

    // MARK: Persistence

    static func loadAll() -> [AgreementRecord] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([AgreementRecord].self, from: data)) ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    static func saveAll(_ records: [AgreementRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: indexURL, options: .atomic)
    }

    static func loadFirm() -> FirmProfile {
        guard let data = try? Data(contentsOf: firmURL), let firm = try? JSONDecoder().decode(FirmProfile.self, from: data) else { return FirmProfile() }
        return firm
    }

    static func saveFirm(_ firm: FirmProfile) {
        try? JSONEncoder().encode(firm).write(to: firmURL, options: .atomic)
    }

    static func upsert(_ record: AgreementRecord) throws {
        var all = loadAll()
        if let i = all.firstIndex(where: { $0.id == record.id }) { all[i] = record } else { all.insert(record, at: 0) }
        try saveAll(all)
    }

    // MARK: Prepare

    static func today() -> AccountingDate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return AccountingDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Writes the signing page and the review PDF for exactly this text.
    /// Returns the existing record when this exact agreement was already
    /// prepared, so re-sending never creates duplicates.
    static func prepare(_ agreement: EngagementAgreement) async throws -> AgreementRecord {
        let problems = agreement.problems
        guard problems.isEmpty else { throw Failure(message: problems.joined(separator: " ")) }
        let hash = EngagementAgreementTemplate.documentHash(agreement)
        if let existing = loadAll().first(where: { $0.documentHash == hash && $0.status == .prepared }),
           FileManager.default.fileExists(atPath: reviewPDFURL(existing).path) {
            return existing
        }
        let docID = EngagementAgreementTemplate.documentID(agreement)
        let preparedOn = today()
        let stamp = String(format: "%04d-%02d-%02d", preparedOn.year, preparedOn.month, preparedOn.day)
        let record = AgreementRecord(id: UUID().uuidString, createdAt: Date(), documentID: docID, documentHash: hash, preparedOn: preparedOn,
                                     agreement: agreement, folderName: "\(stamp) \(safe(agreement.client.legalName)) \(docID)",
                                     status: .prepared, signature: nil, signedFileName: nil,
                                     events: [.init(at: Date(), text: "Prepared (document ID \(docID))")])
        try FileManager.default.createDirectory(at: folder(record), withIntermediateDirectories: true)
        let signing = EngagementAgreementHTML.render(agreement, mode: .signing, providerSignedOn: preparedOn)
        try Data(signing.utf8).write(to: signingPageURL(record), options: .atomic)
        try await renderPDF(agreement, mode: .review, providerSignedOn: preparedOn, to: reviewPDFURL(record))
        try upsert(record)
        return record
    }

    // MARK: PDF (same local WeasyPrint engine as the monthly report)

    static func renderPDF(_ agreement: EngagementAgreement, mode: EngagementAgreementHTML.Mode, providerSignedOn: AccountingDate, to output: URL) async throws {
        guard let renderer = MonthlyReportService.rendererDirectory() else {
            throw Failure(message: "The PDF engine (report-renderer) wasn't found. Rebuild the app bundle to install it.")
        }
        let python = renderer.appending(path: ".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw Failure(message: "The PDF engine isn't installed (report-renderer/.venv is missing).")
        }
        let fontDir = renderer.appending(path: "node_modules/@fontsource/inter/files")
        let fonts = [(400, "400"), (600, "600"), (700, "700")].map { weight, file in
            "@font-face{font-family:\"Inter\";font-weight:\(weight);src:url(\"file://\(fontDir.path)/inter-latin-\(file)-normal.woff\") format(\"woff\");}"
        }.joined()
        let work = FileManager.default.temporaryDirectory.appending(path: "vl-agreement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let html = work.appending(path: "agreement.html")
        let pdf = work.appending(path: "agreement.pdf")
        try Data(EngagementAgreementHTML.render(agreement, mode: mode, providerSignedOn: providerSignedOn, pdfFontCSS: fonts).utf8).write(to: html)

        let process = Process()
        process.executableURL = python
        process.arguments = [renderer.appending(path: "render_pdf.py").path, html.path, pdf.path, renderer.path, work.path]
        process.currentDirectoryURL = work
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { p in
                if p.terminationStatus == 0 { c.resume() } else {
                    let detail = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").last.map(String.init) ?? ""
                    c.resume(throwing: Failure(message: "PDF creation failed. \(detail.prefix(200))"))
                }
            }
            do { try process.run() } catch { c.resume(throwing: Failure(message: "Couldn't start the PDF engine: \(error.localizedDescription)")) }
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.copyItem(at: pdf, to: output)
    }

    // MARK: In-person signing

    /// Validates a signature posted by the in-app signing page and writes
    /// the signed PDF. The page must be signing exactly this document.
    static func recordInPersonSignature(_ record: AgreementRecord, payload: SignedPayload) async throws -> AgreementRecord {
        guard payload.documentID == record.documentID else { throw Failure(message: "The signed page doesn't match this agreement.") }
        let name = payload.typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(name.count) else { throw Failure(message: "The signer's name is missing.") }
        let method: AgreementSignature.Method = payload.method == "drawn" ? .drawn : .typed
        let image = payload.image
        guard AgreementSignature.isSafeImage(image), method == .typed || image != nil else { throw Failure(message: "The drawn signature couldn't be read.") }
        let signature = AgreementSignature(
            typedName: name,
            title: String(payload.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
            method: method,
            imageDataURL: method == .drawn ? image : nil,
            signedAtLabel: String(payload.signedAtLabel.prefix(80)),
            signedAtISO: String(payload.signedAtISO.prefix(40)),
            device: "In person on the bookkeeper's Mac (Voice Ledger)"
        )
        var updated = record
        let fileName = "\(baseName(record.agreement)) (signed).pdf"
        try await renderPDF(record.agreement, mode: .signed(signature), providerSignedOn: record.preparedOn, to: folder(record).appending(path: fileName))
        updated.signature = signature
        updated.signedFileName = fileName
        updated.status = .signedInPerson
        updated.events.append(.init(at: Date(), text: "Signed in person by \(name)\(signature.title.isEmpty ? "" : ", \(signature.title)") (\(method == .drawn ? "drawn" : "typed") signature)"))
        try upsert(updated)
        return updated
    }

    // MARK: Signed copy returned by the client

    /// Stores the client's returned signed copy. For a PDF, checks that the
    /// document ID printed on it matches this agreement.
    static func recordReturnedCopy(_ record: AgreementRecord, file: URL) throws -> (AgreementRecord, String) {
        let ext = file.pathExtension.lowercased()
        guard ["pdf", "png", "jpg", "jpeg", "heic"].contains(ext) else { throw Failure(message: "Choose the signed PDF or a photo/scan of the signed agreement.") }
        var check: String
        if ext == "pdf" {
            guard let doc = PDFDocument(url: file) else { throw Failure(message: "That PDF couldn't be opened.") }
            let text = (doc.string ?? "").uppercased()
            check = text.contains(record.documentID)
                ? "Document ID \(record.documentID) found in the returned PDF — it is this version of the agreement."
                : "Document ID \(record.documentID) was NOT found in the returned PDF. Check that the client signed this version before relying on it."
        } else {
            check = "Image received — the document ID can't be checked automatically. Confirm it shows Document ID \(record.documentID)."
        }
        let fileName = "\(baseName(record.agreement)) (signed by client).\(ext)"
        let target = folder(record).appending(path: fileName)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: file, to: target)
        var updated = record
        updated.signedFileName = fileName
        updated.status = .signedCopyReceived
        updated.events.append(.init(at: Date(), text: "Signed copy received and saved. \(check)"))
        try upsert(updated)
        return (updated, check)
    }

    // MARK: Email

    static func emailBody(_ r: AgreementRecord) -> String {
        let a = r.agreement
        let first = a.client.contactName.split(separator: " ").first.map(String.init) ?? "there"
        let fees = EngagementAgreementTemplate.feeSummary(a).dropFirst().prefix(2).map { "• \($0.label): \($0.value)" }.joined(separator: "\n")
        return """
        Hi \(first),

        Thank you for choosing \(a.firm.firmName). Attached is your Bookkeeping Services Agreement for \(a.terms.package.label):

        \(fees)

        To sign on a computer: open the attached file "\(baseName(a)).html" in your web browser (Safari, Chrome, or Edge), read it, type your name (and draw your signature if you'd like), and click "Accept & Sign Agreement". Then click "Save signed copy as PDF" and reply to this email with that PDF attached.

        To sign on a phone or tablet: open the attached PDF, tap the markup (pen) icon, add your signature and the date on the Client signature line, and reply with the signed PDF.

        Document ID \(r.documentID) appears on every page so we can both be sure we're looking at the same version.

        If you have any questions before signing, just reply or call me at \(a.firm.phone).

        \(a.firm.ownerName)
        \(a.firm.ownerTitle), \(a.firm.firmName)
        \(a.firm.phone) · \(a.firm.email)
        """
    }

    /// Opens a pre-filled email in the Mail app with both files attached.
    /// Nothing is sent until the bookkeeper presses Send in Mail. Returns
    /// false when Mail can't compose (e.g. no Mail account set up).
    @MainActor
    static func composeEmail(_ r: AgreementRecord) -> Bool {
        let subject = "Bookkeeping Services Agreement — \(r.agreement.client.legalName)"
        let items: [Any] = [emailBody(r), signingPageURL(r), reviewPDFURL(r)]
        guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) else { return false }
        service.recipients = r.agreement.client.contactEmail.isEmpty ? [] : [r.agreement.client.contactEmail]
        service.subject = subject
        service.perform(withItems: items)
        return true
    }

    static func executedCopyBody(_ r: AgreementRecord) -> String {
        let a = r.agreement
        let first = (r.signature?.typedName ?? a.client.contactName).split(separator: " ").first.map(String.init) ?? "there"
        var next = ["I'll send the payment authorization for the fees in the agreement, if you haven't completed it already.",
                    "Please invite \(a.firm.email) as an accountant user in QuickBooks Online.",
                    "Keep your bank and card feeds connected, or send statements by the \(EngagementAgreementTemplate.ordinal(a.terms.statementsDueDay)) of each month."]
        if a.terms.package.includesCleanup { next.append("For the clean-up, I'll let you know which statements and records I need for the months being caught up.") }
        return """
        Hi \(first),

        Thank you for signing. Attached is the fully signed copy of your Bookkeeping Services Agreement (Document ID \(r.documentID)) for your records.

        Next steps:
        \(next.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))

        I'm looking forward to working with you.

        \(a.firm.ownerName)
        \(a.firm.ownerTitle), \(a.firm.firmName)
        \(a.firm.phone) · \(a.firm.email)
        """
    }

    /// Emails the client the fully signed copy for their records. Opens a
    /// pre-filled draft only; the bookkeeper presses Send.
    @MainActor
    static func sendExecutedCopy(_ r: AgreementRecord) throws -> (AgreementRecord, Bool) {
        guard let file = signedURL(r), FileManager.default.fileExists(atPath: file.path) else { throw Failure(message: "There's no signed copy on file yet.") }
        let subject = "Your signed Bookkeeping Services Agreement — \(r.agreement.client.legalName)"
        let body = executedCopyBody(r)
        var composed = false
        if let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [body, file]) {
            service.recipients = r.agreement.client.contactEmail.isEmpty ? [] : [r.agreement.client.contactEmail]
            service.subject = subject
            service.perform(withItems: [body, file])
            composed = true
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            NSWorkspace.shared.activateFileViewerSelecting([file])
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = r.agreement.client.contactEmail
            components.queryItems = [URLQueryItem(name: "subject", value: subject)]
            if let url = components.url { NSWorkspace.shared.open(url) }
        }
        var updated = r
        updated.events.append(.init(at: Date(), text: "Email with the fully signed copy opened for sending"))
        try upsert(updated)
        return (updated, composed)
    }

    /// For Gmail in a browser: shows the two files in Finder, copies the
    /// email text, and opens a new message addressed to the client.
    @MainActor
    static func emailViaBrowser(_ r: AgreementRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(emailBody(r), forType: .string)
        NSWorkspace.shared.activateFileViewerSelecting([signingPageURL(r), reviewPDFURL(r)])
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = r.agreement.client.contactEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Bookkeeping Services Agreement — \(r.agreement.client.legalName)")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
