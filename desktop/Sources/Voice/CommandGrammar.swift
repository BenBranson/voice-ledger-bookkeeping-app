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
        // The recognizer hears "spend" as "spin" (owner, 2026-10-02: "vendor by
        // spin"). No command uses the word "spin", so read it as "spend".
        t = t.replacingOccurrences(of: #"\bspin\b"#, with: "spend", options: .regularExpression)
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
        (.allOpen, ["findings", "open findings", "all findings", "everything open", "open items", "issues", "problems", "exceptions", "what's open", "whats open", "what is open",
                   "how many open findings", "how many findings", "how many findings are open", "how many issues", "how many problems", "how many open items", "how many exceptions"])
    ]

    static let kpiPhrases: [(KPIMetric, [String])] = [
        (.revenue, ["revenue", "sales", "income", "total income", "top line"]),
        (.netIncome, ["net income", "profit", "net profit", "bottom line", "net loss", "the loss"]),
        (.cashBalance, ["cash", "cash balance", "bank balance", "cash in the bank", "money in the bank", "cash on hand", "total bank"]),
        (.workingCapital, ["working capital", "net working capital"]),
        (.currentRatio, ["current ratio"]),
        (.quickRatio, ["quick ratio", "acid test", "acid test ratio"]),
        (.grossMargin, ["gross margin", "gross profit margin", "gross margin percent"]),
        (.netMargin, ["net margin", "net profit margin", "profit margin", "net margin percent"])
    ]

    static let chartPhrases: [(ChartKind, [String])] = [
        (.expenseDrivers, ["expenses", "expense", "expense drivers", "expense categories", "top expenses", "spending", "where the money went", "biggest expenses", "largest expenses",
                           "top expense categories", "biggest expense categories", "what are we spending the most on", "where is the money going", "where's the money going"]),
        (.vendorSpend, ["vendors", "vendor", "vendor spend", "spend by vendor", "top vendors", "vendor by spend", "vendors by spend", "top vendors by spend",
                        "vendor spending", "spending by vendor", "biggest vendors", "largest vendors", "who do we spend the most with", "who do we pay the most"]),
        (.incomeVsExpenses, ["income vs expenses", "income versus expenses", "income and expenses", "revenue vs expenses", "revenue versus expenses"]),
        (.pareto, ["pareto", "cost drivers", "biggest cost drivers"]),
        (.receivables, ["receivables", "accounts receivable", "receivables aging", "aging of receivables", "customer aging", "who owes us chart", "receivables by customer"]),
        (.payables, ["payables", "accounts payable", "payables aging", "aging of payables", "vendor aging", "bills by vendor", "payables by vendor"]),
        (.revenueTrend, ["revenue", "sales", "revenue trend", "revenue by month", "monthly revenue", "sales by month", "sales trend", "income trend"]),
        (.cashOutlook, ["cash", "cash balance", "cash outlook", "cash forecast", "cash projection"]),
        (.netIncomeTrend, ["net income", "profit", "net income trend", "net income by month", "profit by month", "monthly profit", "profit trend", "monthly net income"])
    ]

    /// Bare phrases the grammar answers, for "did you mean" suggestions.
    static var knownPhrases: [String] {
        var all: [String] = []
        for (_, p) in groupAliases { all += p + p.map { "pull up the " + $0 } + p.map { "show me the " + $0 } }
        for (_, p) in kpiPhrases { all += p + p.map { "what's our " + $0 } + p.map { "what is the " + $0 } }
        for (_, p) in chartPhrases { all += p + p.map { $0 + " chart" } + p.map { "chart the " + $0 } }
        all += ["who owes us", "what do we owe", "what are we owed", "how much cash do we have", "when did we last sync", "is this current",
                "try again", "start month end", "charts", "go back", "go forward"]
        return all
    }

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

        // Plain-English profit questions (owner test 2026-10-02: "how much did we make this month"
        // went to the AI model and came back about credit cards).
        if ["how much did we make", "how much money did we make", "how much profit did we make", "what did we make", "are we profitable", "were we profitable",
            "did we make money", "are we making money", "did we make a profit", "did we turn a profit", "how did we do", "how are we doing", "what's our profit", "whats our profit"].contains(q) {
            return .kpi(.netIncome, period)
        }

        // "how much cash do we have" and friends
        if ["how much cash do we have", "how much cash have we got", "how much money do we have", "how much money is in the bank", "how much do we have in the bank", "how much is in the bank"].contains(t) { return .kpi(.cashBalance, .current) }

        // The answer to "Which chart?" — a bare chart name.
        for (kind, phrases) in chartPhrases where phrases.contains(t) && t != "income" { return .chart(kind) }
        // "show net income trend", "pull up revenue by month" — only chart-only phrases
        // (trend / by month / outlook), so "show vendors" still opens the Vendors page.
        for verb in openVerbs where t.hasPrefix(verb + " ") {
            let rest = strip(String(t.dropFirst(verb.count + 1)), ["the", "my", "our"])
            for (kind, phrases) in chartPhrases where phrases.contains(rest)
                && ["trend", "by month", "monthly", "outlook", "forecast", "projection", "biggest", "largest", "top "].contains(where: { rest.contains($0) }) { return .chart(kind) }
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

        // Totals, no vendor named (the recognizer's "own" is accepted for "owe").
        let totalOwedPhrases: Set<String> = ["what do we owe", "what do we own", "what do we oh", "how much do we owe", "how much do we own", "what do i owe", "how much do i owe",
                                             "what do we owe in total", "what do we owe overall", "what do we owe vendors", "what do we owe our vendors", "what bills do we have",
                                             "what bills are due", "what bills are open", "what bills do we owe", "what's our accounts payable", "whats our accounts payable",
                                             "what is our accounts payable", "how much accounts payable", "total payables", "what are our payables", "what are our open bills", "what are we paying"]
        if totalOwedPhrases.contains(t) { return .totalOwed }
        let totalReceivablePhrases: Set<String> = ["what are we owed", "who owes us", "who owes us money", "how much are we owed", "what do customers owe", "what do customers owe us", "what's our accounts receivable",
                                                   "whats our accounts receivable", "what is our accounts receivable", "total receivables", "what are our receivables", "how much do customers owe us", "what are our open invoices", "who hasn't paid", "who hasnt paid"]
        if totalReceivablePhrases.contains(t) { return .totalReceivable }
        let topCustomer: Set<String> = ["who owes us the most", "who owes the most", "which customer owes us the most", "which customer owes the most", "what customer owes us the most",
                                         "who owes us the most money", "biggest receivable", "largest receivable", "who is our biggest debtor", "which customer has the biggest balance",
                                         "which customer has the largest balance", "who has the biggest balance", "top customer balance", "biggest customer balance"]
        if topCustomer.contains(t) { return .topBalance(receivables: true) }
        // "anything unusual with Permian Supply" — the open findings for one name, listed by
        // code (owner test 2026-10-02: the AI model paired a real amount with the wrong issue).
        for lead in ["is there anything unusual with ", "anything unusual with ", "is anything unusual with ", "anything unusual about ", "is there anything wrong with ",
                     "is anything wrong with ", "anything wrong with ", "what's wrong with ", "whats wrong with ", "any issues with ", "any problems with ",
                     "are there any issues with ", "are there any problems with ", "issues with ", "problems with ", "findings for ", "open findings for "] where t.hasPrefix(lead) {
            let n = strip(String(t.dropFirst(lead.count)), articles)
            if !n.isEmpty { return .nameFindings(n) }
        }
        // "what does Freeman owe us", "how much does Video Games by Dan owe"
        if let r = t.range(of: #"^(?:what does|what do|how much does|how much do|what is|whats|what's|how much is) (.+?) (?:owe|own|owes|owing)(?: us)?(?: in total| right now| now)?$"#, options: .regularExpression) {
            let name = t[r].replacingOccurrences(of: #"^(?:what does|what do|how much does|how much do|what is|whats|what's|how much is) "#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #" (?:owe|own|owes|owing)(?: us)?(?: in total| right now| now)?$"#, with: "", options: .regularExpression)
            let n = strip(name, articles)
            if !n.isEmpty, !["we", "i", "our customers", "customers", "everyone", "everybody"].contains(n) { return .customerOwes(n) }
        }
        let topVendor: Set<String> = ["who do we owe the most", "which vendor do we owe the most", "what vendor do we owe the most", "who do we owe the most money", "biggest payable",
                                      "largest payable", "which vendor has the biggest balance", "which bill is the biggest", "biggest vendor balance", "who do we own the most", "which vendor do we own the most"]
        if topVendor.contains(t) { return .topBalance(receivables: false) }

        // What we owe a vendor. Recognizers hear "owe" as "own", "oh" and "ow", so accept those before a name.
        for lead in ["what do we owe ", "what do we own ", "what do we oh ", "how much do we owe ", "how much do we own ", "how much do we oh ", "what do i owe ", "what do i own ",
                     "how much do i owe ", "do we owe ", "what are we owing ", "what is owed to ", "what's owed to ", "how much is owed to ", "what do we owe to ", "what do we own to "] where t.hasPrefix(lead) {
            let name = strip(String(t.dropFirst(lead.count)), articles + ["to"])
            if !name.isEmpty, !["in total", "overall", "vendors", "our vendors", "everyone", "all vendors", "total"].contains(name), SpokenNumber.amount(in: name) == nil { return .vendorOwed(name.replacingOccurrences(of: #" \?$"#, with: "", options: .regularExpression)) }
        }

        // Vendor: "what do we owe <vendor>", "how much have we paid <vendor>", "transactions from/for/with <vendor>"
        for lead in ["how much have we paid ", "how much did we pay ", "what have we paid ", "what did we pay ", "transactions from ", "transactions for ", "transactions with ", "payments to ", "everything from ", "purchases from ", "spend with ", "spending with "] where t.hasPrefix(lead) {
            let name = strip(String(t.dropFirst(lead.count)), articles)
            if !name.isEmpty, SpokenNumber.amount(in: name) == nil { return .searchVendor(name) }
        }

        // Charts: a bare request asks which; "<thing> chart" / "chart of <thing>" picks one.
        let bareChart: Set<String> = ["chart", "charts", "show charts", "show me charts", "show me a chart", "show a chart", "pull up charts", "pull up a chart", "graphs", "graph", "show me graphs", "open charts", "i want a chart", "make a chart", "draw a chart"]
        if bareChart.contains(t) { return .chartMenu }
        for (kind, phrases) in chartPhrases {
            for ph in phrases {
                for form in ["\(ph) chart", "\(ph) graph", "the \(ph) chart", "a \(ph) chart", "show me the \(ph) chart", "show me a \(ph) chart", "pull up the \(ph) chart", "show the \(ph) chart", "open the \(ph) chart"] where t == form { return .chart(kind) }
            }
        }
        for lead in ["show me a pie chart of ", "show a pie chart of ", "pie chart of ", "show me a bar chart of ", "bar chart of "] where t.hasPrefix(lead) {
            let what = strip(String(t.dropFirst(lead.count)), articles)
            for (kind, phrases) in chartPhrases where phrases.contains(what) { return .chart(kind) }
        }
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
