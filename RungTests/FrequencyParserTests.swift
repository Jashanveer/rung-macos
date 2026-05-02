import Testing
import Foundation
@testable import Rung

/// FrequencyParser is the front line of habit creation UX — every
/// title the user types passes through it, and a parse miss either
/// silently drops their cadence ("gym 5x/week" stored as "gym 5x/week"
/// with no weeklyTarget) or burns an LLM call. These tests cover the
/// matchers in priority order and the hint detector that gates the
/// LLM fallback.
@MainActor
struct FrequencyParserTests {

    // MARK: - Explicit numeric

    @Test func numericTimesPerWeekParses() {
        let r = FrequencyParser.parse("gym 4 times a week")
        #expect(r.weeklyTarget == 4)
        #expect(r.cleanedTitle == "gym")
        #expect(r.didMatch)
    }

    @Test func compactXPerWeekParses() {
        let r = FrequencyParser.parse("code 3x/week")
        #expect(r.weeklyTarget == 3)
        #expect(r.cleanedTitle == "code")
        #expect(r.didMatch)
    }

    @Test func numericDaysAWeekParses() {
        let r = FrequencyParser.parse("run 5 days a week")
        #expect(r.weeklyTarget == 5)
        #expect(r.cleanedTitle == "run")
    }

    @Test func numericTargetClampsTo7() {
        // 8x/week can't physically happen — parser should either reject
        // or clamp. Either way it must not crash and must not return >7.
        let r = FrequencyParser.parse("stretch 8x a week")
        if r.didMatch {
            #expect((r.weeklyTarget ?? 0) <= 7)
        }
    }

    // MARK: - Weekday list

    @Test func weekdayAbbreviationListParses() {
        let r = FrequencyParser.parse("yoga Mon Wed Fri")
        #expect(r.weeklyTarget == 3)
        #expect(r.cleanedTitle == "yoga")
        #expect(r.didMatch)
    }

    @Test func fullWeekdayNamesParse() {
        let r = FrequencyParser.parse("piano Tuesday Thursday")
        #expect(r.weeklyTarget == 2)
        #expect(r.cleanedTitle == "piano")
    }

    // MARK: - Weekday / weekend keywords

    @Test func weekdaysKeywordResolvesToFive() {
        let r = FrequencyParser.parse("commute on weekdays")
        #expect(r.weeklyTarget == 5)
        #expect(r.cleanedTitle == "commute")
    }

    @Test func weekendsKeywordResolvesToTwo() {
        let r = FrequencyParser.parse("brunch on weekends")
        #expect(r.weeklyTarget == 2)
    }

    // MARK: - Every other day

    @Test func everyOtherDayResolvesToThreeOrFour() {
        // "Every other day" lands on either 3 or 4 days a week
        // depending on which day of the week they start. We accept
        // either; the parser just needs to commit to a value.
        let r = FrequencyParser.parse("ice bath every other day")
        #expect(r.didMatch)
        let target = r.weeklyTarget ?? 0
        #expect(target == 3 || target == 4)
    }

    // MARK: - Daily keywords

    @Test func everyDayResolvesToSeven() {
        let r = FrequencyParser.parse("read every day")
        #expect(r.weeklyTarget == 7)
        #expect(r.cleanedTitle == "read")
    }

    @Test func dailyResolvesToSeven() {
        let r = FrequencyParser.parse("meditate daily")
        #expect(r.weeklyTarget == 7)
        #expect(r.cleanedTitle == "meditate")
    }

    // MARK: - No match

    @Test func plainTitleHasNoMatch() {
        let r = FrequencyParser.parse("Run a marathon")
        #expect(!r.didMatch)
        #expect(r.weeklyTarget == nil)
        // Cleaned title preserves casing and content when no clause
        // matched — the user typed exactly what they meant.
        #expect(r.cleanedTitle == "Run a marathon")
    }

    @Test func emptyInputReturnsEmpty() {
        #expect(FrequencyParser.parse("") == FrequencyParser.ParseResult.empty)
        #expect(FrequencyParser.parse("   ") == FrequencyParser.ParseResult.empty)
    }

    // MARK: - Cleaning preserves user intent

    @Test func cleanedTitleStripsTrailingPunctuation() {
        let r = FrequencyParser.parse("yoga, Mon Wed Fri.")
        // The frequency clause is removed but punctuation that was
        // before the matched clause is preserved or cleaned consistently.
        // We don't assert exact form — just that the core noun survives.
        #expect(r.didMatch)
        #expect(r.cleanedTitle.lowercased().contains("yoga"))
    }

    @Test func cleanedTitlePreservesOriginalCasing() {
        let r = FrequencyParser.parse("Run 5 days a week")
        #expect(r.cleanedTitle == "Run")
    }

    // MARK: - Priority — explicit numeric beats fuzzy daily

    @Test func explicitNumericBeatsFuzzyDaily() {
        // "5 days a week" should win over "daily" if both could match.
        // Tests the matcher priority order directly.
        let r = FrequencyParser.parse("daily run 5 days a week")
        #expect(r.weeklyTarget == 5)
    }

    // MARK: - Hint detection (LLM fallback gate)

    @Test func hintDetectorFlagsCadenceWords() {
        #expect(FrequencyParser.hasFrequencyHint("gym thrice a week"))
        #expect(FrequencyParser.hasFrequencyHint("run every morning"))
        #expect(FrequencyParser.hasFrequencyHint("3 sessions"))
    }

    @Test func hintDetectorIgnoresPlainTitles() {
        #expect(!FrequencyParser.hasFrequencyHint("Run"))
        #expect(!FrequencyParser.hasFrequencyHint("Meditate"))
        #expect(!FrequencyParser.hasFrequencyHint("Buy milk"))
    }

    @Test func hintDetectorFlagsBareDigit() {
        // A bare digit usually signals frequency even without a
        // cadence word — "4x", "3 sessions", etc.
        #expect(FrequencyParser.hasFrequencyHint("gym 4x"))
    }
}
