import Foundation

/// Parses natural-language habit titles to extract frequency hints.
///
/// Examples that resolve via the regex pass alone:
/// - "gym 4 days a week"      → weeklyTarget=4, cleaned="gym"
/// - "read every day"         → weeklyTarget=7, cleaned="read"
/// - "yoga Mon Wed Fri"       → weeklyTarget=3, cleaned="yoga"
/// - "run on weekdays"        → weeklyTarget=5, cleaned="run"
/// - "code 3x/week"           → weeklyTarget=3, cleaned="code"
///
/// Anything the regex doesn't match returns `.unparsed(original)` and the
/// caller can optionally hit the LLM fallback. The parser never mutates the
/// title in destructive ways — the cleaned title always strips only the
/// matched frequency clause and trims whitespace + trailing punctuation,
/// so legitimate words inside the title (e.g. "Run a marathon") survive.
enum FrequencyParser {
    struct ParseResult: Equatable {
        /// Cleaned habit title with the frequency clause removed.
        var cleanedTitle: String
        /// `nil` for daily/unspecified, `1...7` for explicit per-week target.
        /// `7` is functionally identical to "daily" — the caller decides
        /// whether to surface it as a weekly target or strip it.
        var weeklyTarget: Int?
        /// True when at least one regex matched. Lets the UI distinguish
        /// "user typed something with no frequency hint" (don't override) from
        /// "user typed an explicit cadence" (commit it).
        var didMatch: Bool

        static let empty = ParseResult(cleanedTitle: "", weeklyTarget: nil, didMatch: false)
    }

