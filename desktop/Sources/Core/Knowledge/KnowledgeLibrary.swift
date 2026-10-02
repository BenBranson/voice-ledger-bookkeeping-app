import Foundation

/// Her bookkeeping reference shelf: notes on QuickBooks Online procedures, ProAdvisor
/// training, tax forms and Branson's own Voice Ledger workflow, one Markdown file each
/// under `desktop/Knowledge/` (copied from the Talking Buddy project, 2026-10-02). They are written from Intuit's help pages and training
/// rather than copied, and each names its source.
///
/// A local model answering "how do I record a vendor refund" from its own weights
/// invents menu paths. So each question is matched against the notes, and the few
/// sections that fit ride along on the final user message -- like chat retrieval and
/// long-term memory, never in the system prompt, which would break Ollama's cached
/// prefix. A question that matches nothing strongly gets nothing, so an ordinary
/// question is never steered towards bookkeeping.
public final class KnowledgeLibrary: @unchecked Sendable {
    public struct Section: Equatable, Sendable {
        public var note: String
        public var heading: String
        public var source: String
        public var text: String
    }

    private struct Indexed {
        var section: Section
        var counts: [String: Int]
        var titleTerms: Set<String>
        var length: Int
    }

    private let indexed: [Indexed]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    public var sectionCount: Int { indexed.count }

    /// `notes` are (file name, contents). Files whose names begin with `_` or `INDEX`
    /// are working files, not notes.
    public init(notes: [(name: String, text: String)]) {
        var sections: [Section] = []
        for note in notes where !note.name.hasPrefix("_") && !note.name.hasPrefix("INDEX") {
            sections += Self.sections(of: note.text, fallbackTitle: note.name)
        }
        indexed = sections.map { section in
            let terms = Self.terms(section.heading + " " + section.text)
            return Indexed(
                section: section,
                counts: terms.reduce(into: [:]) { $0[$1, default: 0] += 1 },
                titleTerms: Set(Self.terms(section.note + " " + section.heading)),
                length: max(terms.count, 1)
            )
        }
        documentFrequency = indexed.reduce(into: [:]) { frequency, entry in
            for term in Set(entry.counts.keys).union(entry.titleTerms) { frequency[term, default: 0] += 1 }
        }
        averageLength = indexed.isEmpty ? 1 : Double(indexed.map(\.length).reduce(0, +)) / Double(indexed.count)
    }

