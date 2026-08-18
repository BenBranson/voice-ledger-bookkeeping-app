import Testing
@testable import Core

@Suite("MonthEndChecklist")
struct MonthEndChecklistTests {
    @Test("An item with no prerequisites is always unlocked")
    func itemWithNoPrerequisitesIsUnlocked() {
        let item = ChecklistItem(id: ChecklistItemID(rawValue: "a"), title: "A", description: "")
        #expect(MonthEndChecklist.isUnlocked(item, completedItemIDs: []))
    }

    @Test("An item with unmet prerequisites is locked")
    func itemWithUnmetPrerequisiteIsLocked() {
        let item = ChecklistItem(id: ChecklistItemID(rawValue: "b"), title: "B", description: "", prerequisiteIDs: [ChecklistItemID(rawValue: "a")])
        #expect(!MonthEndChecklist.isUnlocked(item, completedItemIDs: []))
    }

    @Test("An item unlocks once all its prerequisites are met")
    func itemUnlocksOnceAllPrerequisitesMet() {
        let item = ChecklistItem(id: ChecklistItemID(rawValue: "c"), title: "C", description: "", prerequisiteIDs: [ChecklistItemID(rawValue: "a"), ChecklistItemID(rawValue: "b")])
        #expect(!MonthEndChecklist.isUnlocked(item, completedItemIDs: [ChecklistItemID(rawValue: "a")]))
        #expect(MonthEndChecklist.isUnlocked(item, completedItemIDs: [ChecklistItemID(rawValue: "a"), ChecklistItemID(rawValue: "b")]))
    }

    @Test("The default checklist's final item requires all three of its named prerequisites, not just one")
    func finalItemRequiresAllPrerequisites() {
        let closingItem = MonthEndChecklist.defaultItems.first { $0.id.rawValue == "set-qbo-closing-date" }!
        #expect(closingItem.prerequisiteIDs.count == 3)
        let onlyOne: Set<ChecklistItemID> = [ChecklistItemID(rawValue: "resolve-cleanup-assessment")]
        #expect(!MonthEndChecklist.isUnlocked(closingItem, completedItemIDs: onlyOne))
        let allThree = Set(closingItem.prerequisiteIDs)
        #expect(MonthEndChecklist.isUnlocked(closingItem, completedItemIDs: allThree))
    }

    @Test("The default checklist has no duplicate item IDs")
    func defaultChecklistHasNoDuplicateIDs() {
        let ids = MonthEndChecklist.defaultItems.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every prerequisite referenced by a default item is itself a real item in the list")
    func everyPrerequisiteIsARealItem() {
        let allIDs = Set(MonthEndChecklist.defaultItems.map(\.id))
        for item in MonthEndChecklist.defaultItems {
            for prereq in item.prerequisiteIDs {
                #expect(allIDs.contains(prereq), "\(item.id.rawValue) references unknown prerequisite \(prereq.rawValue)")
            }
        }
    }

    @Test("completionStatus counts only completions matching the given period")
    func completionStatusCountsOnlyMatchingPeriod() {
        let period = AccountingPeriod(year: 2026, month: 7)
        let otherPeriod = AccountingPeriod(year: 2026, month: 6)
        let completions = [
            ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "resolve-cleanup-assessment"), period: period, completedBy: "A"),
            ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "review-balance-sheet-integrity"), period: period, completedBy: "A"),
            // A completion for a different period must not count toward this period's total.
            ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "review-bank-feed"), period: otherPeriod, completedBy: "A")
        ]
        let status = MonthEndChecklist.completionStatus(completions: completions, period: period)
        #expect(status.completed == 2)
        #expect(status.total == MonthEndChecklist.defaultItems.count)
    }

    @Test("completionStatus is zero-of-total for a period with no completions at all")
    func completionStatusZeroForNoCompletions() {
        let status = MonthEndChecklist.completionStatus(completions: [], period: AccountingPeriod(year: 2026, month: 7))
        #expect(status.completed == 0)
        #expect(status.total == MonthEndChecklist.defaultItems.count)
    }
}
