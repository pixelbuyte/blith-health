import Foundation
@testable import BlithCore

enum T {
    static let tz = TimeZone(identifier: "America/New_York")!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.firstWeekday = 2
        return c
    }

    /// Tuesday 2026-09-29, 3:30 PM New York.
    static let today = LocalDate(year: 2026, month: 9, day: 29)
    static var now: Date { date(today, hour: 15.5) }

    static func date(_ d: LocalDate, hour: Double) -> Date {
        d.startDate(in: calendar).addingTimeInterval(hour * 3600)
    }

    static let source = SourceRef(provider: .appleHealth, name: "iPhone", identifier: "com.apple.health.test", device: "iPhone")

    /// History with the given daily step values keyed by days-ago (0 = today).
    static func history(steps: [Int: Double], hourlyShape: Bool = false) -> HealthHistory {
        var h = HealthHistory(origin: .appleHealth)
        h.requestedCategories = Set(HealthCategory.allCases)
        var series: [LocalDate: DailyAggregate] = [:]
        for (ago, v) in steps {
            let d = today.adding(days: -ago)
            series[d] = DailyAggregate(date: d, metric: .steps, value: v)
            if hourlyShape {
                // Even spread 8 AM – 8 PM.
                var values = Array(repeating: 0.0, count: 24)
                for hr in 8..<20 { values[hr] = v / 12 }
                h.hourlySteps[d] = HourlyBuckets(values: values)
            }
        }
        h.daily[.steps] = series
        return h
    }

    static func ctx(_ h: HealthHistory, profile: UserProfile = UserProfile(), now: Date = T.now) -> AnalyticsContext {
        AnalyticsContext(history: h, profile: profile, now: now, calendar: calendar)
    }

    static func constant(_ value: Double, days: ClosedRange<Int>) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: days.map { ($0, value) })
    }
}
