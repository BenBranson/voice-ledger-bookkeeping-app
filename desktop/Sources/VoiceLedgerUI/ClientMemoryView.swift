import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Client Memory, With Approval."
/// Every rule created from `FindingDetailView`'s "Always Dismiss" button
/// needs somewhere visible to review and remove — a rule silently applying
/// forever with no way to see or undo it would be exactly the "silently"
/// the spec's own wording rules out.
public struct ClientMemoryView: View {
    private let environment: VLEnvironmentTone
    private let rules: [ClientMemoryRule]
    private let onForget: (ClientMemoryRule) -> Void

    public init(environment: VLEnvironmentTone, rules: [ClientMemoryRule], onForget: @escaping (ClientMemoryRule) -> Void) {
        self.environment = environment
        self.rules = rules
        self.onForget = onForget
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Client Memory")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("Rules created from a finding's \"Always Dismiss\" button. Each one auto-dismisses matching findings on every future sync — logged to the Activity Log every time, never silent.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                if rules.isEmpty {
                    VLCard {
                        Text("No client memory rules yet.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    ForEach(rules) { rule in
                        VLCard {
                            HStack {
                                VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                    Text("\(rule.ruleID.rawValue) — \(rule.vendorName)")
                                        .font(VLTypography.body())
                                        .foregroundStyle(VLColor.textPrimary)
                                    Text("Created by \(rule.createdBy)" + (rule.note.map { " — \($0)" } ?? ""))
                                        .font(VLTypography.caption())
                                        .foregroundStyle(VLColor.textMuted)
                                }
                                Spacer()
                                Button("Forget") { onForget(rule) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
