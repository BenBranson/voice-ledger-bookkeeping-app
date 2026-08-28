import SwiftUI
import Core
import DesignSystem

/// Phase 1 step 1.3, minimal version: the smallest thing that proves a
/// connection is real and healthy, in-app rather than only via the
/// `voiceledger-devtool` CLI. **Not the full Access & Evidence Pack page**
/// (docs/VOICE_LEDGER_SPEC.md's Page 1) — no Baseline Evidence Pack
/// generation, no QBOA-access attestation.
///
/// **The Write Access toggle is real**, not theater: it flips a genuine,
/// persisted, live-verified backend flag (`CLAUDE.md` rule 4's access-mode
/// gate — every realm starts Read-Only, `backend/src/auth/tokenStore.ts`'s
/// `write_enabled` column). It is built ahead of its first consumer — no
/// write-classified catalog operation exists yet (§3.4), so flipping this
/// on doesn't unlock any actual capability today — but the control itself
/// is functional, tested, and safe to exercise, the same way a circuit
/// breaker is installed before the second floor is wired.
public struct ConnectionView: View {
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let companyName: String?
        public let realmID: String
        public let healthStatus: VLStatus?
        public let healthDetail: String?
        public let lastCheckedAt: Date?
        public let isChecking: Bool
        public let writeEnabled: Bool?
        public let isTogglingWriteAccess: Bool
        /// docs/VOICE_LEDGER_SPEC.md's AI Connection status + kill switch.
        /// `nil` until the first status check completes.
        public let aiStatus: AIStatus?
        public let isCheckingAIStatus: Bool
        public let isTogglingAIEnabled: Bool
        public let aiStatusError: String?

        public init(
            environment: VLEnvironmentTone,
            companyName: String?,
            realmID: String,
            healthStatus: VLStatus?,
            healthDetail: String?,
            lastCheckedAt: Date?,
            isChecking: Bool,
            writeEnabled: Bool?,
            isTogglingWriteAccess: Bool,
            aiStatus: AIStatus? = nil,
            isCheckingAIStatus: Bool = false,
            isTogglingAIEnabled: Bool = false,
            aiStatusError: String? = nil
        ) {
            self.environment = environment
            self.companyName = companyName
            self.realmID = realmID
            self.healthStatus = healthStatus
            self.healthDetail = healthDetail
            self.lastCheckedAt = lastCheckedAt
            self.isChecking = isChecking
            self.writeEnabled = writeEnabled
            self.isTogglingWriteAccess = isTogglingWriteAccess
            self.aiStatus = aiStatus
            self.isCheckingAIStatus = isCheckingAIStatus
            self.isTogglingAIEnabled = isTogglingAIEnabled
            self.aiStatusError = aiStatusError
        }
    }

    private let state: ViewState
    private let onCheckHealth: () -> Void
    private let onToggleWriteAccess: (Bool) -> Void
    private let onToggleAIEnabled: (Bool) -> Void

    public init(
        state: ViewState,
        onCheckHealth: @escaping () -> Void,
        onToggleWriteAccess: @escaping (Bool) -> Void,
        onToggleAIEnabled: @escaping (Bool) -> Void = { _ in }
    ) {
        self.state = state
        self.onCheckHealth = onCheckHealth
        self.onToggleWriteAccess = onToggleWriteAccess
        self.onToggleAIEnabled = onToggleAIEnabled
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Connection")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(state.environment)
                }

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                Text("COMPANY")
                                    .font(VLTypography.eyebrow())
                                    .tracking(VLTypography.eyebrowTracking)
                                    .foregroundStyle(VLColor.textMuted)
                                Text(state.companyName ?? "Not yet checked")
                                    .font(VLTypography.cardTitle())
                                    .foregroundStyle(VLColor.textPrimary)
                                Text("realmId: \(state.realmID)")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            }
                            Spacer()
                        }

                        Divider().overlay(VLColor.border)

                        HStack {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                Text("HEALTH")
                                    .font(VLTypography.eyebrow())
                                    .tracking(VLTypography.eyebrowTracking)
                                    .foregroundStyle(VLColor.textMuted)
                                if let status = state.healthStatus {
                                    VLStatusPill(status, label: state.healthDetail)
                                } else {
                                    VLStatusPill(.notChecked)
                                }
                                if let checkedAt = state.lastCheckedAt {
                                    Text("Checked \(checkedAt.formatted(date: .abbreviated, time: .standard))")
                                        .font(VLTypography.caption())
                                        .foregroundStyle(VLColor.textMuted)
                                }
                            }
                            Spacer()
                            Button(state.isChecking ? "Checking…" : "Check Health") {
                                onCheckHealth()
                            }
                            .disabled(state.isChecking)
                            .buttonStyle(.borderedProminent)
                        }

                        Text("A live, timestamped call to QuickBooks Online — never a cached assumption. Green here means the connection actually answered just now, not that it answered at some point in the past.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }

                VLCard(accentRail: VLColor.violet) {
                    VStack(alignment: .leading, spacing: VLSpacing.xs) {
                        HStack {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                Text("WRITE ACCESS")
                                    .font(VLTypography.eyebrow())
                                    .tracking(VLTypography.eyebrowTracking)
                                    .foregroundStyle(VLColor.textMuted)
                                Text(writeAccessLabel)
                                    .font(VLTypography.body())
                                    .foregroundStyle(VLColor.textPrimary)
                            }
                            Spacer()
                            if let writeEnabled = state.writeEnabled {
                                Toggle("", isOn: Binding(
                                    get: { writeEnabled },
                                    set: { onToggleWriteAccess($0) }
                                ))
                                .labelsHidden()
                                .disabled(state.isTogglingWriteAccess)
                            }
                        }
                        Text("Every connection starts read-only (CLAUDE.md rule 4). This toggle is real and persisted on the backend, but there is currently no write-classified operation in the catalog for it to unlock — enabling it does not yet let the app do anything it couldn't before.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }

                aiConnectionSection
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    /// docs/VOICE_LEDGER_SPEC.md's "Claude API Connection" section
    /// (OpenAI-backed per the owner's 2026-08-28 direction — see
    /// docs/VOICE_LEDGER_HANDOFF.md): "shows whether a key is configured
    /// and working, not the key itself... Kill switch: a single toggle
    /// that disables all AI features app-wide."
    private var aiConnectionSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("AI CONNECTION")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text(aiStatusLabel)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                    Spacer()
                    if let aiStatus = state.aiStatus, aiStatus.configured {
                        Toggle("", isOn: Binding(
                            get: { aiStatus.enabled },
                            set: { onToggleAIEnabled($0) }
                        ))
                        .labelsHidden()
                        .disabled(state.isTogglingAIEnabled)
                    }
                }
                if let aiStatusError = state.aiStatusError {
                    Text(aiStatusError)
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }
                Text("The Ask [AI] panel is powered by OpenAI. The API key lives only in the backend — this app never sees or displays it. Turning this off disables every AI feature app-wide; every deterministic rule, finding, calculation, and report keeps working exactly the same either way.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    private var aiStatusLabel: String {
        guard let aiStatus = state.aiStatus else {
            return state.isCheckingAIStatus ? "Checking…" : "Not yet checked"
        }
        if !aiStatus.configured { return "Not configured (no API key set on the backend)" }
        return aiStatus.enabled ? "On" : "Off"
    }

    private var writeAccessLabel: String {
        switch state.writeEnabled {
        case .some(true): return "Write-Enabled"
        case .some(false): return "Read-Only"
        case nil: return "Checking…"
        }
    }
}
