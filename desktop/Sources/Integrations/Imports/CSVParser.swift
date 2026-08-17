import Foundation

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.3, Tier 1: "No AI. The
/// preferred path whenever a real export exists." A minimal RFC 4180
/// tokenizer — quoted fields, embedded commas/newlines inside quotes,
/// `""` as an escaped quote. Deliberately does not attempt to guess
/// delimiters other than `,` or sniff encodings; a real export from a bank
/// is comma-delimited UTF-8 in practice, and guessing beyond that is the
/// kind of silent inference §9.3 exists to avoid.
public enum CSVParser {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        // Swift's `Character` is an extended grapheme cluster, so "\r\n" in
        // the source text is ONE `Character`, not two — it would match
        // neither the `"\r"` nor `"\n"` case below. Normalize line endings
        // first rather than trying to pattern-match a multi-scalar cluster.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(normalized)
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if insideQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    }
                    insideQuotes = false
                    i += 1
                    continue
                }
                currentField.append(c)
                i += 1
                continue
            }

            switch c {
            case "\"":
                insideQuotes = true
                i += 1
            case ",":
                currentRow.append(currentField)
                currentField = ""
                i += 1
            case "\n":
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
                i += 1
            default:
                currentField.append(c)
                i += 1
            }
        }

        // Trailing field/row with no final newline.
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        // Drop fully-empty trailing rows (a single "" field), the common
        // artifact of a file ending in a newline.
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
