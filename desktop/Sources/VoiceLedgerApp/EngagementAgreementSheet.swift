import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import Core
import Exporting
import DesignSystem
import VoiceLedgerUI

/// Builds, previews, and issues a client's engagement agreement from a
/// saved intake (owner request 2026-09-29). Every term is editable here;
/// the agreement text itself comes from `EngagementAgreementTemplate`.
struct EngagementAgreementSheet: View {
    let roster: [ClientIntake]
    let onClose: () -> Void

    @State private var selectedIntakeID: String?
    @State private var agreement: EngagementAgreement
    @State private var firm: FirmProfile
    @State private var effectiveDate: Date
    @State private var records: [AgreementRecord] = AgreementService.loadAll()
    @State private var busy: String?
    @State private var message: String?
    @State private var error: String?
    @State private var previewURL: URL?
    @State private var signingRecord: AgreementRecord?
    @State private var showFirm = false

    init(roster: [ClientIntake], initialIntakeID: String?, onClose: @escaping () -> Void) {
        self.roster = roster
        self.onClose = onClose
        let firm = AgreementService.loadFirm()
        let start = Self.defaultEffectiveDate()
        let intake = roster.first { $0.id == initialIntakeID } ?? roster.first
        _firm = State(initialValue: firm)
        _effectiveDate = State(initialValue: start)
        _selectedIntakeID = State(initialValue: intake?.id)
        _agreement = State(initialValue: intake.map { EngagementAgreement.from(intake: $0, firm: firm, effectiveDate: Self.accountingDate(start)) }
                           ?? EngagementAgreement(firm: firm, client: AgreementClient(), terms: AgreementTerms(effectiveDate: Self.accountingDate(start))))
    }

