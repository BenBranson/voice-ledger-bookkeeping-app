import Foundation
import Core

/// A small grammar for spoken commands: strip filler, then match
/// verb + object + argument. Everything it recognizes is resolved in code
/// from `ClientFacts`; the model is only consulted when nothing here fits.
/// See docs/MONEYPENNY_CONSISTENCY_DESIGN.md Part 2.
public enum CommandGrammar {
    static let fillers = ["hey moneypenny", "moneypenny", "hey voice ledger", "voice ledger", "can you", "could you", "would you", "please",
                          "i want to", "i want you to", "i need to", "i'd like to", "i would like to", "let's", "lets", "just", "go ahead and"]
    static let openVerbs = ["pull up", "bring up", "open up", "open", "show me", "show", "display", "list", "go to", "take me to", "navigate to", "get me", "find me", "see"]
    static let articles = ["the", "a", "an", "my", "our", "this", "that", "all", "all the", "all of the", "any", "some", "every"]

    public static func normalize(_ text: String) -> String {
        var t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: #"[?!.,]+$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "&", with: "and")
        for tail in [" please", " thanks", " thank you", " for me", " now", " right now"] where t.hasSuffix(tail) { t = String(t.dropLast(tail.count)) }
        t = t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        var changed = true
        while changed {
            changed = false
            for f in fillers where t.hasPrefix(f + " ") || t == f { t = String(t.dropFirst(f.count)).trimmingCharacters(in: .whitespaces); changed = true }
        }
        return t
    }

    static func strip(_ t: String, _ words: [String]) -> String {
        var s = t
        for w in words.sorted(by: { $0.count > $1.count }) where s.hasPrefix(w + " ") { s = String(s.dropFirst(w.count + 1)); break }
        return s
    }

    static let groupAliases: [(FactFindingGroup, [String])] = [
        (.duplicates, ["duplicates", "duplicate", "dupes", "duplicate findings", "duplicate transactions", "duplicate expenses", "duplicate invoices", "duplicate payments", "duplicate vendors", "duplicate bills"]),
        (.miscategorizedOrUncategorized, ["uncategorized", "uncategorized transactions", "uncategorised", "miscategorized", "miscategorized transactions", "categorization issues", "unclassified"]),
        (.personalExpense, ["personal expenses", "personal expense", "owner draws", "personal charges", "personal spending"]),
        (.negativeBalance, ["negative balances", "negative balance", "overdrawn accounts", "overdrafts", "overdrawn"]),
        (.lateFeesOrOverdrafts, ["late fees", "fees", "avoidable fees", "bank fees", "overdraft fees"]),
        (.vendorPriceIncrease, ["price increases", "vendor price increases", "price changes", "vendors charging more"]),
        (.balanceSheetIntegrity, ["balance sheet issues", "balance sheet problems", "balance sheet findings", "suspense", "suspense and clearing", "clearing accounts", "opening balance equity"]),
        (.cleanupAssessment, ["cleanup findings", "cleanup issues", "cleanup items"]),
        (.allOpen, ["findings", "open findings", "all findings", "everything open", "open items", "issues", "problems", "exceptions", "what's open", "whats open", "what is open"])
    ]

    static let kpiPhrases: [(KPIMetric, [String])] = [
        (.revenue, ["revenue", "sales", "income", "total income", "top line"]),
        (.netIncome, ["net income", "profit", "net profit", "bottom line", "net loss", "the loss"]),
        (.cashBalance, ["cash", "cash balance", "bank balance", "cash in the bank", "money in the bank", "cash on hand", "total bank"])
    ]

    static let chartPhrases: [(ChartKind, [String])] = [
        (.expenseDrivers, ["expenses", "expense drivers", "expense categories", "top expenses", "spending", "where the money went"]),
        (.vendorSpend, ["vendors", "vendor spend", "spend by vendor", "top vendors"]),
        (.incomeVsExpenses, ["income vs expenses", "income versus expenses", "income and expenses", "revenue vs expenses", "revenue versus expenses"]),
        (.pareto, ["pareto", "cost drivers", "biggest cost drivers"])
    ]

