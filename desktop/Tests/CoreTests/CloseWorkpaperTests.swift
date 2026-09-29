import Testing
@testable import Core
import Foundation

@Suite("Month-end close sequence and workpaper")
struct CloseWorkpaperTests {
    let period = AccountingPeriod(year: 2026, month: 7)
    func id(_ raw: String) -> ChecklistItemID { ChecklistItemID(rawValue: raw) }

    @Test("Bank rec → clearing zeroed → balance sheet tie-out → P&L variance review, each gated on the one before")
    func sequence() {
        let items = Dictionary(uniqueKeysWithValues: MonthEndChecklist.defaultItems.map { ($0.id.rawValue, $0) })
        #expect(items["clearing-accounts-zeroed"]?.prerequisiteIDs == [id("reconcile-bank-accounts")])
        #expect(items["balance-sheet-tie-out"]?.prerequisiteIDs == [id("clearing-accounts-zeroed")])
        #expect(items["pnl-variance-review"]?.prerequisiteIDs == [id("balance-sheet-tie-out")])
        #expect(items["set-qbo-closing-date"]?.prerequisiteIDs.contains(id("pnl-variance-review")) == true)
    }

    @Test("Workpaper lists every step with who signed off and when; open steps stay blank")
    func workpaper() {
        let completion = ChecklistItemCompletion(itemID: id("reconcile-bank-accounts"), period: period, completedAt: Date(timeIntervalSince1970: 1_790_000_000), completedBy: "Benjamin", note: "All 3 accounts")
        let other = ChecklistItemCompletion(itemID: id("review-bank-feed"), period: AccountingPeriod(year: 2026, month: 6), completedBy: "Someone")
        let table = MonthEndChecklist.workpaper(completions: [completion, other], period: period, currentWatermark: nil, companyName: "Acme")
        #expect(table.rows.count == MonthEndChecklist.defaultItems.count)
        let rec = table.rows.first { $0[1].text == "Bank reconciliation verified" }
        #expect(rec?[2].text == "Signed off")
        #expect(rec?[3].text == "Benjamin")
        #expect(rec?[5].text == "All 3 accounts")
        let feed = table.rows.first { $0[1].text == "Review Bank Feed Cleanup findings" }
        #expect(feed?[2].text == "Open")
        #expect(table.title.contains("Acme") && table.title.contains("2026-07"))
    }
}
