import SwiftUI
import AppKit
import Core
import DesignSystem

// Practice tools (owner directive 2026-10-02): compliance calendar, 13-week
// forecast, industry setup, scope requests, new-account alerts. Every figure
// here is computed in Core; these views only show it.

@MainActor private func pageHeader(_ title: String, _ environment: VLEnvironmentTone, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: VLSpacing.xs) {
        HStack {
            Text(title).font(VLTypography.pageTitle()).foregroundStyle(VLColor.textPrimary)
            Spacer()
            VLEnvironmentBadge(environment)
        }
        Text(subtitle).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)
    }
}

private func eyebrow(_ text: String) -> some View {
    Text(text).font(VLTypography.eyebrow()).tracking(VLTypography.eyebrowTracking).foregroundStyle(VLColor.textMuted)
}

// MARK: - New account alerts (Dashboard)

public struct NewAccountAlertsCard: View {
    let alerts: [NewAccountAlert]
    let onAcknowledge: (String) -> Void
    @Environment(\.qboLinks) private var qboLinks

    public init(alerts: [NewAccountAlert], onAcknowledge: @escaping (String) -> Void) {
        self.alerts = alerts
        self.onAcknowledge = onAcknowledge
    }

    public var body: some View {
        if !alerts.isEmpty {
            VLCard(accentRail: .orange) {
                VStack(alignment: .leading, spacing: VLSpacing.sm) {
                    VLStatusPill(.reviewNeeded, label: "\(alerts.count) new account\(alerts.count == 1 ? "" : "s") in QuickBooks")
                    Text("These appeared since an earlier sync. Each needs monthly statements and reconciliation; ask the client what it is if you didn't know about it.")
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                    ForEach(alerts) { alert in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.name).font(VLTypography.body()).foregroundStyle(VLColor.textPrimary)
                                Text("\(alert.type) · first seen \(alert.firstSeenAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                            }
                            Spacer()
                            QBOLinkButton(qboLinks.account(id: alert.accountID))
                            Button("Added to my reconciliation list") { onAcknowledge(alert.accountID) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 13-week cash flow forecast

public struct ThirteenWeekForecastCard: View {
    let forecast: ThirteenWeekForecast?
    let planned: [PlannedCashItem]
    let onAdd: (PlannedCashItem) -> Void
    let onRemove: (String) -> Void
    @State private var week = 1
    @State private var itemDescription = ""
    @State private var amountText = ""
    @State private var isOutflow = true

    public init(forecast: ThirteenWeekForecast?, planned: [PlannedCashItem], onAdd: @escaping (PlannedCashItem) -> Void, onRemove: @escaping (String) -> Void) {
        self.forecast = forecast
        self.planned = planned
        self.onAdd = onAdd
        self.onRemove = onRemove
    }

    private func dateLabel(_ d: AccountingDate) -> String { ClientText.polish(d.formatted).replacingOccurrences(of: ", \(d.year)", with: "") }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                eyebrow("13-WEEK CASH FLOW FORECAST")
                guard let forecast else {
                    return AnyView(Text("Needs today's cash balance from the Balance Sheet. Sync, then come back.")
                        .font(VLTypography.caption()).foregroundStyle(.orange))
                }
                return AnyView(VStack(alignment: .leading, spacing: VLSpacing.sm) {
                    if let negative = forecast.firstNegativeWeek {
                        Text("Cash goes below zero in week \(negative.number) (week of \(dateLabel(negative.start))): \(negative.endingCash.accountingDescription).")
                            .font(VLTypography.body()).foregroundStyle(.red)
                    } else if let low = forecast.lowestWeek {
                        Text("Lowest point: week \(low.number) (week of \(dateLabel(low.start))), \(low.endingCash.accountingDescription).")
                            .font(VLTypography.body()).foregroundStyle(VLColor.textPrimary)
                    }
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                ForEach(["Week", "Starts", "Collections", "Bills", "Recurring", "Planned", "Ending cash"], id: \.self) {
                                    Text($0).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).frame(width: 100, alignment: .trailing)
                                }
                            }
                            ForEach(forecast.weeks) { w in
                                HStack {
                                    Text("\(w.number)").frame(width: 100, alignment: .trailing)
                                    Text(dateLabel(w.start)).frame(width: 100, alignment: .trailing)
                                    Text(w.collections.accountingDescription).frame(width: 100, alignment: .trailing)
                                    Text(w.billPayments.minorUnits == 0 ? "—" : "(\(w.billPayments.accountingDescription))").frame(width: 100, alignment: .trailing)
                                    Text(w.recurringCharges.minorUnits == 0 ? "—" : "(\(w.recurringCharges.accountingDescription))").frame(width: 100, alignment: .trailing)
                                    Text(w.planned.minorUnits == 0 ? "—" : w.planned.accountingDescription).frame(width: 100, alignment: .trailing)
                                    Text(w.endingCash.accountingDescription).fontWeight(.semibold)
                                        .foregroundStyle(w.endingCash.minorUnits < 0 ? .red : VLColor.textPrimary).frame(width: 100, alignment: .trailing)
                                }
                                .font(VLTypography.tabularNumeric()).foregroundStyle(VLColor.textSecondary)
                            }
                        }
                    }
                    Text("Starts from today's cash, \(forecast.startingCash.accountingDescription). Customer and vendor balances carry no exact due dates, so each aging bucket is spread evenly: current over weeks 1–4, 1–30 days late over weeks 5–8, 31–90 days late over weeks 9–13. Over 90 days late is never counted. Recurring charges land on their projected dates. Planned items are yours.")
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)

                    Divider().overlay(VLColor.border)
                    eyebrow("PLANNED ITEMS (WHAT-IF)")
                    ForEach(planned) { item in
                        HStack {
                            Text("Week \(item.week): \(item.description)").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                            Spacer()
                            Text(item.amount.accountingDescription).font(VLTypography.tabularNumeric())
                            Button { onRemove(item.id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Picker("Week", selection: $week) { ForEach(1...13, id: \.self) { Text("Week \($0)").tag($0) } }.frame(width: 120)
                        Picker("", selection: $isOutflow) { Text("Money out").tag(true); Text("Money in").tag(false) }.frame(width: 120)
                        TextField("What (e.g. trailer down payment)", text: $itemDescription).textFieldStyle(.roundedBorder)
                        TextField("Amount", text: $amountText).textFieldStyle(.roundedBorder).frame(width: 110)
                        Button("Add") {
                            guard let money = AmountSearch.parseAmount(amountText), !itemDescription.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let cents = abs(money.minorUnits) * (isOutflow ? -1 : 1)
                            onAdd(PlannedCashItem(week: week, description: itemDescription, amount: Money(minorUnits: cents, currency: .usd)))
                            itemDescription = ""; amountText = ""
                        }
                    }
                })
            }
        }
    }
}

// MARK: - Compliance calendar page

public struct ComplianceCalendarView: View {
    let environment: VLEnvironmentTone
    let clientName: String
    let deadlines: [ComplianceDeadline]
    let checks: [ComplianceCheck]
    let nexusRows: [NexusStateRow]
    let nexusNote: String?
    let onLoadHistory: () -> Void
    let onSave: (ClientPracticeProfile) -> Void
    @State private var draft: ClientPracticeProfile
    private let saved: ClientPracticeProfile

    public init(environment: VLEnvironmentTone, clientName: String, profile: ClientPracticeProfile, deadlines: [ComplianceDeadline], checks: [ComplianceCheck],
                nexusRows: [NexusStateRow], nexusNote: String?, onLoadHistory: @escaping () -> Void, onSave: @escaping (ClientPracticeProfile) -> Void) {
        self.environment = environment
        self.clientName = clientName
        self.deadlines = deadlines
        self.checks = checks
        self.nexusRows = nexusRows
        self.nexusNote = nexusNote
        self.onLoadHistory = onLoadHistory
        self.onSave = onSave
        self.saved = profile
        _draft = State(initialValue: profile)
    }

    private func who(_ r: ComplianceDeadline.Responsible) -> String {
        switch r {
        case .client: return "Client files"
        case .bookkeeper: return "You"
        case .cpa: return "CPA / client"
        }
    }

    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    public var body: some View {
        let checked = Set(StateComplianceRules.verifiedStates)
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                pageHeader("Compliance Calendar", environment, "Every filing and delivery date for \(clientName) over the next 120 days, from the profile below. Federal dates apply in every state; state dates appear only for states whose rules Voice Ledger has checked on the state's own websites (\(checked.count) so far). Dates on a weekend or federal holiday move to the next business day. Filing stays the client's or CPA's job under the engagement agreement.")
                if !saved.reviewed {
                    VLCard(accentRail: .orange) {
                        Text("This client's profile hasn't been reviewed. Set the state, entity type and filings, then save.")
                            .font(VLTypography.body()).foregroundStyle(.orange)
                    }
                }
                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("CLIENT PROFILE")
                        Picker("State", selection: $draft.state) {
                            ForEach(StateComplianceRules.allStates, id: \.code) { s in
                                Text("\(s.name)\(checked.contains(s.code) ? "  ✓ checked" : "")").tag(s.code)
                            }
                        }.frame(maxWidth: 360)
                        Picker("Entity type", selection: $draft.entityType) {
                            ForEach(ClientPracticeProfile.EntityType.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.frame(maxWidth: 360)
                        if draft.entityType.isRegisteredEntity {
                            HStack {
                                Picker("Formed in", selection: Binding(get: { draft.formationMonth ?? 0 }, set: { draft.formationMonth = $0 == 0 ? nil : $0 })) {
                                    Text("Month unknown").tag(0)
                                    ForEach(1...12, id: \.self) { Text(Self.months[$0 - 1]).tag($0) }
                                }.frame(maxWidth: 260)
                                TextField("Year", value: Binding(get: { draft.formationYear }, set: { draft.formationYear = $0 }), format: .number.grouping(.never))
                                    .textFieldStyle(.roundedBorder).frame(width: 80)
                            }
                        }
                        Picker("Sales tax filing", selection: $draft.salesTaxFrequency) {
                            ForEach(ClientPracticeProfile.SalesTaxFrequency.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.frame(maxWidth: 360)
                        Toggle("Pays contractors (1099-NEC, January 31)", isOn: $draft.files1099s)
                        Toggle("Has employees (941, W-2, 940, state payroll reports)", isOn: $draft.hasEmployees)
                        Toggle("Interstate trucking (IFTA quarterly)", isOn: $draft.filesIFTA)
                        Toggle("Truck 55,000 lb or more (Form 2290, August 31)", isOn: $draft.filesForm2290)
                        Stepper("Statements due from client: day \(draft.statementsDueDay) of the month", value: $draft.statementsDueDay, in: 1...28)
                        Stepper("Monthly package due: business day \(draft.reportBusinessDay)", value: $draft.reportBusinessDay, in: 1...20)
                        HStack {
                            Button("Save profile") { onSave(draft) }.buttonStyle(.borderedProminent)
                            if draft != saved { Text("Unsaved changes").font(VLTypography.caption()).foregroundStyle(.orange) }
                        }
                    }
                }
                if !checks.isEmpty {
                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.sm) {
                            eyebrow("VERIFY WITH THE STATE OR CPA")
                            ForEach(checks) { c in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                                    Text(c.detail).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("NEXT 120 DAYS")
                        if deadlines.isEmpty {
                            Text("Nothing due in the next 120 days.").font(VLTypography.body()).foregroundStyle(VLColor.textMuted)
                        }
                        ForEach(deadlines) { d in
                            HStack(alignment: .top) {
                                Text(ClientText.polish(d.date.formatted)).font(VLTypography.tabularNumeric()).foregroundStyle(VLColor.textPrimary).frame(width: 120, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title).font(VLTypography.body()).foregroundStyle(VLColor.textPrimary)
                                    Text(d.detail).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Text(who(d.responsible)).font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                            }
                            Divider().overlay(VLColor.border)
                        }
                    }
                }
                VLCard(accentRail: nexusRows.contains(where: \.needsReview) ? .orange : nil) {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("SALES BY CUSTOMER STATE — LAST 12 MONTHS (ECONOMIC NEXUS SCREEN)")
                        Text("A business can owe sales tax in a state where it has no office once its sales into that state pass the state's threshold. This screens QuickBooks invoices by ship-to (else bill-to) state against each threshold; sales receipts and marketplace sales aren't included. Flagged states need a closer look with the CPA, not automatic registration.")
                            .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)
                        if let nexusNote {
                            HStack {
                                Text(nexusNote).font(VLTypography.caption()).foregroundStyle(.orange)
                                Button("Load 24-month history", action: onLoadHistory).controlSize(.small)
                            }
                        }
                        ForEach(nexusRows) { row in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(row.stateName)\(row.isHomeState ? " (home state)" : "")").font(VLTypography.body()).foregroundStyle(VLColor.textPrimary)
                                    Text("\(row.transactionCount) invoice\(row.transactionCount == 1 ? "" : "s") · threshold: \(row.threshold.description)\(row.thresholdChecked ? "" : " (screen only)")")
                                        .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).fixedSize(horizontal: false, vertical: true)
                                    if row.needsReview {
                                        Text(row.overThreshold ? "Over the threshold and no \(row.stateName) tax agency is set up in QuickBooks. Review with the CPA." : "Within 80% of the threshold. Watch it.")
                                            .font(VLTypography.caption()).foregroundStyle(row.overThreshold ? .red : .orange)
                                    } else if row.hasTaxAgency && !row.isHomeState {
                                        Text("Tax agency set up in QuickBooks.").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                                    }
                                }
                                Spacer()
                                Text(row.sales.accountingDescription).font(VLTypography.tabularNumeric()).foregroundStyle(VLColor.textPrimary)
                            }
                            Divider().overlay(VLColor.border)
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}

// MARK: - Industry setup page

public struct IndustrySetupView: View {
    let environment: VLEnvironmentTone
    let kind: IndustryTemplate.Kind
    let comparison: IndustryTemplate.Comparison
    let accountsLoaded: Bool
    let inventory: InventoryReview?
    let historyLoaded: Bool
    let onChangeIndustry: (IndustryTemplate.Kind) -> Void
    let onSaveCount: (Money, AccountingDate) -> Void
    let onLoadHistory: () -> Void
    @Environment(\.qboLinks) private var qboLinks
    @State private var countText = ""

    public init(environment: VLEnvironmentTone, kind: IndustryTemplate.Kind, comparison: IndustryTemplate.Comparison, accountsLoaded: Bool,
                inventory: InventoryReview?, historyLoaded: Bool, onChangeIndustry: @escaping (IndustryTemplate.Kind) -> Void,
                onSaveCount: @escaping (Money, AccountingDate) -> Void, onLoadHistory: @escaping () -> Void) {
        self.environment = environment
        self.kind = kind
        self.comparison = comparison
        self.accountsLoaded = accountsLoaded
        self.inventory = inventory
        self.historyLoaded = historyLoaded
        self.onChangeIndustry = onChangeIndustry
        self.onSaveCount = onSaveCount
        self.onLoadHistory = onLoadHistory
    }

    private var inventorySection: some View {
        VLCard(accentRail: (inventory?.ratioFlag ?? false) || (inventory?.negativeInventory ?? false) ? .orange : nil) {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                eyebrow("INVENTORY REVIEW")
                if !historyLoaded {
                    HStack {
                        Text("Needs the 24-month history for monthly cost of goods.").font(VLTypography.caption()).foregroundStyle(.orange)
                        Button("Load 24-month history", action: onLoadHistory).controlSize(.small)
                    }
                }
                if let inv = inventory {
                    if inv.noCostOfGoods {
                        Text("No cost of goods sold is recorded in these months. A business that sells products should show it; purchases may be booked as ordinary expenses.")
                            .font(VLTypography.body()).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(inv.months) { m in
                        HStack {
                            Text("\(m.period.year)-\(String(format: "%02d", m.period.month))").font(VLTypography.tabularNumeric()).frame(width: 90, alignment: .leading)
                            Text("Sales \(m.sales.accountingDescription)").frame(width: 170, alignment: .leading)
                            Text("Cost of goods \(m.costOfGoods.accountingDescription)").frame(width: 210, alignment: .leading)
                            Text(String(format: "%.1f%%", m.percent)).fontWeight(.semibold)
                        }
                        .font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                    }
                    if let shift = inv.ratioShift {
                        Text(String(format: "Latest month is %.1f points %@ the prior average (%.1f%%).", abs(shift), shift >= 0 ? "above" : "below", inv.priorAverage ?? 0)
                             + (inv.ratioFlag ? " That's a big move: check for missing sales, unrecorded purchases, price changes or shrinkage." : ""))
                            .font(VLTypography.caption()).foregroundStyle(inv.ratioFlag ? .orange : VLColor.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    Divider().overlay(VLColor.border)
                    if let balance = inv.inventoryBalance {
                        Text("Inventory on the books: \(balance.accountingDescription)").font(VLTypography.body()).foregroundStyle(inv.negativeInventory ? .red : VLColor.textPrimary)
                        if inv.negativeInventory { Text("A negative inventory balance means items were sold that were never recorded as bought.").font(VLTypography.caption()).foregroundStyle(.red) }
                    } else {
                        Text("No inventory asset account found in the chart of accounts.").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                    }
                    if let count = inv.count {
                        Text("Client's count\(inv.countDate.map { " on " + ClientText.polish($0.formatted) } ?? ""): \(count.accountingDescription)").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                    }
                    if let diff = inv.countDifference {
                        Text(diff.minorUnits == 0 ? "The books match the count." : "Books minus count: \(diff.accountingDescription). Adjust the books to the count with an inventory adjustment once the client confirms the count.")
                            .font(VLTypography.caption()).foregroundStyle(diff.minorUnits == 0 ? VLColor.textMuted : .orange).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        TextField("Client's physical count ($)", text: $countText).textFieldStyle(.roundedBorder).frame(width: 200)
                        Button("Save count as of today") {
                            guard let m = AmountSearch.parseAmount(countText) else { return }
                            onSaveCount(Money(minorUnits: abs(m.minorUnits), currency: .usd), AccountingDate(date: Date()))
                            countText = ""
                        }
                    }
                }
            }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                pageHeader("Industry Setup", environment, "Compares this client's chart of accounts with what a well-kept chart for their industry has. It only reports; add or rename accounts in QuickBooks yourself. Ask Moneypenny how to book anything specific to the industry.")
                Picker("Industry", selection: Binding(get: { kind }, set: { onChangeIndustry($0) })) {
                    ForEach(IndustryTemplate.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }.frame(maxWidth: 420)
                Text(kind.complexity.pricingNote).font(VLTypography.caption())
                    .foregroundStyle(kind.complexity == .high ? .red : kind.complexity == .elevated ? .orange : VLColor.textMuted)
                if !accountsLoaded {
                    Text("Sync first; the chart of accounts isn't loaded.").font(VLTypography.caption()).foregroundStyle(.orange)
                }
                VLCard(accentRail: comparison.missing.isEmpty ? nil : .orange) {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("MISSING (\(comparison.missing.count))")
                        if comparison.missing.isEmpty { Text("Every recommended account is present.").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary) }
                        ForEach(comparison.missing) { rec in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(rec.name) · \(rec.type.rawValue)").font(VLTypography.body()).foregroundStyle(VLColor.textPrimary)
                                Text(rec.why).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                            }
                        }
                    }
                }
                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("PRESENT (\(comparison.present.count))")
                        ForEach(comparison.present, id: \.0.id) { pair in
                            HStack {
                                Text(pair.0.name).font(VLTypography.body()).foregroundStyle(VLColor.textSecondary)
                                Text("→ \(pair.1.name)").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                                Spacer()
                                QBOLinkButton(qboLinks.account(id: pair.1.id), compact: true)
                            }
                        }
                    }
                }
                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("HOW TO TRACK PROFITABILITY")
                        ForEach(IndustryTemplate.tracking(for: kind), id: \.self) { tip in
                            Text("• \(tip)").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("RED FLAGS IN THIS INDUSTRY")
                        ForEach(IndustryTemplate.redFlags(for: kind), id: \.self) { flag in
                            Text("• \(flag)").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if kind.usesInventory || inventory?.inventoryBalance != nil {
                    inventorySection
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}

// MARK: - Scope requests page

public struct ScopeRequestsView: View {
    let environment: VLEnvironmentTone
    let clientName: String?
    let presets: [ScopePreset]
    let requests: [ScopeRequest]
    let onAdd: (ScopeRequest) -> Void
    let onUpdate: (ScopeRequest) -> Void
    let onRemove: (String) -> Void
    let onSavePresets: ([ScopePreset]) -> Void
    let onResetPresets: () -> Void
    @State private var quantity = 1
    @State private var editingPrices = false
    @State private var priceDrafts: [String: String] = [:]
    @State private var customTitle = ""
    @State private var customPrice = ""
    @State private var customBilling: ScopeBilling = .oneTime
    @State private var copiedID: String?

    public init(environment: VLEnvironmentTone, clientName: String?, presets: [ScopePreset], requests: [ScopeRequest],
                onAdd: @escaping (ScopeRequest) -> Void, onUpdate: @escaping (ScopeRequest) -> Void, onRemove: @escaping (String) -> Void,
                onSavePresets: @escaping ([ScopePreset]) -> Void, onResetPresets: @escaping () -> Void) {
        self.environment = environment
        self.clientName = clientName
        self.presets = presets
        self.requests = requests
        self.onAdd = onAdd
        self.onUpdate = onUpdate
        self.onRemove = onRemove
        self.onSavePresets = onSavePresets
        self.onResetPresets = onResetPresets
    }

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: VLSpacing.sm)]

    public var body: some View {
        let totals = ScopeLog.totals(requests)
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                pageHeader("Scope Requests", environment, "When \(clientName ?? "a client") asks for something outside the engagement agreement, click its price to log it as quoted, copy the reply, and mark it approved once they say yes in writing. Prices are yours to set.")

                HStack(spacing: VLSpacing.lg) {
                    VStack(alignment: .leading) { eyebrow("APPROVED MONTHLY ADD-ONS"); Text(totals.monthlyAddOns.accountingDescription + "/mo").font(VLTypography.metricLarge()) }
                    VStack(alignment: .leading) { eyebrow("APPROVED, NOT YET BILLED"); Text(totals.unbilledOneTime.accountingDescription).font(VLTypography.metricLarge()) }
                    VStack(alignment: .leading) { eyebrow("WAITING ON CLIENT"); Text("\(totals.awaitingApproval)").font(VLTypography.metricLarge()) }
                }.foregroundStyle(VLColor.textPrimary)

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        HStack {
                            eyebrow("ADD A REQUEST — CLICK A PRICE")
                            Spacer()
                            Stepper("Quantity \(quantity)", value: $quantity, in: 1...99).frame(width: 160)
                            Button(editingPrices ? "Done editing prices" : "Edit prices") {
                                if editingPrices {
                                    let updated = presets.map { preset -> ScopePreset in
                                        var p = preset
                                        if let text = priceDrafts[preset.id], let m = AmountSearch.parseAmount(text) { p.price = Money(minorUnits: abs(m.minorUnits), currency: .usd) }
                                        return p
                                    }
                                    onSavePresets(updated)
                                } else {
                                    priceDrafts = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, String(format: "%.2f", $0.price.majorUnitsDouble)) })
                                }
                                editingPrices.toggle()
                            }
                            if editingPrices { Button("Reset to defaults") { onResetPresets(); editingPrices = false } }
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: VLSpacing.sm) {
                            ForEach(presets) { preset in
                                if editingPrices {
                                    HStack {
                                        Text(preset.title).font(VLTypography.caption()).foregroundStyle(VLColor.textSecondary)
                                        Spacer()
                                        TextField("Price", text: Binding(get: { priceDrafts[preset.id] ?? "" }, set: { priceDrafts[preset.id] = $0 }))
                                            .textFieldStyle(.roundedBorder).frame(width: 90)
                                    }
                                } else {
                                    Button {
                                        onAdd(ScopeRequest(preset: preset, quantity: preset.billing == .perUnit ? quantity : 1))
                                        quantity = 1
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.title).font(VLTypography.body()).multilineTextAlignment(.leading)
                                            Text("+ \(preset.priceLabel)").font(VLTypography.caption()).foregroundStyle(VLColor.cyan)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(VLSpacing.sm)
                                    }
                                    .buttonStyle(.bordered)
                                    .help(preset.taxNote ?? "Log this as a quoted request")
                                }
                            }
                        }
                        Divider().overlay(VLColor.border)
                        HStack {
                            TextField("Something else (describe it)", text: $customTitle).textFieldStyle(.roundedBorder)
                            TextField("Price", text: $customPrice).textFieldStyle(.roundedBorder).frame(width: 90)
                            Picker("", selection: $customBilling) {
                                Text("One time").tag(ScopeBilling.oneTime); Text("Monthly").tag(ScopeBilling.monthly)
                            }.frame(width: 120)
                            Button("Add") {
                                guard let m = AmountSearch.parseAmount(customPrice), !customTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                                onAdd(ScopeRequest(title: customTitle, unitPrice: Money(minorUnits: abs(m.minorUnits), currency: .usd), billing: customBilling))
                                customTitle = ""; customPrice = ""
                            }
                        }
                    }
                }

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.sm) {
                        eyebrow("REQUESTS (\(requests.count))")
                        if requests.isEmpty {
                            Text("No out-of-scope requests logged for this client.").font(VLTypography.body()).foregroundStyle(VLColor.textMuted)
                        }
                        ForEach(requests) { request in
                            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(request.title).font(VLTypography.body()).foregroundStyle(VLColor.textPrimary)
                                        Text("\(request.priceText) · logged \(request.requestedAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                                    }
                                    Spacer()
                                    Picker("", selection: Binding(get: { request.status }, set: { var r = request; r.status = $0; onUpdate(r) })) {
                                        ForEach(ScopeRequest.Status.allCases, id: \.self) { Text($0.label).tag($0) }
                                    }.frame(width: 120)
                                    Button(copiedID == request.id ? "Copied" : "Copy reply") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(ScopeLog.clientReply(for: request, clientName: nil), forType: .string)
                                        copiedID = request.id
                                    }.controlSize(.small)
                                    Button { onRemove(request.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                                }
                                if let note = presets.first(where: { $0.title == request.title })?.taxNote {
                                    Text(note).font(VLTypography.caption()).foregroundStyle(.orange)
                                }
                            }
                            Divider().overlay(VLColor.border)
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