    /// nil = the grammar doesn't cover this; let the caller fall back.
    public static func parse(_ raw: String) -> VoiceIntent? {
        let t = normalize(raw)
        guard !t.isEmpty else { return nil }

        // Back / forward
        if ["go back", "back", "previous page", "go back a page", "back up", "previous", "return", "go back to the previous page", "last page", "go to the last page"].contains(t) { return .goBack }
        if ["go forward", "forward", "next page"].contains(t) { return .goForward }

        // Freshness
        if t.hasPrefix("when did we last sync") || t.hasPrefix("when was the last sync") || t.hasPrefix("is this current") || t.hasPrefix("is this up to date")
            || t.hasPrefix("how fresh is") || t.hasPrefix("how old is this data") || t.hasPrefix("has this been synced") || t == "sync status" || t == "data status" { return .freshness }

        // KPIs: "what's our revenue (this month|last month)"
        var period: PeriodChoice = .current
        var q = t
        for lm in [" last month", " for last month", " in the prior month", " prior month", " the prior month"] where q.hasSuffix(lm) { q = String(q.dropLast(lm.count)); period = .priorMonth }
        for tm in [" this month", " for this month", " so far this month", " currently", " right now", " now", " today"] where q.hasSuffix(tm) { q = String(q.dropLast(tm.count)) }
        let questionLead = ["what's", "whats", "what is", "what was", "what are", "how much is", "how much was", "how much did we make", "tell me", "give me", "read me"]
        var body = strip(q, questionLead)
        body = strip(body, articles)
        body = strip(body, ["the"])
        for (metric, phrases) in kpiPhrases where phrases.contains(body) || phrases.contains(where: { body == $0 + " for the month" || body == $0 + " for the month so far" }) {
            return .kpi(metric, period)
        }

        // Account balance: "balance of/in/on <account>", "<account> balance", "how much is in <account>"
        if let range = t.range(of: #"^(?:what's |whats |what is |what was |tell me |give me |read me )?(?:the )?(?:current )?balance (?:of|in|on|for) (?:the )?(.+?)(?: account)?$"#, options: .regularExpression) {
            _ = range
            let name = t.replacingOccurrences(of: #"^(?:what's |whats |what is |what was |tell me |give me |read me )?(?:the )?(?:current )?balance (?:of|in|on|for) (?:the )?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #" account$"#, with: "", options: .regularExpression)
            if !name.isEmpty { return .accountBalance(name) }
        }
        if let m = t.range(of: #"^(?:how much (?:is|do we have) in (?:the )?)(.+?)(?: account)?$"#, options: .regularExpression) {
            _ = m
            let name = t.replacingOccurrences(of: #"^how much (?:is|do we have) in (?:the )?"#, with: "", options: .regularExpression).replacingOccurrences(of: #" account$"#, with: "", options: .regularExpression)
            if !name.isEmpty { return .accountBalance(name) }
        }
        if t.hasSuffix(" balance"), !t.contains(" of "), let name = Optional(String(t.dropLast(" balance".count))).map({ strip(strip($0, questionLead), articles) }), !name.isEmpty,
           !groupAliases.contains(where: { $0.1.contains(name + " balance") }), name != "negative", name != "cash", name != "bank" {
            return .accountBalance(name)
        }

        // Hands-free correction: say it again without touching the mouse.
        if ["try again", "again", "retry", "let me try again", "start over", "scratch that", "that's wrong", "thats wrong", "that is wrong", "wrong",
            "that's not right", "thats not right", "no that's wrong", "no thats wrong", "no", "nope", "never mind", "nevermind", "cancel that", "cancel", "clear that", "clear", "dismiss", "close that", "listen again", "i said"].contains(t) {
            return .retry
        }

        // What we owe a vendor. Recognizers hear "owe" as "own", "oh" and "ow", so accept those before a name.
        for lead in ["what do we owe ", "what do we own ", "what do we oh ", "how much do we owe ", "how much do we own ", "how much do we oh ", "what do i owe ", "what do i own ",
                     "how much do i owe ", "do we owe ", "what are we owing ", "what is owed to ", "what's owed to ", "how much is owed to ", "what do we owe to ", "what do we own to "] where t.hasPrefix(lead) {
            let name = strip(String(t.dropFirst(lead.count)), articles + ["to"])
            if !name.isEmpty, SpokenNumber.amount(in: name) == nil { return .vendorOwed(name.replacingOccurrences(of: #" \?$"#, with: "", options: .regularExpression)) }
        }

        // Vendor: "what do we owe <vendor>", "how much have we paid <vendor>", "transactions from/for/with <vendor>"
        for lead in ["how much have we paid ", "how much did we pay ", "what have we paid ", "what did we pay ", "transactions from ", "transactions for ", "transactions with ", "payments to ", "everything from ", "purchases from ", "spend with ", "spending with "] where t.hasPrefix(lead) {
            let name = strip(String(t.dropFirst(lead.count)), articles)
            if !name.isEmpty, SpokenNumber.amount(in: name) == nil { return .searchVendor(name) }
        }

        // Charts
        for lead in ["chart ", "graph ", "chart the ", "graph the ", "show me a chart of ", "show a chart of ", "show me a graph of ", "chart of ", "graph of ", "chart my ", "graph my "] where t.hasPrefix(lead) {
            let what = strip(String(t.dropFirst(lead.count)), articles)
            for (kind, phrases) in chartPhrases where phrases.contains(what) { return .chart(kind) }
        }

        // Open / find something: strip a verb, then decide by what's left.
        var rest = strip(t, openVerbs)
        let hadVerb = rest != t
        let wasSearch = t.hasPrefix("find ") || t.hasPrefix("search ") || t.hasPrefix("search for ") || t.hasPrefix("look up ") || t.hasPrefix("look for ") || t.hasPrefix("any ") || t.hasPrefix("is there a ") || t.hasPrefix("is there an ") || t.hasPrefix("do we have a ")
        if wasSearch { rest = strip(strip(strip(t, ["find", "search for", "search", "look up", "look for", "any", "is there a", "is there an", "do we have a"]), articles), ["transaction for", "transactions for", "transaction of", "transactions of", "transaction", "transactions", "charge for", "charge of", "payment for", "payment of", "expense for", "expense of"]) }
        rest = strip(rest, articles)

        // Finding groups
        let groupKey = rest.replacingOccurrences(of: #"^(?:list of |the |my |our )"#, with: "", options: .regularExpression)
        for (group, aliases) in groupAliases where aliases.contains(groupKey) || aliases.contains(where: { groupKey == $0 + " findings" || groupKey == $0 + " issues" || groupKey == $0 + " items" }) {
            if hadVerb || wasSearch || groupKey == rest { return .findingsGroup(group) }
        }

        // Amount → a finding with that amount, else the transaction search
        if let amount = SpokenNumber.amount(in: rest) {
            let isFinding = rest.contains("finding") || rest.contains(" one") || rest.hasSuffix("one") || rest.contains("issue") || rest.contains("item") || rest.contains("flag")
            if wasSearch && !isFinding { return .searchAmount(amount) }
            return .openFindingMatching(amount: amount, text: rest)
        }

        // "pull up the Cool Cars payment" / "open the duplicate invoice"
        if hadVerb, !rest.isEmpty, rest.split(separator: " ").count <= 6 {
            return .openFindingMatching(amount: nil, text: rest)
        }
        if wasSearch, !rest.isEmpty, rest.split(separator: " ").count <= 5 {
            return .searchVendor(rest)
        }
        return nil
    }
}
