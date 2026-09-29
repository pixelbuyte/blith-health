import Foundation
import Testing
@testable import BlithCore

@Suite("Calendar math")
struct CalendarMathTests {
    @Test func dayNumberRoundTrips() {
        for n in stride(from: -1000, through: 30000, by: 37) {
            #expect(LocalDate(dayNumber: n).dayNumber == n)
        }
        #expect(LocalDate(year: 1970, month: 1, day: 1).dayNumber == 0)
        #expect(LocalDate(year: 2024, month: 3, day: 1).adding(days: -1) == LocalDate(year: 2024, month: 2, day: 29))
        #expect(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1) == LocalDate(year: 2027, month: 1, day: 1))
    }

    @Test func weekdayMatchesFoundation() {
        let cal = T.calendar
        for offset in 0..<400 {
            let d = T.today.adding(days: -offset)
            #expect(d.weekday == cal.component(.weekday, from: d.startDate(in: cal)))
        }
        #expect(T.today.weekday == 3) // Tuesday
    }

    @Test func dstDayBoundaries() {
        let cal = T.calendar
        // US DST ended 2026-11-01 (25-hour day) and began 2026-03-08 (23-hour day).
        let fallBack = LocalDate(year: 2026, month: 11, day: 1)
        #expect(fallBack.endDate(in: cal).timeIntervalSince(fallBack.startDate(in: cal)) == 25 * 3600)
        let springForward = LocalDate(year: 2026, month: 3, day: 8)
        #expect(springForward.endDate(in: cal).timeIntervalSince(springForward.startDate(in: cal)) == 23 * 3600)
        // 11:30 PM local is still the same local day, not the next UTC day.
        let late = springForward.startDate(in: cal).addingTimeInterval(22.5 * 3600)
        #expect(LocalDate(late, calendar: cal) == springForward)
    }

    @Test func startOfWeekRespectsFirstWeekday() {
        #expect(T.today.startOfWeek(firstWeekday: 2) == LocalDate(year: 2026, month: 9, day: 28)) // Monday
        #expect(T.today.startOfWeek(firstWeekday: 1) == LocalDate(year: 2026, month: 9, day: 27)) // Sunday
    }

    @Test func codableUsesISODates() throws {
        let data = try JSONEncoder().encode(["d": T.today])
        #expect(String(decoding: data, as: UTF8.self) == #"{"d":"2026-09-29"}"#)
        let dict: [LocalDate: Int] = [T.today: 1]
        let back = try JSONDecoder().decode([LocalDate: Int].self, from: JSONEncoder().encode(dict))
        #expect(back == dict)
    }
}

@Suite("Statistics")
struct StatsTests {
    @Test func basics() {
        #expect(Stats.mean([]) == nil)
        #expect(Stats.mean([2, 4, 6]) == 4)
        #expect(Stats.median([5, 1, 3]) == 3)
        #expect(Stats.median([4, 1, 3, 2]) == 2.5)
        #expect(Stats.percentChange(from: 0, to: 10) == nil)
        #expect(abs(Stats.percentChange(from: 6810, to: 7410)! - 0.0881) < 0.0001)
        #expect(Stats.slope(x: [0, 1, 2, 3], y: [1, 3, 5, 7]) == 2)
        #expect(abs(Stats.pearson([1, 2, 3, 4], [2, 4, 6, 8])! - 1) < 1e-9)
        #expect(abs(Stats.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9])! - 2.138) < 0.001)
    }

    @Test func formatting() {
        #expect(Fmt.int(7420.4) == "7,420")
        #expect(Fmt.signedPercent(0.18) == "+18%")
        #expect(Fmt.signedPercent(-0.08) == "\u{2212}8%")
        #expect(Fmt.duration(7 * 3600 + 42 * 60) == "7h 42m")
        #expect(Fmt.weight(80, units: .imperial) == "176.4 lb")
        #expect(Fmt.weightChange(-0.95, units: .metric) == "\u{2212}0.9 kg" || Fmt.weightChange(-0.95, units: .metric) == "\u{2212}1.0 kg")
        #expect(Fmt.hour(0) == "12 AM")
        #expect(Fmt.hour(16) == "4 PM")
    }
}

@Suite("Step analytics")
struct StepAnalyticsTests {
    @Test func rollingAverageExcludesTodayAndMissingDays() {
        var steps = T.constant(7000, days: 1...7)
        steps[3] = nil // missing day is not a zero
        steps[0] = 100 // today, partial
        let a = HealthAnalytics(T.ctx(T.history(steps: steps)))
        let avg = a.rollingAverage(.steps, days: 7)!
        #expect(avg.value == 7000)
        #expect(avg.days == 6)
    }

    @Test func baselineNeedsEnoughHistory() {
        let few = HealthAnalytics(T.ctx(T.history(steps: T.constant(6000, days: 1...5))))
        #expect(few.baseline(.steps, window: 28) == nil)
        let enough = HealthAnalytics(T.ctx(T.history(steps: T.constant(6000, days: 1...10))))
        let b = enough.baseline(.steps, window: 28)!
        #expect(b.mean == 6000 && b.observations == 10)
    }

    @Test func weekPeriodComparesWithPreviousSevenDays() {
        var steps = T.constant(8000, days: 0...6)
        for d in 7...13 { steps[d] = 6400 }
        let p = HealthAnalytics(T.ctx(T.history(steps: steps))).periodSummary(.steps, period: .week)
        #expect(p.buckets.count == 7)
        #expect(p.dailyAverage == 8000) // today (8000) excluded but same value
        #expect(p.previousDailyAverage == 6400)
        #expect(abs(p.change! - 0.25) < 1e-9)
        #expect(p.total == 56000)
        #expect(p.span.dayCount == 7)
    }

