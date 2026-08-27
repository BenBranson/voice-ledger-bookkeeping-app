import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 9 (Sales Tax Review, Type A + C,
/// skippable per client) — see `Core/SalesTax.swift`'s doc comment for the
/// scoped-down slice this is (codes/rates/agencies only, no liability
/// balances or transaction-level detail).
public struct SalesTaxReviewView: View {
    private let environment: VLEnvironmentTone
    private let taxCodes: [TaxCode]
    private let taxRates: [TaxRate]
    private let taxAgencies: [TaxAgency]
    private let isLoading: Bool
    private let errorMessage: String?
    private let attestation: SalesTaxAttestation
    private let onRefresh: () -> Void
    private let onSaveAttestation: (SalesTaxAttestation) -> Void

    @State private var actorNameDraft: String = NSFullUserName()
    @State private var noteDraft: String = ""

    public init(
        environment: VLEnvironmentTone,
        taxCodes: [TaxCode],
        taxRates: [TaxRate],
        taxAgencies: [TaxAgency],
        isLoading: Bool,
        errorMessage: String?,
        attestation: SalesTaxAttestation,
        onRefresh: @escaping () -> Void,
        onSaveAttestation: @escaping (SalesTaxAttestation) -> Void
    ) {
        self.environment = environment
        self.taxCodes = taxCodes
        self.taxRates = taxRates
        self.taxAgencies = taxAgencies
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.attestation = attestation
        self.onRefresh = onRefresh
        self.onSaveAttestation = onSaveAttestation
        _noteDraft = State(initialValue: attestation.note ?? "")
    }

    private func agencyName(for id: String?) -> String {
        guard let id, let agency = taxAgencies.first(where: { $0.id == id }) else { return "—" }
        return agency.displayName
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Sales Tax Review")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("Reads tax codes, rates, and agencies directly from QuickBooks. Does not compute liability balances or review transaction-level tax detail — those aren't built yet. Skippable per client: not every engagement includes sales tax.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                HStack {
                    Button(isLoading ? "Loading…" : "Refresh") { onRefresh() }
                        .disabled(isLoading)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(VLTypography.caption())
                            .foregroundStyle(.red)
                    }
                }

                if taxCodes.isEmpty && taxRates.isEmpty && taxAgencies.isEmpty && !isLoading {
                    VLCard {
                        Text(errorMessage == nil ? "No sales tax data loaded yet. Tap Refresh." : "Nothing to show.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    agenciesSection
                    ratesSection
                    codesSection
                }

                attestationSection
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var agenciesSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("TAX AGENCIES")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                if taxAgencies.isEmpty {
                    Text("None.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(taxAgencies) { agency in
                        Text(agency.displayName)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                }
            }
        }
    }

    private var ratesSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("TAX RATES")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                if taxRates.isEmpty {
                    Text("None.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(taxRates) { rate in
                        HStack {
                            Text(rate.name)
                                .font(VLTypography.body())
                                .foregroundStyle(rate.isActive ? VLColor.textPrimary : VLColor.textMuted)
                            Text("(\(agencyName(for: rate.agencyID)))")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                            Spacer()
                            Text(rate.ratePercent.map { String(format: "%.2f%%", $0) } ?? "—")
                                .font(VLTypography.tabularNumeric())
                                .foregroundStyle(VLColor.textPrimary)
                            if !rate.isActive {
                                VLStatusPill(.notChecked, label: "Inactive")
                            }
                        }
                    }
                }
            }
        }
    }

    private var codesSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("TAX CODES")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                if taxCodes.isEmpty {
                    Text("None.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(taxCodes) { code in
                        HStack {
                            Text(code.name)
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textPrimary)
                            Spacer()
                            if let taxable = code.taxable {
                                VLStatusPill(taxable ? .reviewNeeded : .verified, label: taxable ? "Taxable" : "Non-taxable")
                            }
                        }
                    }
                }
            }
        }
    }

    private var attestationSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("FILING STATUS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text("Confirm filing jurisdiction, frequency, whether the return and payment were submitted, and any Tax Center adjustments or outstanding notices — none of this is API-confirmable, so it's your own attestation.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if attestation.filingStatusConfirmed {
                    HStack {
                        VLStatusPill(.verified, label: "Confirmed")
                        if let attestedBy = attestation.attestedBy, let attestedAt = attestation.attestedAt {
                            Text("by \(attestedBy) on \(attestedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                        Spacer()
                    }
                    if let note = attestation.note, !note.isEmpty {
                        Text(note)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                    Button("Update") {
                        onSaveAttestation(SalesTaxAttestation(filingStatusConfirmed: false, attestedBy: nil, attestedAt: nil, note: attestation.note))
                    }
                    .buttonStyle(.bordered)
                } else {
                    TextField("Optional note (jurisdiction, frequency, filed status, adjustments, notices)", text: $noteDraft)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Your name", text: $actorNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Button("Confirm Filing Status Reviewed") {
                            onSaveAttestation(SalesTaxAttestation(filingStatusConfirmed: true, attestedBy: actorNameDraft, attestedAt: Date(), note: noteDraft.isEmpty ? nil : noteDraft))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(actorNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
