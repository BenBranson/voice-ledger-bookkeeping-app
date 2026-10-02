import Testing
import Foundation
@testable import Voice

/// docs/VOICE_COMMANDS.md is the owner's printable list. This keeps it honest:
/// every quoted phrase in it must be understood by the app (never fall through
/// to the slow model), and every sidebar page must be listed.
@Suite("Printable voice-command list stays true")
struct VoiceCommandsDocTests {
    var doc: String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("docs/VOICE_COMMANDS.md"), encoding: .utf8)) ?? ""
    }

    @Test("Every bold quoted phrase in the list is recognized by the grammar")
    func everyListedPhraseWorks() throws {
        #expect(!doc.isEmpty, "docs/VOICE_COMMANDS.md not found")
        let re = try NSRegularExpression(pattern: #"\*\*"([^"]+)"\*\*|(?<=\*\*)"([^"]+)"(?=\*\*)|·\s\*\*"([^"]+)"\*\*"#)
        // Phrases in bold quotes inside table cells: **"a"** · **"b"** — collect every "..." inside **...**.
        let quoted = try NSRegularExpression(pattern: #""([^"\n]{2,60})""#)
        var phrases = Set<String>()
        for line in doc.split(separator: "\n") where line.contains("**\"") {
            let s = String(line)
            for m in quoted.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                if let r = Range(m.range(at: 1), in: s) { phrases.insert(String(s[r])) }
            }
        }
        _ = re
        // Phrases that need session state or are answers to a question — documented, not routable cold.
        let stateful: Set<String> = ["next", "skip", "what's left", "how many are left", "yes", "no", "that one", "open it"]
        #expect(phrases.count > 40)
        for p in phrases.sorted() where !stateful.contains(p.lowercased()) {
            let intent = VoiceIntentRouter.match(text: p, context: .empty)
            if case .unrecognized = intent { Issue.record("Listed but not understood: \"\(p)\"") }
        }
    }

    @Test("Every sidebar page is listed by name")
    func everyMenuTitleListed() {
        for d in VoiceDestination.allCases { #expect(doc.contains("| \(d.menuTitle.replacingOccurrences(of: "&", with: "&")) |"), "Missing from list: \(d.menuTitle)") }
    }
}
