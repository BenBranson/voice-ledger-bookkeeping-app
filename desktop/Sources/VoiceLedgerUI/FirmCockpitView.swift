import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit — see `Core/FirmCockpit.swift`'s
/// doc comment for exactly what this slice covers and what it deliberately
/// doesn't (client-blocked items, deadlines — this app tracks neither).
/// **Read-only summary, not a switcher**: tapping a client here does not
/// make it the active connection — this app still runs as exactly one
/// realm per launch. Actually switching which client's data the rest of
/// the app shows is separate, larger work (a connected-client registry
/// already exists via this same backend endpoint, but re-instantiating
/// `AppState`/`ClientStore`/the sync session for a newly-picked realm
/// on demand is not built).
public struct FirmCockpitView: View {
    private let environment: VLEnvironmentTone
    private let summaries: [ClientCockpitSummary]
    private let isLoading: Bool
    private let errorMessage: String?
    private let onRefresh: () -> Void

    public init(environment: VLEnvironmentTone, summaries: [ClientCockpitSummary], isLoading: Bool, errorMessage: String?, onRefresh: @escaping () -> Void) {
        self.environment = environment
        self.summaries = summaries
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Firm Cockpit")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("Every connected client, from what's already been synced locally — not a live re-check of each one. Doesn't show client-blocked items or deadlines; this app doesn't track either yet. Selecting a client here doesn't switch the app to it — that's separate work, not built.")
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

                if summaries.isEmpty && !isLoading {
                    VLCard {
                        Text(errorMessage == nil ? "No connected clients found." : "Nothing to show.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    ForEach(summaries) { summary in
                        clientCard(summary)
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private func clientCard(_ summary: ClientCockpitSummary) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text(summary.client.companyName ?? "(unnamed company)")
                            .font(VLTypography.cardTitle())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("realmId: \(summary.client.realmID.rawValue)")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    Spacer()
                    VLEnvironmentBadge(summary.client.environment == .production ? .production : .sandbox)
                    VLStatusPill(StatusMapping.status(for: summary.client.lastHealthCheckStatus))
                }

                Divider().overlay(VLColor.border)

                HStack(spacing: VLSpacing.lg) {
                    metric(label: "Open findings", value: "\(summary.openFindingsCount)", emphasize: summary.openFindingsCount > 0)
                    metric(label: "Urgent", value: "\(summary.urgentFindingsCount)", emphasize: summary.urgentFindingsCount > 0)
                    metric(label: "Checklist", value: "\(summary.checklistCompleted)/\(summary.checklistTotal)", emphasize: false)
                    metric(label: "Statement lines imported", value: "\(summary.importedStatementLineCount)", emphasize: false)
                }

                HStack {
                    Text(summary.client.writeEnabled ? "Write-Enabled" : "Read-Only")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    if let lastActivity = summary.lastLocalActivityAt {
                        Text("Last local activity \(lastActivity.formatted(date: .abbreviated, time: .shortened))")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    } else {
                        Text("No local activity recorded yet")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
            }
        }
    }

    private func metric(label: String, value: String, emphasize: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(value)
                .font(VLTypography.metricLarge())
                .foregroundStyle(emphasize ? .red : VLColor.textPrimary)
            Text(label)
                .font(VLTypography.caption())
                .foregroundStyle(VLColor.textMuted)
        }
    }
}