    static func defaultEffectiveDate() -> Date {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: 1, to: startOfMonth) ?? Date()
    }

    static func accountingDate(_ d: Date) -> AccountingDate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return AccountingDate(year: c.year!, month: c.month!, day: c.day!)
    }

    private var clientRecords: [AgreementRecord] {
        records.filter { r in
            if let id = selectedIntakeID, r.agreement.intakeID == id { return true }
            return !agreement.client.legalName.isEmpty && r.agreement.client.legalName.caseInsensitiveCompare(agreement.client.legalName) == .orderedSame
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                ScrollView { form.padding(VLSpacing.md) }
                    .frame(width: 440)
                    .background(VLColor.background)
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Text("Preview — what the client will read").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                        Spacer()
                        Text("Document ID \(EngagementAgreementTemplate.documentID(agreement))").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).monospacedDigit()
                    }
                    .padding(.horizontal, VLSpacing.md).padding(.vertical, VLSpacing.xs)
                    AgreementWebView(html: EngagementAgreementHTML.render(agreement, mode: .review, providerSignedOn: AgreementService.today()), onSigned: nil)
                }
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 1180, minHeight: 820)
        .background(VLColor.background)
        .onChange(of: effectiveDate) { _, new in agreement.terms.effectiveDate = Self.accountingDate(new) }
        .onChange(of: firm) { _, new in agreement.firm = new; AgreementService.saveFirm(new) }
        .sheet(item: Binding(get: { previewURL.map { PreviewItem(url: $0) } }, set: { previewURL = $0?.url })) { item in
            PDFPreviewSheet(url: item.url, title: item.url.deletingPathExtension().lastPathComponent) { previewURL = nil }
        }
        .sheet(item: $signingRecord) { record in
            InPersonSigningSheet(record: record) { updated in
                signingRecord = nil
                records = AgreementService.loadAll()
                if let updated, let url = AgreementService.signedURL(updated) {
                    message = "Signed by \(updated.signature?.typedName ?? "the client") and saved. Use “Send Signed Copy to Client…” under Agreements on File to email them their copy."
                    previewURL = url
                }
            }
        }
        .alert("Engagement Agreement", isPresented: Binding(get: { message != nil || error != nil }, set: { if !$0 { message = nil; error = nil } })) {
            Button("OK") { message = nil; error = nil }
        } message: {
            Text(error ?? message ?? "")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: VLSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Engagement Agreement").font(VLTypography.pageTitle()).foregroundStyle(VLColor.textPrimary)
                Text("For a client who has agreed to your price. The client reads it and signs by typing and/or drawing their signature.")
                    .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
            }
            Spacer()
            Picker("Client", selection: Binding(get: { selectedIntakeID ?? "" }, set: { pick($0) })) {
                if roster.isEmpty { Text("No saved clients yet").tag("") }
                ForEach(roster) { intake in Text(intake.displayName).tag(intake.id) }
            }
            .frame(width: 300)
            Button("Close") { onClose() }.keyboardShortcut(.cancelAction)
        }
        .padding(VLSpacing.md)
    }

    private func pick(_ id: String) {
        guard let intake = roster.first(where: { $0.id == id }) else { return }
        selectedIntakeID = id
        agreement = EngagementAgreement.from(intake: intake, firm: firm, effectiveDate: Self.accountingDate(effectiveDate))
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: VLSpacing.md) {
            if roster.isEmpty {
                note("Save the client on the Intake Questions page first — the agreement is filled in from their intake answers and quote.", color: VLColor.violet)
            }
            if !agreement.problems.isEmpty {
                note(agreement.problems.joined(separator: "\n"), color: .orange)
            }

            group("CLIENT") {
                field("Legal business name", $agreement.client.legalName)
                field("Entity type (LLC, S-Corp, sole proprietorship…)", $agreement.client.entityType)
                HStack { field("Signer's full name", $agreement.client.contactName); field("Signer's title", $agreement.client.contactTitle) }
                field("Signer's email", $agreement.client.contactEmail)
            }

            group("PACKAGE") {
                Picker("", selection: $agreement.terms.package) {
                    ForEach(EngagementPackage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup).labelsHidden()
            }

            group("FEES") {
                if agreement.terms.package.includesMonthly {
                    money("Monthly fee", $agreement.terms.monthlyFee)
                    Stepper("Billed on day \(agreement.terms.billingDay) of each month", value: $agreement.terms.billingDay, in: 1...28)
                }
                if agreement.terms.package.includesCleanup {
                    money("Historical clean-up — fixed fee", $agreement.terms.cleanupFee)
                    Picker("Clean-up payment", selection: $agreement.terms.cleanupPayment) {
                        ForEach(CleanupPaymentSchedule.allCases) { Text($0.label).tag($0) }
                    }
                    field("Clean-up period covered", $agreement.terms.cleanupMonthsLabel)
                }
                money("Hourly rate for extra work", $agreement.terms.hourlyRate)
                DatePicker("Effective date", selection: $effectiveDate, displayedComponents: .date)
                Text("Prefilled from the intake quote (clean-up uses the midpoint of the estimate). Change anything you agreed differently.")
                    .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
            }

            if agreement.terms.package.includesMonthly {
                group("MONTHLY SCOPE") {
                    Stepper("Bank accounts covered: \(agreement.terms.bankAccounts)", value: $agreement.terms.bankAccounts, in: 1...20)
                    Stepper("Credit cards covered: \(agreement.terms.creditCards)", value: $agreement.terms.creditCards, in: 0...20)
                    Picker("Monthly transactions", selection: $agreement.terms.volumeTierLabel) {
                        ForEach(PricingCalculator.VolumeTier.allCases) { Text($0.label).tag($0.label) }
                    }
                    Toggle("Payroll support (prepare payroll for approval, record & reconcile)", isOn: $agreement.terms.payrollSupport)
                    Toggle("Sales tax tracking (not filing)", isOn: $agreement.terms.salesTaxSupport)
                    Toggle("Inventory accounting", isOn: $agreement.terms.inventorySupport)
                    field("Payment processors to reconcile (optional)", $agreement.client.paymentProcessors)
                    Text("Anything not switched on here is listed under “Services Not Included”.")
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                }
            }

            group("TERMS") {
                Stepper("Statements due by day \(agreement.terms.statementsDueDay) of the month", value: $agreement.terms.statementsDueDay, in: 1...20)
                Stepper("Client answers questions within \(agreement.terms.responseBusinessDays) business days", value: $agreement.terms.responseBusinessDays, in: 1...10)
                Stepper("Reports by business day \(agreement.terms.reportBusinessDay)", value: $agreement.terms.reportBusinessDay, in: 5...25)
                Stepper("Notice to end: \(agreement.terms.noticeDays) days", value: $agreement.terms.noticeDays, in: 7...90, step: 1)
                Stepper("Liability cap: fees from the last \(agreement.terms.liabilityCapMonths) months", value: $agreement.terms.liabilityCapMonths, in: 1...12)
            }

            DisclosureGroup("Your business details", isExpanded: $showFirm) {
                VStack(alignment: .leading, spacing: VLSpacing.xs) {
                    field("Business name", $firm.firmName)
                    HStack { field("Your name", $firm.ownerName); field("Title", $firm.ownerTitle) }
                    HStack { field("City", $firm.city); field("State", $firm.state) }
                    field("County (for disputes)", $firm.county)
                    HStack { field("Email", $firm.email); field("Phone", $firm.phone) }
                }
                .padding(.top, VLSpacing.xs)
            }
            .font(VLTypography.body())

            if !clientRecords.isEmpty { recordsList }

            note("This template was written to protect your practice, but it isn't legal advice. Have a Texas attorney review it once before you rely on it, and consider professional liability (E&O) insurance.", color: VLColor.textMuted)
        }
    }

    private var recordsList: some View {
        group("AGREEMENTS ON FILE FOR THIS CLIENT") {
            ForEach(clientRecords) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VLStatusPill(r.status == .prepared ? .reviewNeeded : .verified, label: r.status.label)
                        Spacer()
                        Text(r.documentID).font(VLTypography.caption()).monospacedDigit().foregroundStyle(VLColor.textMuted)
                    }
                    Text("\(r.agreement.terms.package.label) · prepared \(r.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                    if let last = r.events.last { Text(last.text).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted) }
                    HStack {
                        if let url = AgreementService.signedURL(r) { Button("Open Signed Copy") { NSWorkspace.shared.open(url) } }
                        if r.status == .prepared {
                            Button("Record Signed Copy…") { recordReturned(r) }
                        } else {
                            Button("Send Signed Copy to Client…") { sendExecuted(r) }
                        }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AgreementService.folder(r)]) }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: VLSpacing.sm) {
            if let busy { ProgressView().controlSize(.small); Text(busy).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted) }
            Spacer()
            Button("Save PDF…") { run("Creating the PDF…") { r in PDFExport.save(AgreementService.reviewPDFURL(r), suggestedName: AgreementService.baseName(r.agreement)) } }
            Button("Sign in Person…") { run("Preparing…") { r in signingRecord = r } }
            Button("Email to Client…") {
                run("Preparing the email…", needsEmail: true) { r in
                    if !AgreementService.composeEmail(r) {
                        AgreementService.emailViaBrowser(r)
                        message = "Mail isn't set up on this Mac, so I opened a new email addressed to \(r.agreement.client.contactEmail.isEmpty ? "the client" : r.agreement.client.contactEmail), copied the message text (paste it into the email), and showed the two files to attach in Finder."
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(busy != nil || !agreement.problems.isEmpty)
        .padding(VLSpacing.md)
    }

    private func run(_ label: String, needsEmail: Bool = false, then action: @escaping @MainActor (AgreementRecord) -> Void) {
        // A macOS text field only hands its text over when editing ends;
        // end it first so the field typed last (often the email) counts.
        NSApp.keyWindow?.makeFirstResponder(nil)
        busy = label
        Task { @MainActor in
            defer { busy = nil }
            await Task.yield()
            let snapshot = agreement
            guard snapshot.problems.isEmpty else { error = snapshot.problems.joined(separator: " "); return }
            if needsEmail && snapshot.client.contactEmail.trimmingCharacters(in: .whitespaces).isEmpty {
                error = "Add the signer's email address first — that's where the agreement goes."
                return
            }
            do {
                let record = try await AgreementService.prepare(snapshot)
                records = AgreementService.loadAll()
                action(record)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func sendExecuted(_ r: AgreementRecord) {
        do {
            let (_, composed) = try AgreementService.sendExecutedCopy(r)
            records = AgreementService.loadAll()
            if !composed { message = "Mail isn't set up on this Mac, so I opened a new email to the client, copied the message text (paste it in), and showed the signed PDF to attach in Finder." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func recordReturned(_ r: AgreementRecord) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .heic]
        panel.message = "Choose the signed agreement the client sent back"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let (_, check) = try AgreementService.recordReturnedCopy(r, file: url)
            records = AgreementService.loadAll()
            message = "Saved. \(check)"
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Small pieces

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text(title).font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.textMuted)
                content()
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func money(_ label: String, _ value: Binding<Money>) -> some View {
        HStack {
            Text(label).font(VLTypography.body())
            Spacer()
            Text("$").foregroundStyle(VLColor.textMuted)
            TextField(label, value: Binding(get: { Double(value.wrappedValue.minorUnits) / 100 },
                                            set: { value.wrappedValue = Money(minorUnits: Int64(($0 * 100).rounded()), currency: .usd) }),
                      format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder).frame(width: 110).multilineTextAlignment(.trailing)
        }
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text).font(VLTypography.caption()).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct PreviewItem: Identifiable { let url: URL; var id: String { url.path } }
}

/// The client signs on this Mac: the same signing page the client would
/// receive by email, with a bridge that hands the signature back to the app.
struct InPersonSigningSheet: View {
    let record: AgreementRecord
    let onDone: (AgreementRecord?) -> Void
    @State private var status: String?
    @State private var failed: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in person — \(record.agreement.client.legalName)").font(VLTypography.cardTitle())
                Spacer()
                if let status { ProgressView().controlSize(.small); Text(status).font(VLTypography.caption()) }
                if let failed { Text(failed).font(VLTypography.caption()).foregroundStyle(.red) }
                Button("Cancel") { onDone(nil) }.keyboardShortcut(.cancelAction)
            }
            .padding(VLSpacing.md)
            Divider()
            AgreementWebView(html: EngagementAgreementHTML.render(record.agreement, mode: .signing, providerSignedOn: record.preparedOn)) { body in
                let payload = SignedPayload(body)
                status = "Saving the signed agreement…"
                Task { @MainActor in
                    do {
                        let updated = try await AgreementService.recordInPersonSignature(record, payload: payload)
                        onDone(updated)
                    } catch {
                        status = nil
                        failed = error.localizedDescription
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 820)
    }
}

/// Local HTML only: every navigation away from the loaded page is refused,
/// and the only message accepted is the signing page's signature payload.
struct AgreementWebView: NSViewRepresentable {
    let html: String
    let onSigned: ((([String: Any]) -> Void))?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if onSigned != nil { config.userContentController.add(WeakHandler(context.coordinator), name: "vlAgreement") }
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onSigned = onSigned
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "vlAgreement")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSigned: (([String: Any]) -> Void)?
        var lastHTML: String?
        var delivered = false

        func receive(_ body: Any) {
            guard !delivered, let payload = body as? [String: Any] else { return }
            delivered = true
            onSigned?(payload)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let url = action.request.url
            if url?.scheme == "mailto" { decisionHandler(.cancel); return }
            decisionHandler(url == nil || url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }

    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: Coordinator?
        init(_ target: Coordinator) { self.target = target }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let body = message.body
            MainActor.assumeIsolated { target?.receive(body) }
        }
    }
}
