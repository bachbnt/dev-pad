// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  TimestampEngine.swift
//  DevPad
//
//  Unix epoch ↔ calendar date. Accepts a bare number (unit auto-detected
//  from its magnitude unless the caller pins one) or a date string (ISO 8601
//  with an offset, or a handful of common zone-less layouts that are read in
//  a caller-chosen time zone). Only the supported range 0001–9999 is
//  accepted so formatters never see a date they can't print. Dates are
//  `Double` seconds underneath, so nanosecond inputs lose sub-microsecond
//  precision.
//

import Foundation

enum TimestampUnit: String, CaseIterable, Identifiable {
    case seconds, milliseconds, microseconds, nanoseconds
    var id: String { rawValue }

    /// Units per second.
    var perSecond: Double {
        switch self {
        case .seconds:      return 1
        case .milliseconds: return 1_000
        case .microseconds: return 1_000_000
        case .nanoseconds:  return 1_000_000_000
        }
    }
}

enum TimestampError: LocalizedError {
    case empty
    case unrecognized
    case outOfRange

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Input is empty"
        case .unrecognized:
            return "Not a Unix timestamp or a recognized date format"
        case .outOfRange:
            return "Value is outside the supported range (years 0001–9999)"
        }
    }
}

struct TimestampResult {
    let date: Date
    /// Unit the number was read in. `nil` when the input was a date string.
    let unit: TimestampUnit?
}

enum TimestampEngine {

    // Year 0001-01-01 and 9999-12-31 23:59:59 UTC as Unix seconds.
    private static let minSeconds: Double = -62_135_596_800
    private static let maxSeconds: Double = 253_402_300_799

    // MARK: - Parsing

    /// - Parameters:
    ///   - unit: Pin the unit of a numeric input. `nil` auto-detects it.
    ///   - zoneLessTimeZone: Zone used for date strings that carry no offset.
    static func parse(_ input: String,
                      unit: TimestampUnit? = nil,
                      zoneLessTimeZone: TimeZone = .current) throws -> TimestampResult {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TimestampError.empty }

        if isNumeric(text), let value = Double(text) {
            let resolved = unit ?? detectUnit(value)
            let seconds = value / resolved.perSecond
            guard seconds.isFinite, seconds >= minSeconds, seconds <= maxSeconds else {
                throw TimestampError.outOfRange
            }
            return TimestampResult(date: Date(timeIntervalSince1970: seconds), unit: resolved)
        }

        guard let date = parseDateString(text, timeZone: zoneLessTimeZone) else {
            throw TimestampError.unrecognized
        }
        let seconds = date.timeIntervalSince1970
        guard seconds >= minSeconds, seconds <= maxSeconds else { throw TimestampError.outOfRange }
        return TimestampResult(date: date, unit: nil)
    }

    /// Magnitude heuristic. A *millisecond* value before March 1973 (< 1e11)
    /// is indistinguishable from seconds, which is why callers can pin a unit.
    static func detectUnit(_ value: Double) -> TimestampUnit {
        let m = abs(value)
        if m < 1e11 { return .seconds }
        if m < 1e14 { return .milliseconds }
        if m < 1e17 { return .microseconds }
        return .nanoseconds
    }

    private static func isNumeric(_ s: String) -> Bool {
        var seenDigit = false
        var seenDot = false
        for (i, ch) in s.enumerated() {
            if ch.isASCII, ch.isNumber {
                seenDigit = true
            } else if ch == "-" && i == 0 {
                continue
            } else if ch == "." && !seenDot {
                seenDot = true
            } else {
                return false
            }
        }
        return seenDigit
    }

    // MARK: - Date strings

    private static let zoneLessFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss.SSS",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd"
    ]

    private static func parseDateString(_ text: String, timeZone: TimeZone) -> Date? {
        // ISO 8601 with an explicit offset wins: the zone is in the string.
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ] {
            let f = ISO8601DateFormatter()
            f.formatOptions = options
            if let d = f.date(from: text) { return d }
        }

        // RFC 2822, as seen in HTTP `Date` / email headers.
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let d = rfc.date(from: text) { return d }

        for format in zoneLessFormats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = format
            // DateFormatter happily accepts trailing garbage as a prefix
            // match on some layouts; require the round-trip to consume
            // the whole string by checking the formatted length.
            if let d = f.date(from: text), f.string(from: d).count == text.count {
                return d
            }
        }
        return nil
    }

    // MARK: - Formatting

    static func epochSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down))
    }

    static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// ISO 8601 with offset (`Z` for UTC). Milliseconds are printed only when
    /// the date actually has a sub-second part.
    static func iso8601(_ date: Date, timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        let hasFraction = epochMilliseconds(date) % 1000 != 0
        f.formatOptions = hasFraction
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return f.string(from: date)
    }

    static func readable(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateStyle = .full
        f.timeStyle = .long
        return f.string(from: date)
    }

    static func relative(_ date: Date, to now: Date = Date(), locale: Locale) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }
}
