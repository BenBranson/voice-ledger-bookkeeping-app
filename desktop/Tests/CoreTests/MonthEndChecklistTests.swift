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

    @Test("The default checklist's final item requires all four of its named prerequisites, not just one")
    func finalItemRequiresAllPrerequisites() {
        let closingItem = MonthEndChecklist.defaultItems.first { $0.id.rawValue == "set-qbo-closing-date" }!
        #expect(closingItem.prerequisiteIDs.count == 4)
        let onlyOne: Set<ChecklistItemID> = [ChecklistItemID(rawValue: "resolve-cleanup-assessment")]
        #expect(!MonthEndChecklist.isUnlocked(closingItem, completedItemIDs: onlyOne))
        let allThree = Set(closingItem.prerequisiteIDs)
        #expect(MonthEndChecklist.isUnlocked(closingItem, completedItemIDs: allThree))
    }

    @Test("isStale is false when the completion's watermark matches the current one")
    func isStaleFalseWhenWatermarksMatch() {
        let watermark = EvidenceWatermark(ruleVersionsSignature: "VL-DUP-EXP-001:1.0.0", materialityFloorMinorUnits: 2_500)
        let completion = ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "a"), period: AccountingPeriod(year: 2026, month: 7), completedBy: "A", watermark: watermark)
        #expect(!MonthEndChecklist.isStale(completion, currentWatermark: watermark))
    }

    @Test("isStale is true when a rule version has changed since completion")
    func isStaleTrueWhenRuleVersionChanged() {
        let oldWatermark = EvidenceWatermark(ruleVersionsSignature: "VL-DUP-EXP-001:1.0.0", materialityFloorMinorUnits: 2_500)
        let newWatermark = EvidenceWatermark(ruleVersionsSignature: "VL-DUP-EXP-001:1.1.0", materialityFloorMinorUnits: 2_500)
        let completion = ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "a"), period: AccountingPeriod(year: 2026, month: 7), completedBy: "A", watermark: oldWatermark)
        #expect(MonthEndChecklist.isStale(completion, currentWatermark: newWatermark))
    }

    @Test("isStale is true when the materiality floor has changed since completion")
    func isStaleTrueWhenMaterialityChanged() {
        let oldWatermark = EvidenceWatermark(ruleVersionsSignature: "VL-DUP-EXP-001:1.0.0", materialityFloorMinorUnits: 2_500)
        let newWatermark = EvidenceWatermark(ruleVersionsSignature: "VL-DUP-EXP-001:1.0.0", materialityFloorMinorUnits: 5_000)
        let completion = ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "a"), period: AccountingPeriod(year: 2026, month: 7), completedBy: "A", watermark: oldWatermark)
        #expect(MonthEndChecklist.isStale(completion, currentWatermark: newWatermark))
    }

    @Test("isStale is true for a completion recorded before watermarks existed — unknown is never treated as fresh")
    func isStaleTrueForNilWatermark() {
        let currentWatermark = EvidenceWatermark(ruleVersionsSignature: "VL-DUP-EXP-001:1.0.0", materialityFloorMinorUnits: 2_500)
        let completion = ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "a"), period: AccountingPeriod(year: 2026, month: 7), completedBy: "A", watermark: nil)
        #expect(MonthEndChecklist.isStale(completion, currentWatermark: currentWatermark))
    }

    @Test("EvidenceWatermark.current is order-independent — rule identity order never changes the signature")
    func evidenceWatermarkCurrentIsOrderIndependent() {
        let a = RuleIdentity(id: RuleID(rawValue: "VL-A"), version: RuleVersion(major: 1, minor: 0, patch: 0), title: "A", category: .duplicateExpense, ruleClass: .categorization, page: .cleanupAssessment, accountingPrinciple: "", sourceDependencies: [])
        let b = RuleIdentity(id: RuleID(rawValue: "VL-B"), version: RuleVersion(major: 2, minor: 1, patch: 0), title: "B", category: .duplicateExpense, ruleClass: .categorization, page: .cleanupAssessment, accountingPrinciple: "", sourceDependencies: [])
        let watermark1 = EvidenceWatermark.current(ruleIdentities: [a, b], materiality: .defaultPolicy)
        let watermark2 = EvidenceWatermark.current(ruleIdentities: [b, a], materiality: .defaultPolicy)
        #expect(watermark1 == watermark2)
    }

    @Test("EvidenceWatermark.current changes when a rule's version changes")
    func evidenceWatermarkCurrentChangesWithRuleVersion() {
        let v1 = RuleIdentity(id: RuleID(rawValue: "VL-A"), version: RuleVersion(major: 1, minor: 0, patch: 0), title: "A", category: .duplicateExpense, ruleClass: .categorization, page: .cleanupAssessment, accountingPrinciple: "", sourceDependencies: [])
        let v2 = RuleIdentity(id: RuleID(rawValue: "VL-A"), version: RuleVersion(major: 1, minor: 1, patch: 0), title: "A", category: .duplicateExpense, ruleClass: .categorization, page: .cleanupAssessment, accountingPrinciple: "", sourceDependencies: [])
        let watermark1 = EvidenceWatermark.current(ruleIdentities: [v1], materiality: .defaultPolicy)
        let watermark2 = EvidenceWatermark.current(ruleIdentities: [v2], materiality: .defaultPolicy)
        #expect(watermark1 != watermark2)
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
