import Foundation

/// Reads currency as amounts instead of spelling out each digit. The exact
/// formatted dollars stay on screen and in the transcript; only TTS receives
/// this spoken rendering.
public enum VoiceSpeechFormatter {
    private static let amountPattern = #"\(\s*\$\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?\s*\)|(?<![\w])\$\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"#

    public static func formatCurrency(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: amountPattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            let raw = ns.substring(with: match.range)
            let negative = raw.contains("(")
            let numeric = raw.filter { $0.isNumber || $0 == "." }
            let pieces = numeric.split(separator: ".", omittingEmptySubsequences: false)
            guard let dollars = Int64(pieces.first.map(String.init) ?? "") else { continue }
            let cents = pieces.count > 1 ? Int(String(pieces[1].prefix(2)).padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0 : 0
            var words = Self.integerWords(dollars) + (dollars == 1 ? " dollar" : " dollars")
            if cents > 0 { words += " and \(Self.integerWords(Int64(cents))) \(cents == 1 ? "cent" : "cents")" }
            if negative { words = "negative " + words }
            result = (result as NSString).replacingCharacters(in: match.range, with: words)
        }
        return result
    }

    private static func integerWords(_ value: Int64) -> String {
        if value == 0 { return "zero" }
        let scales = ["", "thousand", "million", "billion", "trillion", "quadrillion"]
        let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        func underThousand(_ n: Int) -> String {
            var parts: [String] = []; var n = n
            if n >= 100 { parts += [ones[n / 100], "hundred"]; n %= 100 }
            if n >= 20 { parts.append(tens[n / 10]); if n % 10 > 0 { parts.append(ones[n % 10]) } }
            else if n > 0 { parts.append(ones[n]) }
            return parts.joined(separator: " ")
        }
        var remaining = value; var groups: [String] = []; var place = 0
        while remaining > 0 && place < scales.count {
            let group = Int(remaining % 1000)
            if group > 0 { groups.insert(underThousand(group) + (scales[place].isEmpty ? "" : " " + scales[place]), at: 0) }
            remaining /= 1000; place += 1
        }
        return groups.joined(separator: " ")
    }
}
