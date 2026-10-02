import Testing
@testable import Voice

@Suite("Spoken replies are shorter than the displayed ones")
struct SpeechShorteningTests {
    let full = "We owe Norton Lumber $2,149.93: $756.93 current and $1,393.00 past due. July 2026, synced 30 minutes ago."

    @Test("Fresh data: the closing scope sentence is dropped from speech")
    func freshDropsScope() {
        #expect(VoiceSpeechFormatter.shortenForSpeech(full, dataIsFresh: true) == "We owe Norton Lumber $2,149.93: $756.93 current and $1,393.00 past due.")
        #expect(VoiceSpeechFormatter.shortenForSpeech("1 transaction. July 2026, including the 24-month history, synced just now.", dataIsFresh: true) == "1 transaction.")
    }

    @Test("Stale or unsynced data: everything is spoken")
    func staleKeepsScope() {
        #expect(VoiceSpeechFormatter.shortenForSpeech(full, dataIsFresh: false) == full)
        #expect(VoiceSpeechFormatter.shortenForSpeech("Balance is $5.00. July 2026, saved data from 2 hours ago — sync to refresh.", dataIsFresh: true).contains("saved data"))
    }

    @Test("A promise to navigate is detected; plain explanations are not")
    func promises() {
        #expect(VoiceSpeechFormatter.promisesAnAction("To see what you owe, I'll pull up the accounts payable report for you."))
        #expect(VoiceSpeechFormatter.promisesAnAction("Opening the Balance Sheet now."))
        #expect(!VoiceSpeechFormatter.promisesAnAction("Opening Balance Equity carries a nonzero balance of $9,247.50."))
        #expect(!VoiceSpeechFormatter.promisesAnAction("That finding is flagged because two invoices share an amount."))
    }
}
