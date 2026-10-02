import Testing
import Foundation
@testable import Voice
import Core

@Suite("Month-end guided walkthrough")
struct MonthEndRoutineTests {
    func route(_ s: String, step: Int? = nil) -> VoiceIntent {
        var ctx = VoiceSessionContext.empty
        ctx.routineStep = step
        return VoiceIntentRouter.match(text: s, context: ctx)
    }

    @Test("Starting phrases work cold, with filler")
    func start() {
        for p in ["start month end", "Start the month end review", "hey moneypenny start month end", "walk me through the month", "start the monthly routine", "please start the routine"] {
            #expect(route(p) == .startRoutine, "\(p)")
        }
    }

    @Test("Control words only mean something while the walkthrough is running")
    func controls() {
        #expect(route("next", step: 2) == .routineAdvance)
        #expect(route("done", step: 2) == .routineAdvance)
        #expect(route("I did that", step: 2) == .routineAdvance)
        #expect(route("repeat", step: 3) == .routineRepeat)
        #expect(route("previous step", step: 3) == .routinePrevious)
        #expect(route("stop", step: 3) == .routineStop)
        #expect(route("where are we", step: 3) == .routineWhere)
        #expect(route("done", step: nil) != .routineAdvance)
        #expect(route("stop", step: nil) != .routineStop)
    }

    @Test("The step list matches the printed routine: manual steps carry instructions, the rest are runnable")
    func steps() {
        #expect(MonthEndRoutine.count == 16)
        for step in MonthEndRoutine.steps { #expect((step.manual == nil) != (step.intent == nil), "\(step.title): exactly one of manual/intent") }
        #expect(MonthEndRoutine.steps.filter { $0.manual != nil }.count == 2)
        #expect(MonthEndRoutine.heading(2) == "Step 3 of 16: Add or match missing bank lines.")
        #expect(MonthEndRoutine.steps.first?.intent == .freshness)
        #expect(MonthEndRoutine.steps.last?.intent == .navigate(.closePackage))
    }

    @Test("A saved session from before the walkthrough existed still loads")
    func oldSessionsDecode() throws {
        let old = #"{"reviewQueue":[],"lastViewedEntities":[],"conversationGoal":"general"}"#
        let decoded = try JSONDecoder().decode(VoiceSessionContext.self, from: Data(old.utf8))
        #expect(decoded.routineStep == nil)
    }
}