    /// Every `.md` note under `directory`.
    public static func load(from directory: URL) -> KnowledgeLibrary {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "md" } ?? []
        return KnowledgeLibrary(notes: files.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (url.deletingPathExtension().lastPathComponent, $0) }
        })
    }

    /// The best-matching sections, best first, within `budget` characters. Scored with
    /// BM25 so a word every note shares ("QuickBooks", "select") counts for little and a
    /// distinctive one ("undeposited", "1099") for a lot; a match in the note's title or
    /// heading counts double, because titles say what a note is for.
    ///
    /// At most one section per note, so three different notes answer rather than one note
    /// three times. A section must match at least two different words of the question:
    /// one shared word ("remind" against invoice reminders) is coincidence, not a topic.
    public func search(_ query: String, limit: Int = 3, budget: Int = 3000, minimumScore: Double = 7) -> [Section] {
        var chosen: [Section] = []
        var used = 0
        for (_, index) in ranked(query, minimumScore: minimumScore) {
            guard chosen.count < limit else { break }
            var section = indexed[index].section
            guard !chosen.contains(where: { $0.note == section.note }) else { continue }
            let room = budget - used
            guard room > 300 else { break }
            if section.text.count > room { section.text = String(section.text.prefix(room)) + "…" }
            used += section.text.count
            chosen.append(section)
        }
        return chosen
    }

    /// Every candidate's score, best first -- for tuning the threshold.
    func scores(_ query: String) -> [(note: String, heading: String, score: Double)] {
        ranked(query, minimumScore: 0).map { (indexed[$0.index].section.note, indexed[$0.index].section.heading, $0.score) }
    }

    private func ranked(_ query: String, minimumScore: Double) -> [(score: Double, index: Int)] {
        let queryTerms = Set(Self.terms(query))
        guard !queryTerms.isEmpty, !indexed.isEmpty else { return [] }
        let total = Double(indexed.count)
        var scored: [(score: Double, index: Int)] = []
        for (index, entry) in indexed.enumerated() {
            var score = 0.0
            var matched = 0
            for term in queryTerms {
                let inTitle = entry.titleTerms.contains(term)
                let frequency = Double(entry.counts[term] ?? 0)
                guard frequency > 0 || inTitle else { continue }
                matched += 1
                let documents = Double(documentFrequency[term] ?? 0)
                let idf = log(1 + (total - documents + 0.5) / (documents + 0.5))
                let norm = frequency * 2.2 / (frequency + 1.2 * (0.25 + 0.75 * Double(entry.length) / averageLength))
                score += idf * norm + (inTitle ? idf : 0)
            }
            if matched >= 2, score >= minimumScore { scored.append((score, index)) }
        }
        return scored.sorted { $0.score > $1.score }
    }

    /// The chosen sections as reference text for a model's context. Ported
    /// from Talking Buddy (2026-10-02) with its framing: steps and menu names
    /// come from these notes, never invented.
    public static func referenceBlock(_ sections: [Section]) -> String? {
        guard !sections.isEmpty else { return nil }
        let notes = sections.map { "[\($0.note) -- \($0.heading)]\n\($0.text)" }.joined(separator: "\n\n")
        return """
        Reference notes from the bookkeeping library, written from Intuit's QuickBooks Online \
        help articles, ProAdvisor training and Voice Ledger's own workflow. Use them for exact \
        steps and menu names, and say the steps plainly. QuickBooks changes its screens, so if \
        the bookkeeper says a menu isn't where the notes put it, believe him. If the notes don't \
        cover what was asked, say so rather than inventing a menu path. Dollar figures for THIS \
        client still come only from the client data, never from these notes:

        \(notes)
        """
    }

    /// A note becomes one section if it is short, otherwise one per `##` heading,
    /// each labelled with the note's title so it still makes sense alone.
    static func sections(of text: String, fallbackTitle: String, wholeNoteLimit: Int = 2400) -> [Section] {
        var title = fallbackTitle
        var source = ""
        var body = text
        if text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) {
            for line in text[text.startIndex..<end.lowerBound].split(separator: "\n") {
                if line.hasPrefix("title:") { title = line.dropFirst(6).trimmingCharacters(in: .whitespaces) }
                if line.hasPrefix("source:") { source = line.dropFirst(7).trimmingCharacters(in: .whitespaces) }
            }
            body = String(text[end.upperBound...])
        }
        var parts: [(heading: String, lines: [Substring])] = [("Overview", [])]
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                parts.append((String(line.dropFirst(3)), []))
            } else if !line.hasPrefix("# ") {
                parts[parts.count - 1].lines.append(line)
            }
        }
        let cleaned = parts.map { part in
            (part.heading, part.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { !$0.1.isEmpty }
        let whole = cleaned.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        if whole.count <= wholeNoteLimit {
            return whole.isEmpty ? [] : [Section(note: title, heading: "whole note", source: source, text: whole)]
        }
        return cleaned.map { Section(note: title, heading: $0.0, source: source, text: $0.1) }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "you", "your", "how", "what", "when", "can", "does", "that",
        "this", "from", "into", "are", "was", "has", "have", "not", "but", "its", "any", "all",
        "use", "using", "used", "about", "there", "their", "they", "them", "then", "than", "who",
        "why", "which", "should", "would", "could", "will", "just", "also", "out", "one", "get",
        "branson", "moneypenny", "penny", "please", "tell", "know", "want", "need", "like",
        "select", "choose", "click", "quickbooks", "qbo", "online", "intuit"
    ]

    /// Lowercased words of three or more letters, crudely stemmed, without stop words.
    static func terms(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !stopWords.contains(String($0)) }
            .map { word -> String in
                var word = String(word)
                if word.count > 4, word.hasSuffix("ies") { word = String(word.dropLast(3)) + "y" }
                else if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { word = String(word.dropLast()) }
                // "invoice" and "invoices", "match" and "matches" meet at the same stem.
                if word.count > 4, word.hasSuffix("e") { word = String(word.dropLast()) }
                return word
            }
            .filter { $0.count >= 3 }
    }
}
