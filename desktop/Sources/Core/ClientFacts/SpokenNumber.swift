import Foundation

/// Turns what a speech recognizer heard into a dollar amount:
/// "$1,420", "1420.00", "fourteen twenty", "one four two zero",
/// "twelve hundred dollars", "three thousand two hundred ninety three
/// dollars and two cents". Returns nil when no amount is present.
public enum SpokenNumber {
    static let units: [String: Int] = ["zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
                                       "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
                                       "seventeen": 17, "eighteen": 18, "nineteen": 19]
    static let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
    static let scales: [String: Int] = ["hundred": 100, "thousand": 1_000, "million": 1_000_000]

    public static func amount(in text: String, currency: CurrencyCode = .usd) -> Money? {
        let lowered = text.lowercased().replacingOccurrences(of: ",", with: "")
        // 1. Digits: $1420.00 / 1420 / 1,420.50 / 1420 dollars
        if let match = lowered.range(of: #"\$?\s*(\d+(?:\.\d{1,2})?)"#, options: .regularExpression) {
            let raw = lowered[match].replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
            if let value = Decimal(string: raw), value > 0 || lowered.contains("$") {
                // A bare small integer with no money cue ("open the 3 findings") isn't an amount.
                let hasCue = lowered.contains("$") || lowered.contains("dollar") || raw.contains(".") || (Decimal(string: raw) ?? 0) >= 20
                if hasCue { return Money(minorUnits: Int64((NSDecimalNumber(decimal: value).doubleValue * 100).rounded()), currency: currency) }
            }
        }
        // 2. Number words: take the first contiguous run of number-ish words.
        let words = lowered.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
        var run: [String] = []
        var started = false
        for word in words {
            let isNumberWord = units[word] != nil || tens[word] != nil || scales[word] != nil
            let isJoiner = ["and", "point", "dollars", "dollar", "bucks", "cents", "cent"].contains(word)
            if isNumberWord { run.append(word); started = true }
            else if started && isJoiner { run.append(word) }
            else if started { break }
        }
        guard !run.isEmpty else { return nil }
        let numberWords = run.filter { units[$0] != nil || tens[$0] != nil || scales[$0] != nil }
        // Digit-by-digit: "one four two zero" (≥3 single digits, or any zero).
        if numberWords.allSatisfy({ (units[$0] ?? 99) < 10 }), numberWords.count >= 3 || numberWords.contains("zero") || numberWords.contains("oh") {
            let value = Int(numberWords.map { String(units[$0]!) }.joined()) ?? 0
            return value > 0 ? Money(minorUnits: Int64(value) * 100, currency: currency) : nil
        }
        // "fourteen twenty" — two chunks, no scale word: 14|20 → 1420.
        if numberWords.count == 2, !run.contains("and"), scales[numberWords[0]] == nil, scales[numberWords[1]] == nil,
           let a = units[numberWords[0]] ?? tens[numberWords[0]], a >= 10, let b = units[numberWords[1]] ?? tens[numberWords[1]], b >= 10 {
            return Money(minorUnits: Int64(a * 100 + b) * 100, currency: currency)
        }
        var total = 0, current = 0, dollars: Int? = nil, cents: Int? = nil
        for word in run {
            if let u = units[word] { current += u }
            else if let t = tens[word] { current += t }
            else if let sc = scales[word] {
                if current == 0 { current = 1 }
                if sc == 100 { current *= 100 } else { total += current * sc; current = 0 }
            } else if word == "dollars" || word == "dollar" || word == "bucks" { dollars = total + current; total = 0; current = 0 }
            else if word == "cents" || word == "cent" { cents = total + current; total = 0; current = 0 }
        }
        let remaining = total + current
        if dollars == nil { dollars = remaining } else if cents == nil, remaining > 0 { cents = remaining }
        let value = Int64((dollars ?? 0) * 100 + (cents ?? 0))
        return value > 0 ? Money(minorUnits: value, currency: currency) : nil
    }
}

/// Deterministic check on model-written text: every dollar amount it
/// contains must appear verbatim in the source text the model was given.
/// Sentences with an unknown amount are replaced by the source itself.
public enum NumberGuard {
    static let amountPattern = #"\(?\$\s?\d[\d,]*(?:\.\d{2})?\)?|(?<![\w.])\d{1,3}(?:,\d{3})+(?:\.\d{2})?(?![\w.])|(?<![\w.$])\d+\.\d{2}(?![\w.])"#

    public static func amounts(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: amountPattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    static func key(_ s: String) -> String { s.filter { $0.isNumber } }

    public struct Result: Sendable, Equatable {
        public let text: String
        public let replacedSentences: Int
    }

    /// `source` is everything the model was allowed to know for this turn.
    public static func check(_ spoken: String, source: String) -> Result {
        let allowed = Set(amounts(in: source).map(key))
        // Split on sentence ends only (a period followed by space/newline/end), never inside "3,293.02".
        let sentences = spoken.replacingOccurrences(of: #"(?<=[.!?])\s+|\n+"#, with: "\u{1F}", options: .regularExpression)
            .split(separator: "\u{1F}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var replaced = 0
        var kept: [String] = []
        for sentence in sentences {
            let bad = amounts(in: sentence).map(key).filter { !allowed.contains($0) }
            if bad.isEmpty { kept.append(sentence) } else { replaced += 1 }
        }
        if replaced == 0 { return Result(text: spoken, replacedSentences: 0) }
        let fallback = source.components(separatedBy: "\n").filter { !$0.isEmpty }.suffix(6).joined(separator: " ")
        let text = (kept.isEmpty ? [] : [kept.joined(separator: " ")]) + [fallback]
        return Result(text: text.joined(separator: " "), replacedSentences: replaced)
    }

    /// For typed Ask AI answers: same rule as `check` (a sentence citing a
    /// figure that is not in `source` is removed), but paragraphs are kept
    /// and nothing is substituted, so a report answer is never replaced by
    /// raw context lines.
    public struct ProseResult: Sendable, Equatable {
        public let text: String
        public let removedSentences: Int
    }

    public static func scrubProse(_ answer: String, source: String) -> ProseResult {
        let allowed = Set(amounts(in: source).map(key))
        var removed = 0
        var paragraphs: [String] = []
        for paragraph in answer.components(separatedBy: "\n") {
            if paragraph.trimmingCharacters(in: .whitespaces).isEmpty { paragraphs.append(""); continue }
            let sentences = paragraph.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\u{1F}", options: .regularExpression)
                .split(separator: "\u{1F}").map { String($0) }
            let kept = sentences.filter { sentence in
                let bad = amounts(in: sentence).map(key).filter { !allowed.contains($0) }
                if !bad.isEmpty { removed += 1 }
                return bad.isEmpty
            }
            paragraphs.append(kept.joined(separator: " "))
        }
        if removed == 0 { return ProseResult(text: answer, removedSentences: 0) }
        let text = paragraphs.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return ProseResult(text: "I could not verify the figures in that answer against this page's data, so I withheld it. Ask again, or ask about one specific item.", removedSentences: removed)
        }
        let note = "Note: \(removed) sentence\(removed == 1 ? "" : "s") removed because \(removed == 1 ? "it cited a figure" : "they cited figures") that is not in this page's data."
        return ProseResult(text: text + "\n\n" + note, removedSentences: removed)
    }
}
