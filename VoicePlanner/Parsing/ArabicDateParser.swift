//
//  ArabicDateParser.swift
//  VoicePlanner
//
//  Pulls a scheduled date out of dictated text, e.g.
//    "اتصل بأحمد غداً الساعة 5 مساءً"      → tomorrow 17:00
//    "اجتماع يوم الخميس الساعة عشرة ونص"   → next Thursday 10:30
//    "ذكرني بعد ساعتين"                    → now + 2h
//    "بكرة الصبح"                           → tomorrow 09:00
//
//  Why two strategies:
//  NSDataDetector works well for numeric and English dates ("25/9 17:00",
//  "tomorrow at 5pm"), but it does not understand Arabic relative expressions
//  such as "غداً" or "بعد ساعتين". Arabic text therefore goes through a
//  rule-based parser first, and NSDataDetector is the fallback. The
//  NaturalLanguage framework (NLLanguageRecognizer) picks which one runs first.
//

import Foundation
import NaturalLanguage

enum ArabicDateParser {

    // MARK: Public API

    static func parse(_ text: String, now: Date = .now) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isArabic(trimmed) {
            return parseArabic(trimmed, now: now) ?? detectDate(in: trimmed)
        } else {
            return detectDate(in: trimmed) ?? parseArabic(trimmed, now: now)
        }
    }

    /// NSDataDetector pass. Arabic-Indic digits are converted to ASCII first,
    /// so "٢٥/٩ ١٧:٠٠" is detected too.
    static func detectDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let normalized = normalize(text)
        let range = NSRange(normalized.startIndex..., in: normalized)
        return detector.matches(in: normalized, options: [], range: range).lazy.compactMap(\.date).first
    }

    /// Rule-based Arabic pass (MSA plus common Gulf/Levantine words).
    static func parseArabic(_ text: String, now: Date = .now) -> Date? {
        let s = normalize(text)
        let cal = calendar

        // "بعد ساعتين" / "بعد ١٠ دقائق" → exact offset from now.
        let relative = relativeOffset(in: s)
        if case .minutes(let minutes)? = relative {
            return cal.date(byAdding: .minute, value: minutes, to: now)
        }

        let days: Int?
        if case .days(let d)? = relative {
            days = d
        } else {
            days = dayOffset(in: s, now: now, calendar: cal)
        }
        let time = timeOfDay(in: s)
        guard days != nil || time != nil else { return nil }

        let dayStart = cal.startOfDay(for: now)
        guard
            let day = cal.date(byAdding: .day, value: (days ?? 0) + (time?.extraDay ?? 0), to: dayStart),
            var result = cal.date(bySettingHour: time?.hour ?? defaultHour, minute: time?.minute ?? 0, second: 0, of: day)
        else { return nil }

        // A time with no day ("الساعة 5") that has already passed today means tomorrow.
        if days == nil, result <= now, let next = cal.date(byAdding: .day, value: 1, to: result) {
            result = next
        }
        return result
    }

    // MARK: - Normalization

    /// Removes diacritics and tatweel, unifies alef/yaa/taa-marbuta, and converts
    /// Arabic-Indic and Persian digits to ASCII. All patterns below are written in
    /// this normalized form (e.g. "الساعه", not "الساعة").
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640:          // tashkeel, dagger alef, tatweel
                continue
            case 0x0660...0x0669:                           // ٠-٩
                scalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            case 0x06F0...0x06F9:                           // ۰-۹
                scalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            case 0x0622, 0x0623, 0x0625, 0x0671:            // آ أ إ ٱ
                scalars.append("ا")
            case 0x0649:                                    // ى
                scalars.append("ي")
            case 0x0629:                                    // ة
                scalars.append("ه")
            case 0x066B:                                    // Arabic decimal separator
                scalars.append(":")
            case 0x060C, 0x061B:                            // ، ؛
                scalars.append(" ")
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).lowercased()
    }

    // MARK: - Relative offsets ("بعد ساعتين")

    private enum RelativeOffset {
        case minutes(Int)
        case days(Int)
    }

    private static func relativeOffset(in s: String) -> RelativeOffset? {
        let pattern = "بعد\\s+(?:(\(numberPattern)|نصف|نص|ربع)\\s+)?"
            + "(ساعات|ساعتين|ساعه|دقائق|دقايق|دقيقتين|دقيقه|ايام|يومين|يوم|اسابيع|اسبوعين|اسبوع)(?!\\p{L})"
        guard let groups = firstMatch(pattern, in: s), let unit = groups[2] else { return nil }

        let quantity: Double
        switch groups[1] {
        case nil: quantity = 1
        case "نص"?, "نصف"?: quantity = 0.5
        case "ربع"?: quantity = 0.25
        case let token?: quantity = Double(numberValue(token) ?? 1)
        }

        switch unit {
        case "ساعه", "ساعات": return .minutes(Int(quantity * 60))
        case "ساعتين": return .minutes(120)
        case "دقيقه", "دقائق", "دقايق": return .minutes(Int(quantity))
        case "دقيقتين": return .minutes(2)
        case "يوم", "ايام": return .days(max(1, Int(quantity)))
        case "يومين": return .days(2)
        case "اسبوع", "اسابيع": return .days(max(1, Int(quantity)) * 7)
        case "اسبوعين": return .days(14)
        default: return nil
        }
    }

    // MARK: - Day ("غداً", "بعد بكرة", "الخميس")

    private static let weekdays: [(names: [String], weekday: Int)] = [   // Calendar: 1 = Sunday
        (["الاحد"], 1),
        (["الاثنين", "الاتنين"], 2),
        (["الثلاثاء", "الثلاثا"], 3),
        (["الاربعاء", "الاربعا"], 4),
        (["الخميس"], 5),
        (["الجمعه"], 6),
        (["السبت"], 7),
    ]

    private static func dayOffset(in s: String, now: Date, calendar cal: Calendar) -> Int? {
        // Check "بعد غد" before "غد".
        if containsWord(["بعد غد", "بعد غدا", "بعد الغد", "بعد بكره", "بعد بكرا"], in: s) { return 2 }
        if containsWord(["غدا", "الغد", "غد", "بكره", "بكرا", "باكر"], in: s) { return 1 }
        if containsWord(["اليوم", "الليله"], in: s) { return 0 }
        if containsWord(["الاسبوع القادم", "الاسبوع الجاي", "الاسبوع الياي", "الاسبوع المقبل"], in: s) { return 7 }

        let today = cal.component(.weekday, from: now)
        for (names, weekday) in weekdays where containsWord(names, in: s) {
            let diff = (weekday - today + 7) % 7
            return diff == 0 ? 7 : diff   // Naming today's weekday means next week.
        }
        return nil
    }

    // MARK: - Time of day ("الساعة 5 مساءً", "الساعة عشرة الا ربع", "17:30")

    private struct TimeOfDay {
        var hour: Int
        var minute: Int
        var extraDay: Int
    }

    private enum Period: CaseIterable {
        case afternoon, evening, night, noon, morning   // Checked in this order.

        var words: [String] {
            switch self {
            case .afternoon: ["بعد الظهر", "العصر", "عصرا", "عصر"]
            case .evening: ["المساء", "مساء", "مساءا", "المسا", "مسا", "المغرب", "مغربا"]
            case .night: ["الليل", "ليلا", "الليله", "بليل", "العشاء", "العشا"]
            case .noon: ["الظهر", "ظهرا", "الظهيره", "ظهر"]
            case .morning: ["الصباح", "صباحا", "صباح", "الصبح", "صبحا", "الفجر", "فجرا", "فجر"]
            }
        }

        /// Used when a period is spoken without an hour ("بكرة العصر").
        var defaultHour: Int {
            switch self {
            case .morning: 9
            case .noon: 12
            case .afternoon: 16
            case .evening: 19
            case .night: 21
            }
        }
    }

    private static let defaultHour = 9

    private static func timeOfDay(in s: String) -> TimeOfDay? {
        let period = Period.allCases.first { containsWord($0.words, in: s) }

        var hour: Int?
        var minute = 0

        let spokenTime = "الساعه\\s*(\(numberPattern))(?!\\p{L})"
            + "(?:\\s*[:.]\\s*(\\d{1,2}))?"
            + "(?:\\s*(الا|و)\\s*(النصف|نصف|نص|الربع|ربع|الثلث|ثلث|\\d{1,2})(?!\\p{L}))?"
        let clockTime = "(?<![\\d:])(\\d{1,2})\\s*:\\s*(\\d{2})(?![\\d:])"

        if let g = firstMatch(spokenTime, in: s), let token = g[1], let h = numberValue(token) {
            hour = h
            if let mm = g[2], let value = Int(mm) { minute = value }
            if let op = g[3], let fraction = g[4] {
                let value = fractionMinutes(fraction)
                if op == "الا" {            // "خمسة الا ربع" → 4:45
                    minute = (60 - value) % 60
                    hour = h <= 1 ? 12 : h - 1
                } else {                    // "خمسة ونص" → 5:30
                    minute = value
                }
            }
        } else if let g = firstMatch(clockTime, in: s),
                  let h = g[1].flatMap({ Int($0) }),
                  let m = g[2].flatMap({ Int($0) }) {
            hour = h
            minute = m
        }

        guard var h = hour else {
            return period.map { TimeOfDay(hour: $0.defaultHour, minute: 0, extraDay: 0) }
        }

        // Spoken Arabic uses the 12-hour clock; turn it into 24-hour time.
        var extraDay = 0
        if h <= 12 {
            switch period {
            case .morning?:
                if h == 12 { h = 0 }
            case .noon?:
                if h < 7 { h += 12 }                  // "الساعة 1 ظهراً" → 13:00
            case .afternoon?, .evening?:
                if h < 12 { h += 12 }
            case .night?:
                if h == 12 { h = 0; extraDay = 1 }    // Midnight → start of the next day.
                else if h <= 4 { extraDay = 1 }       // "2 بالليل" → 02:00 the next day.
                else { h += 12 }
            case nil:
                // No period given: people rarely schedule 1–6 AM, so assume PM.
                if (1...6).contains(h) { h += 12 }
            }
        }

        guard (0...23).contains(h), (0...59).contains(minute) else { return nil }
        return TimeOfDay(hour: h, minute: minute, extraDay: extraDay)
    }

    private static func fractionMinutes(_ token: String) -> Int {
        switch token {
        case "نص", "نصف", "النصف": 30
        case "ربع", "الربع": 15
        case "ثلث", "الثلث": 20
        default: Int(token) ?? 0
        }
    }

    // MARK: - Numbers

    /// Cardinal (MSA + dialect) and ordinal hour words, in normalized form.
    private static let numberWords: [String: Int] = [
        "واحد": 1, "واحده": 1, "الواحده": 1,
        "اثنين": 2, "اثنتين": 2, "ثنتين": 2, "اتنين": 2, "الثانيه": 2,
        "ثلاث": 3, "ثلاثه": 3, "تلاته": 3, "الثالثه": 3,
        "اربع": 4, "اربعه": 4, "الرابعه": 4,
        "خمس": 5, "خمسه": 5, "الخامسه": 5,
        "ست": 6, "سته": 6, "السادسه": 6,
        "سبع": 7, "سبعه": 7, "السابعه": 7,
        "ثمان": 8, "ثماني": 8, "ثمانيه": 8, "تمانيه": 8, "الثامنه": 8,
        "تسع": 9, "تسعه": 9, "التاسعه": 9,
        "عشر": 10, "عشره": 10, "العاشره": 10,
        "احدي عشر": 11, "احد عشر": 11, "حداش": 11, "حدعش": 11,
        "الحاديه عشر": 11, "الحاديه عشره": 11,
        "اثني عشر": 12, "اثنا عشر": 12, "اطنعش": 12, "ثنعش": 12,
        "الثانيه عشر": 12, "الثانيه عشره": 12,
    ]

    /// Longest words first, so "الثانيه عشر" wins over "الثانيه".
    private static let numberPattern: String = {
        let words = numberWords.keys
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
        return (["\\d{1,2}"] + words).joined(separator: "|")
    }()

    private static func numberValue(_ token: String) -> Int? {
        Int(token) ?? numberWords[token]
    }

    // MARK: - Helpers

    private static var calendar: Calendar {
        // Always Gregorian. ar-SA devices often default to the Umm al-Qura calendar.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.locale = Locale(identifier: "ar")
        return cal
    }

    private static func isArabic(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage == .arabic
    }

    /// Whole-word match that also allows an attached و / ب / ف prefix ("وبكرة", "بالليل").
    private static func containsWord(_ words: [String], in s: String) -> Bool {
        let alternatives = words
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return firstMatch("(?<!\\p{L})[وبف]?(?:\(alternatives))(?!\\p{L})", in: s) != nil
    }

    /// Capture groups of the first match; unmatched groups are `nil`.
    private static func firstMatch(_ pattern: String, in s: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let match = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }
}
