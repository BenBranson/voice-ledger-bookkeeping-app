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
    /// Owner directive (2026-09-07): "connect Claude API... for the tool
    /// loop" — a selectable backend for Voice Ledger's own in-app voice
    /// assistant. Primitive params only, same "no Core/app-layer
    /// dependency" boundary this module already holds everywhere else —
    /// the actual model enum/persistence (`VoiceToolLoopModel`,
    /// `VoiceToolLoopPreference`) lives in `VoiceLedgerApp`, which
    /// translates to/from this plain `id`/`label` shape.
    public struct VoiceModelOption: Identifiable {
        public let id: String
        public let label: String
        /// `false` when this option needs a backend API key that isn't
        /// set — shown, but not selectable, rather than hidden entirely,
        /// so picking it tells the bookkeeper what's missing instead of
        /// the option just not existing.
        public let isAvailable: Bool

        public init(id: String, label: String, isAvailable: Bool) {
            self.id = id
            self.label = label
            self.isAvailable = isAvailable
        }
    }

    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let companyName: String?
        public let realmID: String
        public let healthStatus: VLStatus?
        public let healthDetail: String?
        public let lastCheckedAt: Date?
        /// QBO's own refresh-token expiry (2026-09-11), read off the same
        /// health-check response — `nil` until the first check, or for a
        /// realm connected before this field existed and not yet refreshed
        /// since. Never estimated client-side; see `HealthCheckResult`'s
        /// own doc comment.
        public let refreshTokenExpiresAt: Date?
        public let isChecking: Bool
        public let writeEnabled: Bool?
        public let isTogglingWriteAccess: Bool
        /// docs/VOICE_LEDGER_SPEC.md's AI Connection status + kill switch.
        /// `nil` until the first status check completes.
        public let aiStatus: AIStatus?
        public let isCheckingAIStatus: Bool
        public let isTogglingAIEnabled: Bool
        public let aiStatusError: String?
        public let voiceAssistantModelOptions: [VoiceModelOption]
        public let selectedVoiceAssistantModelID: String
        public let isDisconnecting: Bool
        public let disconnectError: String?

        public init(
            environment: VLEnvironmentTone,
            companyName: String?,
            realmID: String,
            healthStatus: VLStatus?,
            healthDetail: String?,
            lastCheckedAt: Date?,
            refreshTokenExpiresAt: Date? = nil,
            isChecking: Bool,
            writeEnabled: Bool?,
            isTogglingWriteAccess: Bool,
            aiStatus: AIStatus? = nil,
            isCheckingAIStatus: Bool = false,
            isTogglingAIEnabled: Bool = false,
            aiStatusError: String? = nil,
            voiceAssistantModelOptions: [VoiceModelOption] = [],
            selectedVoiceAssistantModelID: String = "",
            isDisconnecting: Bool = false,
            disconnectError: String? = nil
        ) {
            self.environment = environment
            self.companyName = companyName
            self.realmID = realmID
            self.healthStatus = healthStatus
            self.healthDetail = healthDetail
            self.lastCheckedAt = lastCheckedAt
            self.refreshTokenExpiresAt = refreshTokenExpiresAt
            self.isChecking = isChecking
            self.writeEnabled = writeEnabled
            self.isTogglingWriteAccess = isTogglingWriteAccess
            self.aiStatus = aiStatus
            self.isCheckingAIStatus = isCheckingAIStatus
            self.isTogglingAIEnabled = isTogglingAIEnabled
            self.aiStatusError = aiStatusError
            self.voiceAssistantModelOptions = voiceAssistantModelOptions
            self.selectedVoiceAssistantModelID = selectedVoiceAssistantModelID
            self.isDisconnecting = isDisconnecting
            self.disconnectError = disconnectError
        }
    }

    private let state: ViewState
    private let onCheckHealth: () -> Void
    private let onToggleWriteAccess: (Bool) -> Void
    private let onToggleAIEnabled: (Bool) -> Void
    private let onSelectVoiceAssistantModel: (String) -> Void
    private let onDisconnect: () -> Void
    @State private var isConfirmingDisconnect = false

    public init(
        state: ViewState,
        onCheckHealth: @escaping () -> Void,
        onToggleWriteAccess: @escaping (Bool) -> Void,
        onToggleAIEnabled: @escaping (Bool) -> Void = { _ in },
        onSelectVoiceAssistantModel: @escaping (String) -> Void = { _ in },
        onDisconnect: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onCheckHealth = onCheckHealth
        self.onToggleWriteAccess = onToggleWriteAccess
        self.onToggleAIEnabled = onToggleAIEnabled
        self.onSelectVoiceAssistantModel = onSelectVoiceAssistantModel
        self.onDisconnect = onDisconnect
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

                        Divider().overlay(VLColor.border)

                        refreshTokenExpirySection
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

                if !state.voiceAssistantModelOptions.isEmpty {
                    voiceAssistantModelSection
                }

                disconnectSection
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    /// docs/VOICE_LEDGER_SPEC.md's Connection Pages section: "a 30-day/
    /// 14-day refresh-token expiry warning." Built 2026-09-11 from real
    /// data QBO already returns on every token exchange/refresh
    /// (`x_refresh_token_expires_in`) and this backend was previously
    /// discarding — never an estimate. In practice this window keeps
    /// rolling forward by ~100 days every time the app actually uses the
    /// connection, so a real warning here means the connection has
    /// genuinely gone unused (or was revoked) for a long stretch, not that
    /// anything is imminently wrong on a normally-used connection.
    private var disconnectSection: some View {
        VLCard(accentRail: .red) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("DISCONNECT FROM QUICKBOOKS")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text(state.companyName ?? "This client")
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                    Spacer()
                    Button(state.isDisconnecting ? "Disconnecting…" : "Disconnect…", role: .destructive) {
                        isConfirmingDisconnect = true
                    }
                    .disabled(state.isDisconnecting)
                }
                Text("Revokes Voice Ledger's access to this QuickBooks company at Intuit, deletes its stored tokens, and deletes this client's local Voice Ledger data (findings, notes, AI history). Nothing in QuickBooks itself is changed. Reports you already exported are kept. To use this client again, reconnect it through Intuit.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
                if let error = state.disconnectError {
                    Text(error)
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(
            "Disconnect \(state.companyName ?? "this client") from QuickBooks?",
            isPresented: $isConfirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect and Delete Local Data", role: .destructive) { onDisconnect() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This revokes access at Intuit and permanently deletes this client's local Voice Ledger data. It can't be undone.")
        }
    }

    private var refreshTokenExpirySection: some View {
        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
            Text("REFRESH TOKEN")
                .font(VLTypography.eyebrow())
                .tracking(VLTypography.eyebrowTracking)
                .foregroundStyle(VLColor.textMuted)
            if let expiresAt = state.refreshTokenExpiresAt {
                let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0
                HStack(spacing: VLSpacing.xs) {
                    VLStatusPill(refreshTokenStatus(daysRemaining: daysRemaining), label: refreshTokenLabel(daysRemaining: daysRemaining))
                    Text("Valid until \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                }
            } else {
                VLStatusPill(.notChecked, label: "Unknown until next health check")
            }
        }
    }

    private func refreshTokenStatus(daysRemaining: Int) -> VLStatus {
        if daysRemaining <= 3 { return .urgent }
        if daysRemaining <= 14 { return .reviewNeeded }
        return .verified
    }

    private func refreshTokenLabel(daysRemaining: Int) -> String {
        if daysRemaining < 0 { return "Expired — reconnect required" }
        if daysRemaining <= 3 { return "Expires in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") — reconnect now" }
        if daysRemaining <= 14 { return "Expires in \(daysRemaining) days — reconnect soon" }
        return "\(daysRemaining) days remaining"
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
                Text("\(aiProviderDescription) Turning this off disables every AI feature app-wide; every deterministic rule, finding, calculation, and report keeps working exactly the same either way.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    /// Owner directive (2026-09-07): "connect Claude API... for the tool
    /// loop" — which model answers Voice Ledger's own in-app voice
    /// assistant (navigation, chart generation, comparisons), independent
    /// of the Ask AI panel's own provider above.
    private var voiceAssistantModelSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("VOICE ASSISTANT MODEL")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                    ForEach(state.voiceAssistantModelOptions) { option in
                        Button {
                            onSelectVoiceAssistantModel(option.id)
                        } label: {
                            HStack {
                                Image(systemName: state.selectedVoiceAssistantModelID == option.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(option.isAvailable ? VLColor.cyan : VLColor.textMuted)
                                Text(option.label)
                                    .font(VLTypography.body())
                                    .foregroundStyle(option.isAvailable ? VLColor.textPrimary : VLColor.textMuted)
                                Spacer()
                                if !option.isAvailable {
                                    Text("Needs backend API key")
                                        .font(VLTypography.caption())
                                        .foregroundStyle(VLColor.textMuted)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isAvailable)
                    }
                }
                Text("Chooses which model decides what the voice assistant does (navigate, pull up a chart, compare findings) when you speak or type a command — not the Ask AI panels above, which are separate. Tool-selection accuracy matters more here than for a plain question: a wrong tool call is a wrong action, not just a slower sentence.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)
            }
        }
    }

    private var aiStatusLabel: String {
        guard let aiStatus = state.aiStatus else {
            return state.isCheckingAIStatus ? "Checking…" : "Not yet checked"
        }
        if !aiStatus.configured { return "Not configured (no provider set on the backend)" }
        return aiStatus.enabled ? "On" : "Off"
    }

    /// Never hardcodes a provider name — the backend's actual config
    /// (`AIStatus.provider`/`.model`) decides what's true here, so this
    /// stays honest whether it's answering via local Ollama (free) or
    /// OpenAI (paid). The API key, when one exists, never leaves the
    /// backend either way.
    private var aiProviderDescription: String {
        guard let aiStatus = state.aiStatus, aiStatus.configured else {
            return "The Ask [AI] panel needs a provider configured on the backend."
        }
        switch aiStatus.provider {
        case "ollama":
            return "The Ask [AI] panel runs locally via Ollama\(aiStatus.model.map { " (\($0))" } ?? "") — free, and nothing leaves this machine."
        case "openai":
            return "The Ask [AI] panel is powered by OpenAI. The API key lives only in the backend — this app never sees or displays it."
        default:
            return "The Ask [AI] panel is configured on the backend."
        }
    }

    private var writeAccessLabel: String {
        switch state.writeEnabled {
        case .some(true): return "Write-Enabled"
        case .some(false): return "Read-Only"
        case nil: return "Checking…"
        }
    }
}
