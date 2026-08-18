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

        public init(
            environment: VLEnvironmentTone,
            companyName: String?,
            realmID: String,
            healthStatus: VLStatus?,
            healthDetail: String?,
            lastCheckedAt: Date?,
            isChecking: Bool,
            writeEnabled: Bool?,
            isTogglingWriteAccess: Bool
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
        }
    }

    private let state: ViewState
    private let onCheckHealth: () -> Void
    private let onToggleWriteAccess: (Bool) -> Void

    public init(state: ViewState, onCheckHealth: @escaping () -> Void, onToggleWriteAccess: @escaping (Bool) -> Void) {
        self.state = state
        self.onCheckHealth = onCheckHealth
        self.onToggleWriteAccess = onToggleWriteAccess
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
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var writeAccessLabel: String {
        switch state.writeEnabled {
        case .some(true): return "Write-Enabled"
        case .some(false): return "Read-Only"
        case nil: return "Checking…"
        }
    }
}