    /// True when `raw` contains a hint that the user is *trying* to encode
    /// a cadence — but the regex pass missed. Triggers the LLM fallback in
    /// the dashboard's add flow. Conservative on purpose so we don't burn
    /// AI calls on plain titles like "Read".
    static func hasFrequencyHint(_ raw: String) -> Bool {
        let lowered = raw.lowercased()
        let cadenceWords = ["week", "day", "every", "daily", "weekday", "weekend", "alternate", "times", "session", "morning", "evening", "night"]
        if cadenceWords.contains(where: { lowered.contains($0) }) { return true }
        // A bare digit ("4x", "3 sessions") usually signals frequency.
        if lowered.range(of: #"\d"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Best-effort parse. Always returns a result — the caller treats
    /// `didMatch == false` as "leave the user's input alone".
    static func parse(_ raw: String) -> ParseResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let lowered = trimmed.lowercased()

        // Try each pattern in priority order. First hit wins so explicit
        // numeric phrases ("4 times a week") beat fuzzy ones ("daily").
        for matcher in matchers {
            if let hit = matcher(lowered, trimmed) {
                return hit
            }
        }

        return ParseResult(cleanedTitle: trimmed, weeklyTarget: nil, didMatch: false)
    }

    // MARK: - Matchers

    /// All matchers share the same shape: `(lowered, original) -> ParseResult?`.
    /// They return nil to fall through to the next matcher. The original-cased
    /// string is threaded through so the cleaned title preserves the user's
    /// capitalisation ("Run", not "run").
    private static var matchers: [(String, String) -> ParseResult?] {
        [
            matchExplicitNumeric,
            matchWeekdayList,
            matchWeekdaysWeekends,
            matchEveryOtherDay,
            matchDailyKeywords,
        ]
    }

    /// Captures phrases like "4 days a week", "4x a week", "4 times per week",
    /// "four days/week". Bounds are 1-7; anything outside silently falls
    /// through (so "gym 12 times a week" doesn't suggest weeklyTarget=12).
    private static func matchExplicitNumeric(_ lowered: String, _ original: String) -> ParseResult? {
        // Patterns we want to match (case-insensitive, lowered already):
        //   "(\d+|one|two|...) (days|times|x) (a|per|/) week"
        //   "(\d+|...)x/week"
        //   "(\d+|...) times weekly"
        let numberPattern = #"(\d+|one|two|three|four|five|six|seven)"#
        let connector = #"\s*(days?|times?|x|sessions?)?"#
        let separator = #"\s*(?:a|per|/|each|every)?\s*"#
        let weekWord = #"(?:week|wk)"#
        let suffix = #"(?:ly)?"#
        let pattern = "\\b\(numberPattern)\(connector)\(separator)\(weekWord)\(suffix)\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(lowered.startIndex..., in: lowered)
        guard let match = regex.firstMatch(in: lowered, range: range) else { return nil }

        let captured = (lowered as NSString).substring(with: match.range(at: 1))
        guard let count = numericValue(of: captured), (1...7).contains(count) else {
            return nil
        }

        let cleaned = removeRange(match.range, from: original)
        return ParseResult(cleanedTitle: cleaned, weeklyTarget: count, didMatch: true)
    }

    /// Captures lists of weekday names: "mon wed fri", "monday and thursday",
    /// "on tue, thu". Counts unique weekdays and returns that as the target.
    private static func matchWeekdayList(_ lowered: String, _ original: String) -> ParseResult? {
        // Build a master regex that finds any weekday token in the string,
        // then count distinct hits. The cleaned title drops every matched
        // span plus surrounding "on" / "every" / commas / "and"s.
        let dayPattern = #"\b(mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|saturdays?|sundays?|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)\b"#
        guard let dayRegex = try? NSRegularExpression(pattern: dayPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(lowered.startIndex..., in: lowered)
        let matches = dayRegex.matches(in: lowered, range: range)
        guard !matches.isEmpty else { return nil }

        var distinctDays = Set<Int>()
        for match in matches {
            let token = (lowered as NSString).substring(with: match.range)
            if let weekday = weekdayIndex(for: token) {
                distinctDays.insert(weekday)
            }
        }
        guard !distinctDays.isEmpty else { return nil }

        // Strip the weekday clause plus its leading conjunctions ("on",
        // "every", commas, "and") so "yoga on Mon and Wed" → "yoga".
        let connectorPattern = #"(?:\b(?:on|every|each)\s+)?(?:[\s,]+(?:and|&)\s+|\s*,\s*|\s+)*"#
        let combinedPattern = "\(connectorPattern)(?:\(dayPattern)(?:[\\s,]+(?:and|&)\\s+|\\s*,\\s*|\\s+)?)+"
        let cleaned: String
        if let combined = try? NSRegularExpression(pattern: combinedPattern, options: [.caseInsensitive]) {
            let combinedRange = NSRange(original.startIndex..., in: original)
            if let bigMatch = combined.firstMatch(in: original, range: combinedRange) {
                cleaned = removeRange(bigMatch.range, from: original)
            } else {
                cleaned = removeMatches(matches, from: original)
            }
        } else {
            cleaned = removeMatches(matches, from: original)
        }

        return ParseResult(cleanedTitle: cleaned, weeklyTarget: distinctDays.count, didMatch: true)
    }

    /// "weekdays" → 5, "weekends" → 2.
    private static func matchWeekdaysWeekends(_ lowered: String, _ original: String) -> ParseResult? {
        let pattern = #"\b(?:on\s+)?(weekdays?|weekends?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
        else { return nil }

        let token = (lowered as NSString).substring(with: match.range(at: 1))
        let target: Int
        switch token {
        case "weekdays", "weekday":  target = 5
        case "weekends", "weekend":  target = 2
        default: return nil
        }

        let cleaned = removeRange(match.range, from: original)
        return ParseResult(cleanedTitle: cleaned, weeklyTarget: target, didMatch: true)
    }

    /// "every other day" → ~3 times a week (rounded down so the user's
    /// commitment isn't auto-inflated).
    private static func matchEveryOtherDay(_ lowered: String, _ original: String) -> ParseResult? {
        let pattern = #"\b(?:every\s+other\s+day|alternate\s+days?|every\s+second\s+day)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
        else { return nil }

        let cleaned = removeRange(match.range, from: original)
        return ParseResult(cleanedTitle: cleaned, weeklyTarget: 3, didMatch: true)
    }

    /// "every day", "daily", "each day", "everyday" → 7.
    private static func matchDailyKeywords(_ lowered: String, _ original: String) -> ParseResult? {
        let pattern = #"\b(every\s*day|everyday|each\s+day|daily)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
        else { return nil }

        let cleaned = removeRange(match.range, from: original)
        return ParseResult(cleanedTitle: cleaned, weeklyTarget: 7, didMatch: true)
    }

    // MARK: - Helpers

    /// "4" → 4, "four" → 4. Returns nil for tokens we don't recognise.
    private static func numericValue(of token: String) -> Int? {
        if let n = Int(token) { return n }
        switch token.lowercased() {
        case "one":   return 1
        case "two":   return 2
        case "three": return 3
        case "four":  return 4
        case "five":  return 5
        case "six":   return 6
        case "seven": return 7
        default: return nil
        }
    }

    /// Maps weekday tokens to an index 1...7 (Mon..Sun) so we can dedupe a
    /// list of days the user listed twice ("Mon and Monday" still counts once).
    private static func weekdayIndex(for token: String) -> Int? {
        switch token.lowercased() {
        case "monday", "mondays", "mon": return 1
        case "tuesday", "tuesdays", "tue", "tues": return 2
        case "wednesday", "wednesdays", "wed": return 3
        case "thursday", "thursdays", "thu", "thur", "thurs": return 4
        case "friday", "fridays", "fri": return 5
        case "saturday", "saturdays", "sat": return 6
        case "sunday", "sundays", "sun": return 7
        default: return nil
        }
    }

    private static func removeRange(_ range: NSRange, from source: String) -> String {
        guard let swiftRange = Range(range, in: source) else { return source }
        var result = source
        result.removeSubrange(swiftRange)
        return tidy(result)
    }

    private static func removeMatches(_ matches: [NSTextCheckingResult], from source: String) -> String {
        var result = source
        // Walk from the end so earlier indexes don't shift.
        for match in matches.reversed() {
            if let r = Range(match.range, in: result) {
                result.removeSubrange(r)
            }
        }
        return tidy(result)
    }

    /// Collapses runs of whitespace, strips trailing punctuation, and trims
    /// the result so a cleaned title like " run  ,  " becomes "run".
    private static func tidy(_ s: String) -> String {
        let collapsedSpaces = s.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsedSpaces.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:-/"))
        )
        return trimmed
    }
}