    @Test func weeklyBucketsAverageDaysWithData() {
        var steps: [Int: Double] = [:]
        for d in 1...181 { steps[d] = d % 2 == 0 ? 6000 : 8000 }
        let p = HealthAnalytics(T.ctx(T.history(steps: steps))).periodSummary(.steps, period: .sixMonths)
        #expect(p.bucketUnit == .week)
        let full = p.buckets.filter { $0.dayCount == 7 && !$0.isPartial }
        for b in full { #expect(b.value! >= 6000 && b.value! <= 8000) }
        #expect(p.buckets.first!.start <= p.span.start)
    }

    @Test func todayPaceUsesSameWeekdayAtSameTime() {
        // Past Tuesdays: 12,000 evenly spread 8 AM–8 PM → 7,500 by 3:30 PM.
        var steps: [Int: Double] = [:]
        for w in 1...6 { steps[7 * w] = 12000 }
        steps[0] = 9000
        var h = T.history(steps: steps, hourlyShape: true)
        // Today: 9,000 so far, all before 3 PM.
        var todayValues = Array(repeating: 0.0, count: 24)
        for hr in 8..<15 { todayValues[hr] = 9000 / 7 }
        h.hourlySteps[T.today] = HourlyBuckets(values: todayValues)
        let pace = HealthAnalytics(T.ctx(h)).todayPace()!
        #expect(pace.basis == .sameWeekday)
        #expect(pace.observations == 6)
        #expect(abs(pace.usualByNow! - 7500) < 1)
        #expect(abs(pace.change! - 0.2) < 0.001)
        #expect(pace.usualFullDay == 12000)
    }

    @Test func todayPaceFallsBackToRecentDays() {
        var steps = T.constant(6000, days: 1...5)
        steps[0] = 3000
        let pace = HealthAnalytics(T.ctx(T.history(steps: steps, hourlyShape: true))).todayPace()!
        #expect(pace.basis == .recentDays)
        #expect(pace.observations == 5)
    }

    @Test func personalBestAndBestWeek() {
        var steps = T.constant(5000, days: 1...60)
        steps[12] = 15000
        for d in 15...21 { steps[d] = 9000 } // a big week, Mon 2026-09-07 … Sun 2026-09-13? (days 16..22 ago span a week)
        let a = HealthAnalytics(T.ctx(T.history(steps: steps)))
        let best = a.personalBest(.steps, in: T.ctx(T.history(steps: steps)).trailing(60))!
        #expect(best.value == 15000 && best.date == T.today.adding(days: -12))
        let week = a.bestWeek(.steps, in: DateSpan(T.today.adding(days: -60), T.today))!
        #expect(week.start.weekday == 2)
        #expect(week.average > 5000)
    }

    @Test func consistencyWeekStates() {
        var steps = T.constant(6000, days: 1...28)
        steps[1] = 2000 // Monday of this week, below 85% of median
        steps[0] = 7000 // today already above threshold
        let c = HealthAnalytics(T.ctx(T.history(steps: steps))).weekConsistency()!
        #expect(c.threshold == 5100)
        #expect(c.days.count == 7)
        #expect(c.days[0].state == .notMet)
        #expect(c.days[1].state == .met)
        #expect(c.days[2].state == .future)
        #expect(c.metCount == 1)
    }

    @Test func goalOverridesBaselineThreshold() {
        let a = HealthAnalytics(T.ctx(T.history(steps: T.constant(6000, days: 1...28)), profile: UserProfile(dailyStepGoal: 8000)))
        #expect(a.activeThreshold() == 8000)
    }
}

@Suite("Weight")
struct WeightTests {
    func samples(_ values: [(Int, Double)]) -> [HealthSample] {
        values.map { ago, v in
            let t = T.date(T.today.adding(days: -ago), hour: 7)
            return HealthSample(id: "w\(ago)", metric: .weight, value: v, start: t, end: t, source: T.source, syncedAt: t)
        }
    }

    @Test func smoothingFiltersDailySwings() {
        // Alternating ±1 kg around 80 → trend stays near 80.
        let s = samples((0..<40).map { (40 - $0, $0 % 2 == 0 ? 81 : 79) })
        let pts = WeightAnalytics.smoothed(s)
        #expect(abs(pts.last!.trend - 80) < 0.3)
    }

    @Test func trendDetectsSustainedDecline() {
        var h = HealthHistory(origin: .appleHealth)
        h.weights = samples((0...60).map { ago in (ago, 80 + Double(ago) * 0.05) }) // losing 0.35 kg/week
        let t = WeightAnalytics.trend(T.ctx(h, profile: UserProfile(goalWeightKg: 75)))!
        #expect(t.direction == .down)
        #expect(t.change30Days! < -1.0 && t.change30Days! > -1.8)
        #expect(t.weeklyRate! < -0.2)
        #expect(abs(t.distanceToGoal! - (t.trendNow - 75)) < 1e-9)
        #expect(!t.isStale)
    }

    @Test func flatNoisyWeightIsStable() {
        var h = HealthHistory(origin: .appleHealth)
        h.weights = samples((0...40).map { ago in (ago, ago % 3 == 0 ? 80.8 : 79.6) })
        #expect(WeightAnalytics.trend(T.ctx(h))!.direction == .stable)
    }

    @Test func staleWhenNoRecentReadings() {
        var h = HealthHistory(origin: .appleHealth)
        h.weights = samples([(90, 80), (80, 80), (70, 80)])
        #expect(WeightAnalytics.trend(T.ctx(h))!.isStale)
        #expect(InsightEngine(T.ctx(h)).weightTrend() == nil)
    }
}
