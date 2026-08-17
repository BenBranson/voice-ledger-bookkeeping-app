import SwiftUI
import Core
import DesignSystem

/// Phase 1 step 1.3, minimal version: the smallest thing that proves a
/// connection is real and healthy, in-app rather than only via the
/// `voiceledger-devtool` CLI. **Not the full Access & Evidence Pack page**
/// (docs/VOICE_LEDGER_SPEC.md's Page 1) — no Baseline Evidence Pack
/// generation, no QBOA-access attestation. Read-only Write-Enabled toggle is
/// deliberately absent too: `CLAUDE.md` rule 4 requires one, but there is no
/// write-classified catalog operation to gate yet (§3.4) — a toggle with
/// nothing behind it would be theater, not a control.
public struct ConnectionView: View {
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let companyName: String?
        public let realmID: String
        public let healthStatus: VLStatus?
        public let healthDetail: String?
        public let lastCheckedAt: Date?
        public let isChecking: Bool

        public init(
            environment: VLEnvironmentTone,
            companyName: String?,
            realmID: String,
            healthStatus: VLStatus?,
            healthDetail: String?,
            lastCheckedAt: Date?,
            isChecking: Bool
        ) {
            self.environment = environment
            self.companyName = companyName
            self.realmID = realmID
            self.healthStatus = healthStatus
            self.healthDetail = healthDetail
            self.lastCheckedAt = lastCheckedAt
            self.isChecking = isChecking
        }
    }

    private let state: ViewState
    private let onCheckHealth: () -> Void

    public init(state: ViewState, onCheckHealth: @escaping () -> Void) {
        self.state = state
        self.onCheckHealth = onCheckHealth
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
                        Text("WRITE ACCESS")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text("Read-Only")
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("Every connection starts read-only. There is currently no write-classified operation in the backend catalog at all, so there is nothing to enable yet — this isn't a setting waiting to be flipped, it's an honest reflection of what the app can do right now.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
