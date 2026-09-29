import Foundation

/// A calendar day in the user's local time, independent of time zone and DST.
///
/// Health totals are bucketed by the day the user lived through, so every aggregate is keyed by
/// a `LocalDate` rather than a `Date`. Day arithmetic uses a day number (days since 1970-01-01,
/// proleptic Gregorian), so adding days never lands on the wrong date across DST changes.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: m <= 2 ? y + 1 : y, month: m, day: d)
    }

    public func adding(days: Int) -> LocalDate { LocalDate(dayNumber: dayNumber + days) }

    public func days(until other: LocalDate) -> Int { other.dayNumber - dayNumber }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday, …)`.
    public var weekday: Int {
        // 1970-01-01 was a Thursday (5).
        let w = (dayNumber % 7 + 7) % 7 // 0 = Thursday
        return (w + 4) % 7 + 1
    }

    public var isWeekend: Bool { weekday == 1 || weekday == 7 }

    /// Local midnight at the start of this day.
    public func startDate(in calendar: Calendar) -> Date {
        let comps = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: comps) ?? Date(timeIntervalSince1970: TimeInterval(dayNumber) * 86_400)
    }

    /// Local midnight at the start of the following day.
    public func endDate(in calendar: Calendar) -> Date { adding(days: 1).startDate(in: calendar) }

    /// First day of the week containing this date (`firstWeekday` 1 = Sunday, 2 = Monday).
    public func startOfWeek(firstWeekday: Int) -> LocalDate {
        let offset = (weekday - firstWeekday + 7) % 7
        return adding(days: -offset)
    }

    public var startOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1) }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool { lhs.dayNumber < rhs.dayNumber }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Inclusive sequence of days.
    public static func range(_ from: LocalDate, _ to: LocalDate) -> [LocalDate] {
        guard from <= to else { return [] }
        return (from.dayNumber...to.dayNumber).map(LocalDate.init(dayNumber:))
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDate(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid LocalDate \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension LocalDate: CodingKeyRepresentable {
    public var codingKey: CodingKey { DateKey(stringValue: description) }
    public init?<T: CodingKey>(codingKey: T) { self.init(string: codingKey.stringValue) }

    private struct DateKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// An inclusive span of local days.
public struct DateSpan: Hashable, Codable, Sendable {
    public var start: LocalDate
    public var end: LocalDate

    public init(_ start: LocalDate, _ end: LocalDate) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public var dayCount: Int { start.days(until: end) + 1 }
    public var days: [LocalDate] { LocalDate.range(start, end) }
    public func contains(_ date: LocalDate) -> Bool { date >= start && date <= end }

    /// The span of the same length immediately before this one.
    public var previous: DateSpan { DateSpan(start.adding(days: -dayCount), start.adding(days: -1)) }

    public func dateInterval(in calendar: Calendar) -> DateInterval {
        DateInterval(start: start.startDate(in: calendar), end: end.endDate(in: calendar))
    }
}
