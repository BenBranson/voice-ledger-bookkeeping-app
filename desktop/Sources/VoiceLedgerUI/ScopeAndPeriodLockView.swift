import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 2 (Type A + C), scoped-down slice — see
/// `Core/PeriodLock.swift`'s doc comment for what's deliberately not
/// included (QBO's `BookCloseDate`, error codes 6200/6210).
public struct ScopeAndPeriodLockView: View {
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let servicesIncluded: Set<String>
        public let qboaAccountantAccessAttested: Bool
        public let attestedBy: String?
        public let attestedAt: Date?
        public let currentPeriod: AccountingPeriod
        public let periodLock: PeriodLock?
        /// Non-voided transactions dated on or before the current lock —
        /// computed by `PeriodLockCheck` (`CLAUDE.md` rule 1: this count is
        /// deterministic Swift, not a guess), empty when there's no lock.
        public let transactionsInLockedPeriod: [LedgerTransaction]

        public init(
            environment: VLEnvironmentTone,
            servicesIncluded: Set<String>,
            qboaAccountantAccessAttested: Bool,
            attestedBy: String?,
            attestedAt: Date?,
            currentPeriod: AccountingPeriod,
            periodLock: PeriodLock?,
            transactionsInLockedPeriod: [LedgerTransaction]
        ) {
            self.environment = environment
            self.servicesIncluded = servicesIncluded
            self.qboaAccountantAccessAttested = qboaAccountantAccessAttested
            self.attestedBy = attestedBy
            self.attestedAt = attestedAt
            self.currentPeriod = currentPeriod
            self.periodLock = periodLock
            self.transactionsInLockedPeriod = transactionsInLockedPeriod
        }
    }

    private let state: ViewState
    private let onToggleService: (String) -> Void
    private let onAttest: (_ actorName: String) -> Void
    private let onSetLock: (_ through: AccountingPeriod, _ note: String?) -> Void
    private let onClearLock: () -> Void

    @State private var actorNameDraft: String = NSFullUserName()
    @State private var lockYearDraft: Int
    @State private var lockMonthDraft: Int
    @State private var lockNoteDraft: String = ""

    public init(
        state: ViewState,
        onToggleService: @escaping (String) -> Void,
        onAttest: @escaping (_ actorName: String) -> Void,
        onSetLock: @escaping (_ through: AccountingPeriod, _ note: String?) -> Void,
        onClearLock: @escaping () -> Void
    ) {
        self.state = state
        self.onToggleService = onToggleService
        self.onAttest = onAttest
        self.onSetLock = onSetLock
        self.onClearLock = onClearLock
        let defaultTarget = state.periodLock?.lockedThrough ?? state.currentPeriod
        _lockYearDraft = State(initialValue: defaultTarget.year)
        _lockMonthDraft = State(initialValue: defaultTarget.month)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Scope & Period Lock")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(state.environment)
                }

                Text("Voice Ledger cannot read QuickBooks Online's own closing date in this sandbox (verified absent from the Preferences response) and cannot set it either. This page records engagement scope and enforces Voice Ledger's own, stricter lock — a local convention that warns here, but never blocks or changes anything in QBO.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                scopeSection
                attestationSection
                lockSection
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var scopeSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("Engagement scope")
                    .font(VLTypography.cardTitle())
                    .foregroundStyle(VLColor.textPrimary)
                Text("Which services are in scope for this client. Voice Ledger does not build AR/AP workflows, so those aren't listed.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                ForEach(EngagementScope.availableServices, id: \.self) { service in
                    Toggle(service, isOn: Binding(
                        get: { state.servicesIncluded.contains(service) },
                        set: { _ in onToggleService(service) }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var attestationSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("QBOA accountant access")
                    .font(VLTypography.cardTitle())
                    .foregroundStyle(VLColor.textPrimary)
                Text("Not verifiable via API — Voice Ledger records your attestation rather than checking it.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                if state.qboaAccountantAccessAttested {
                    HStack {
                        VLStatusPill(.verified, label: "Attested")
                        if let attestedBy = state.attestedBy, let attestedAt = state.attestedAt {
                            Text("by \(attestedBy) on \(attestedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                        Spacer()
                    }
                } else {
                    HStack {
                        TextField("Your name", text: $actorNameDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Button("Attest I have QBOA accountant access") { onAttest(actorNameDraft) }
                            .buttonStyle(.borderedProminent)
                            .disabled(actorNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private var lockSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("Period lock")
                    .font(VLTypography.cardTitle())
                    .foregroundStyle(VLColor.textPrimary)

                if let lock = state.periodLock {
                    HStack {
                        VLStatusPill(state.transactionsInLockedPeriod.isEmpty ? .verified : .reviewNeeded, label: "Locked through \(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month))")
                        Spacer()
                        Button("Unlock", role: .destructive) { onClearLock() }
                    }
                    Text("Set by \(lock.lockedBy) on \(lock.lockedAt.formatted(date: .abbreviated, time: .shortened))\(lock.note.map { " — \($0)" } ?? "")")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)

                    if state.transactionsInLockedPeriod.isEmpty {
                        Text("No transactions dated in the locked period from the last sync.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    } else {
                        Text("\(state.transactionsInLockedPeriod.count) transaction(s) from the last sync fall in the locked period — this is a local warning only, since Voice Ledger has no write path that this would block.")
                            .font(VLTypography.caption())
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                            ForEach(state.transactionsInLockedPeriod.prefix(20)) { txn in
                                HStack {
                                    Text(txn.vendorName ?? "(no name)")
                                        .font(VLTypography.body())
                                        .foregroundStyle(VLColor.textSecondary)
                                    Spacer()
                                    Text(txn.txnDate.formatted)
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(VLColor.textMuted)
                                    Text(txn.totalAmount.description)
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(VLColor.textMuted)
                                }
                            }
                            if state.transactionsInLockedPeriod.count > 20 {
                                Text("+ \(state.transactionsInLockedPeriod.count - 20) more")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            }
                        }
                    }
                } else {
                    Text("No lock set yet. Locking a period is a local convention — it warns Voice Ledger's own screens about transactions dated in or before that month, but does not touch QBO.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                }

                Divider()

                HStack {
                    Stepper("Month: \(lockMonthDraft)", value: $lockMonthDraft, in: 1...12)
                    Stepper("Year: \(lockYearDraft)", value: $lockYearDraft, in: 2000...2100)
                }
                TextField("Optional note", text: $lockNoteDraft)
                    .textFieldStyle(.roundedBorder)
                Button(state.periodLock == nil ? "Lock through this period" : "Update lock") {
                    onSetLock(AccountingPeriod(year: lockYearDraft, month: lockMonthDraft), lockNoteDraft.isEmpty ? nil : lockNoteDraft)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
