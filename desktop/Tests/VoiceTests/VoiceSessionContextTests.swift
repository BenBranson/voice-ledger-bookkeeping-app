import Testing
@testable import Voice
import Foundation

@Suite("VoiceSessionContext")
struct VoiceSessionContextTests {
    @Test("viewingEntity sets currentEntity and prepends to lastViewedEntities")
    func viewingEntitySetsCurrentAndPrepends() {
        let ctx = VoiceSessionContext.empty.viewingEntity(VoiceEntityRef(type: .finding, id: "f1", label: "Duplicate expense"))
        #expect(ctx.currentEntity?.id == "f1")
        #expect(ctx.lastViewedEntities.first?.id == "f1")
    }

    @Test("Re-viewing the same entity moves it to the front without duplicating")
    func reViewingSameEntityMovesToFrontWithoutDuplicate() {
        var ctx = VoiceSessionContext.empty
        ctx = ctx.viewingEntity(VoiceEntityRef(type: .finding, id: "f1"))
        ctx = ctx.viewingEntity(VoiceEntityRef(type: .finding, id: "f2"))
        ctx = ctx.viewingEntity(VoiceEntityRef(type: .finding, id: "f1"))
        #expect(ctx.lastViewedEntities.map(\.id) == ["f1", "f2"])
    }

    @Test("lastViewedEntities is capped at 10")
    func lastViewedEntitiesCappedAtTen() {
        var ctx = VoiceSessionContext.empty
        for i in 0..<15 {
            ctx = ctx.viewingEntity(VoiceEntityRef(type: .finding, id: "f\(i)"))
        }
        #expect(ctx.lastViewedEntities.count == 10)
        #expect(ctx.lastViewedEntities.first?.id == "f14")
    }

    @Test("clearingPendingAction removes a set pending action")
    func clearingPendingActionRemovesIt() {
        var ctx = VoiceSessionContext.empty
        ctx.pendingAction = VoicePendingAction(kind: .dismissFinding, findingID: "f1", summary: "dismiss this finding")
        let cleared = ctx.clearingPendingAction()
        #expect(cleared.pendingAction == nil)
    }

    @Test("stage is idle when nothing is set")
    func stageIsIdleByDefault() {
        #expect(VoiceSessionContext.empty.stage == .idle)
    }

    @Test("stage is reviewingSummary once a review queue exists but nothing is opened yet")
    func stageIsReviewingSummaryWithQueueOnly() {
        var ctx = VoiceSessionContext.empty
        ctx.reviewQueue = ["f1", "f2"]
        #expect(ctx.stage == .reviewingSummary)
    }

    @Test("stage is activeFinding once currentEntity is set")
    func stageIsActiveFindingWithCurrentEntity() {
        let ctx = VoiceSessionContext.empty.viewingEntity(VoiceEntityRef(type: .finding, id: "f1"))
        #expect(ctx.stage == .activeFinding)
    }

    @Test("stage is awaitingConfirmation when a pending action is set, even with a current entity — the more specific state takes priority")
    func stageIsAwaitingConfirmationEvenWithCurrentEntity() {
        var ctx = VoiceSessionContext.empty.viewingEntity(VoiceEntityRef(type: .finding, id: "f1"))
        ctx.pendingAction = VoicePendingAction(kind: .dismissFinding, findingID: "f1", summary: "dismiss this finding")
        #expect(ctx.stage == .awaitingConfirmation)
    }

    @Test("VoiceSessionContext round-trips through Codable")
    func roundTripsThroughCodable() throws {
        var ctx = VoiceSessionContext.empty
        ctx.reviewQueue = ["f1", "f2"]
        ctx.reviewQueueIndex = 1
        ctx.pendingAction = VoicePendingAction(kind: .completeChecklistItem, checklistItemID: "x", summary: "mark complete")
        ctx.conversationGoal = .cleanup
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(VoiceSessionContext.self, from: data)
        #expect(decoded == ctx)
    }
}
