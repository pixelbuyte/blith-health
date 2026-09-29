import Foundation

/// Everything the analytics layer needs: history + who the user is + what time it is.
/// `now` and `calendar` are injected and used everywhere, so results are reproducible.
public struct AnalyticsContext: Sendable {
    public let history: HealthHistory
    public let profile: UserProfile
    public let now: Date
    public let calendar: Calendar

    public init(history: HealthHistory, profile: UserProfile, now: Date, calendar: Calendar) {
        self.history = history
        self.profile = profile
        self.now = now
        self.calendar = calendar
    }

    public var today: LocalDate { LocalDate(now, calendar: calendar) }
    public var yesterday: LocalDate { today.adding(days: -1) }

    /// Fractional hour of the day, e.g. 14.5 at 2:30 PM.
    public var hourNow: Double {
        Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60
    }

    public var units: UnitSystem { profile.units }

    /// Complete days ending yesterday.
    public func trailing(_ days: Int, endingDaysAgo offset: Int = 1) -> DateSpan {
        let end = today.adding(days: -offset)
        return DateSpan(end.adding(days: -(days - 1)), end)
    }

    public func sourceLabel(_ metric: HealthMetric) -> String {
        if history.origin.isDemo { return "Sample data" }
        let names = (history.sources[metric] ?? []).sorted { $0.value > $1.value }.map(\.source.name)
        if names.isEmpty { return history.origin.providerKind.displayName }
        return "Apple Health (" + names.prefix(3).joined(separator: ", ") + ")"
    }
}

public struct AverageResult: Sendable, Hashable {
    public var value: Double
    public var days: Int
    public var span: DateSpan
}

public struct PersonalBaseline: Sendable, Hashable {
    public var metric: HealthMetric
    public var span: DateSpan
    public var mean: Double
    public var median: Double
    public var observations: Int
}

public struct TodayPace: Sendable, Hashable {
    public enum Basis: String, Sendable, Hashable { case sameWeekday, recentDays }

    public var stepsSoFar: Double
    public var usualByNow: Double?
    public var usualFullDay: Double?
    public var basis: Basis
    public var weekday: Int
    public var observations: Int
    /// Change vs usual-by-now (0.14 = 14% ahead).
    public var change: Double?
    /// Cumulative steps at the end of each hour so far today.
    public var todayCurve: [Double]
    /// Median cumulative steps at the end of each hour on comparable days (24 values).
    public var usualCurve: [Double]
    public var hourNow: Double
}

public enum WalkPeriod: String, CaseIterable, Sendable, Codable, Identifiable {
    case day, week, month, sixMonths, year, all

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .day: "D"
        case .week: "W"
        case .month: "M"
        case .sixMonths: "6M"
        case .year: "Y"
        case .all: "All"
        }
    }

    public var title: String {
        switch self {
        case .day: "Today"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .sixMonths: "Last 6 months"
        case .year: "Last 12 months"
        case .all: "All time"
        }
    }

    public var dayCount: Int? {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .sixMonths: 182
        case .year: 365
        case .all: nil
        }
    }

    public var bucket: BucketUnit {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .sixMonths, .year: .week
        case .all: .month
        }
    }

    /// Parses "7d", "30d", "6m", "1y", "all", "today", "week", "month", "year".
    public init?(token: String) {
        switch token.lowercased() {
        case "day", "today", "1d": self = .day
        case "week", "7d", "w": self = .week
        case "month", "30d", "m", "28d": self = .month
        case "6m", "sixmonths", "180d", "182d", "90d", "3m": self = .sixMonths
        case "year", "1y", "y", "12m", "365d": self = .year
        case "all", "alltime": self = .all
        default: return nil
        }
    }
}

public enum BucketUnit: String, Sendable, Codable { case hour, day, week, month }

public struct ChartBucket: Sendable, Hashable, Codable, Identifiable {
    public var start: LocalDate
    /// Hour of day for hourly buckets.
    public var hour: Int?
    /// Total for hours/days; average per day with data for weeks/months.
    public var value: Double?
    public var dayCount: Int
    public var isPartial: Bool
    public var id: String { "\(start)-\(hour ?? -1)" }

    public init(start: LocalDate, hour: Int? = nil, value: Double?, dayCount: Int, isPartial: Bool) {
        self.start = start
        self.hour = hour
        self.value = value
        self.dayCount = dayCount
        self.isPartial = isPartial
    }
}

public struct PeriodSummary: Sendable, Hashable {
    public var metric: HealthMetric
    public var period: WalkPeriod
    public var span: DateSpan
    public var bucketUnit: BucketUnit
    public var buckets: [ChartBucket]
    /// Includes today so far.
    public var total: Double
    /// Mean over complete days with data (today excluded because it isn't over yet).
    public var dailyAverage: Double?
    public var daysWithData: Int
    public var previousSpan: DateSpan
    public var previousDailyAverage: Double?
    public var change: Double?
    public var highest: DayValue?
    public var lowest: DayValue?
    public var median: Double?
    public var variability: Double?
    public var activeDays: Int
    public var activeThreshold: Double?
    public var weekdayAverage: Double?
    public var weekendAverage: Double?
    /// Hourly view: usual cumulative curve for today's weekday.
    public var usualHourly: [Double]?
}

public struct DayValue: Sendable, Hashable, Codable {
    public var date: LocalDate
    public var value: Double
    public init(date: LocalDate, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct WeekdayPattern: Sendable, Hashable {
    /// Median by weekday (index 0 = Sunday); nil when fewer than 3 observations.
    public var medians: [Double?]
    public var observations: [Int]
    public var span: DateSpan
    public var busiest: Int?
    public var quietest: Int?
    public var weekdayMean: Double?
    public var weekendMean: Double?
}

public struct TimeOfDayProfile: Sendable, Hashable {
    /// Share of steps per hour (sums to 1).
    public var shares: [Double]
    public var days: Int
    public var span: DateSpan
    /// Start hour of the 4-hour window with the most movement.
    public var peakWindowStart: Int
    public var peakWindowShare: Double
    /// Share of steps before 4 PM.
    public var shareBefore4PM: Double
}

public struct WeekConsistency: Sendable, Hashable {
    public enum DayState: String, Sendable, Hashable { case met, notMet, noData, future, inProgress }
    public struct Day: Sendable, Hashable, Identifiable {
        public var date: LocalDate
        public var state: DayState
        public var value: Double?
        public var id: LocalDate { date }
    }

    public var days: [Day]
    public var metCount: Int
    public var threshold: Double
    public var thresholdIsGoal: Bool
}

/// Deterministic analytics over `HealthHistory`.
public struct HealthAnalytics: Sendable {
    public let ctx: AnalyticsContext

    public init(_ ctx: AnalyticsContext) { self.ctx = ctx }

    var history: HealthHistory { ctx.history }

    // MARK: Averages and baselines

    public func average(_ metric: HealthMetric, in span: DateSpan) -> AverageResult? {
        let vals = Array(history.values(metric, in: span).values)
        guard let m = Stats.mean(vals) else { return nil }
        return AverageResult(value: m, days: vals.count, span: span)
    }

    /// Mean of the last `days` complete days (today excluded).
    public func rollingAverage(_ metric: HealthMetric, days: Int) -> AverageResult? {
        average(metric, in: ctx.trailing(days))
    }

    /// The user's own normal over a trailing window of complete days. Requires at least
    /// a third of the window to have data.
    public func baseline(_ metric: HealthMetric, window: Int = 28, endingDaysAgo: Int = 1) -> PersonalBaseline? {
        let span = ctx.trailing(window, endingDaysAgo: endingDaysAgo)
        let vals = Array(history.values(metric, in: span).values)
        guard vals.count >= max(3, window / 3), let mean = Stats.mean(vals), let median = Stats.median(vals) else { return nil }
        return PersonalBaseline(metric: metric, span: span, mean: mean, median: median, observations: vals.count)
    }

    /// Median value on the same weekday over the last `weeks` weeks (complete days only).
    public func usual(_ metric: HealthMetric, weekday: Int, weeks: Int = 8) -> (median: Double, observations: Int)? {
        let span = ctx.trailing(weeks * 7)
        let vals = history.values(metric, in: span).filter { $0.key.weekday == weekday }.map(\.value)
        guard vals.count >= 3, let med = Stats.median(vals) else { return nil }
        return (med, vals.count)
    }

    /// Median steps on the same weekday in the 8 weeks before `date` (≥3 observations).
    public func usualBefore(_ date: LocalDate, metric: HealthMetric = .steps) -> (median: Double, observations: Int)? {
        let vals = (1...8).compactMap { history.value(metric, on: date.adding(days: -7 * $0)) }
        guard vals.count >= 3, let m = Stats.median(vals) else { return nil }
        return (m, vals.count)
    }

    // MARK: Today

    public func todayPace() -> TodayPace? {
        let today = ctx.today
        guard let todayBuckets = history.hourlySteps[today] ?? history.value(.steps, on: today).map({ total in
            // Without hourly data we only know the total; spread it into the current hour.
            var v = Array(repeating: 0.0, count: 24)
            v[min(23, Int(ctx.hourNow))] = total
            return HourlyBuckets(values: v)
        }) else { return nil }
        let hourNow = ctx.hourNow
        let soFar = history.value(.steps, on: today) ?? todayBuckets.total
        let todayCurve = Array(todayBuckets.cumulative.prefix(min(24, Int(hourNow) + 1)))

        func comparable(_ filter: (LocalDate) -> Bool, lookback: Int) -> [HourlyBuckets] {
            LocalDate.range(today.adding(days: -lookback), ctx.yesterday)
                .filter(filter)
                .compactMap { history.hourlySteps[$0] }
                .filter { $0.total > 0 }
        }

        var basis = TodayPace.Basis.sameWeekday
        var days = comparable({ $0.weekday == today.weekday }, lookback: 56)
        if days.count < 3 {
            basis = .recentDays
            days = comparable({ _ in true }, lookback: 28)
        }
        guard days.count >= 3 else {
            return TodayPace(stepsSoFar: soFar, usualByNow: nil, usualFullDay: nil, basis: basis, weekday: today.weekday,
                             observations: days.count, change: nil, todayCurve: todayCurve, usualCurve: [], hourNow: hourNow)
        }
        let byNow = Stats.median(days.map { $0.cumulative(atHour: hourNow) })
        let full = Stats.median(days.map(\.total))
        let curves = days.map(\.cumulative)
        let usualCurve = (0..<24).map { h in Stats.median(curves.map { $0[h] }) ?? 0 }
        let change = byNow.flatMap { $0 >= 200 ? Stats.percentChange(from: $0, to: soFar) : nil }
        return TodayPace(stepsSoFar: soFar, usualByNow: byNow, usualFullDay: full, basis: basis, weekday: today.weekday,
                         observations: days.count, change: change, todayCurve: todayCurve, usualCurve: usualCurve, hourNow: hourNow)
    }

    // MARK: Periods

    public func span(for period: WalkPeriod, metric: HealthMetric = .steps) -> DateSpan {
        if let n = period.dayCount { return DateSpan(ctx.today.adding(days: -(n - 1)), ctx.today) }
        let first = history.firstDate(metric, calendar: ctx.calendar) ?? ctx.today.adding(days: -29)
        return DateSpan(min(first, ctx.today.adding(days: -29)), ctx.today)
    }

    public func activeThreshold() -> Double? {
        if let goal = ctx.profile.dailyStepGoal, goal > 0 { return Double(goal) }
        guard let b = baseline(.steps, window: 28) else { return nil }
        return (b.median * 0.85 / 100).rounded() * 100
    }

    public func periodSummary(_ metric: HealthMetric = .steps, period: WalkPeriod) -> PeriodSummary {
        let span = span(for: period, metric: metric)
        let values = history.values(metric, in: span)
        let completeSpan = span.end == ctx.today && span.dayCount > 1 ? DateSpan(span.start, ctx.yesterday) : span
        let complete = values.filter { completeSpan.contains($0.key) }
        let isCumulative = metric.aggregation == .cumulative

        var buckets: [ChartBucket] = []
        var usualHourly: [Double]?
        switch period.bucket {
        case .hour:
            let hb = history.hourlySteps[ctx.today]
            let currentHour = Int(ctx.hourNow)
            buckets = (0..<24).map { h in
                ChartBucket(start: ctx.today, hour: h, value: h <= currentHour ? (hb?.values[h] ?? 0) : nil,
                            dayCount: 1, isPartial: h == currentHour)
            }
            usualHourly = todayPace()?.usualCurve
        case .day:
            buckets = span.days.map { d in ChartBucket(start: d, value: values[d], dayCount: 1, isPartial: d == ctx.today) }
        case .week:
            buckets = groupBuckets(span: span, values: values) { $0.startOfWeek(firstWeekday: ctx.profile.firstWeekday) }
        case .month:
            buckets = groupBuckets(span: span, values: values) { $0.startOfMonth }
        }

        let completeVals = Array(complete.values)
        let dailyAverage = period == .day ? values[ctx.today] : Stats.mean(completeVals)
        let previous = span.previous
        let previousVals = Array(history.values(metric, in: previous).values)
        let previousAverage = Stats.mean(previousVals)
        let change: Double? = {
            if period == .day { return todayPace()?.change }
            guard let a = dailyAverage, let b = previousAverage, previousVals.count >= max(2, previous.dayCount / 3) else { return nil }
            return Stats.percentChange(from: b, to: a)
        }()
        let sortedComplete = complete.sorted { $0.key < $1.key }
        let highest = sortedComplete.max { $0.value < $1.value }.map { DayValue(date: $0.key, value: $0.value) }
        let lowest = sortedComplete.min { $0.value < $1.value }.map { DayValue(date: $0.key, value: $0.value) }
        let threshold = metric == .steps ? activeThreshold() : nil
        let active = threshold.map { t in values.filter { $0.value >= t }.count } ?? 0
        let weekdayVals = complete.filter { !$0.key.isWeekend }.map(\.value)
        let weekendVals = complete.filter { $0.key.isWeekend }.map(\.value)

        return PeriodSummary(
            metric: metric, period: period, span: span, bucketUnit: period.bucket, buckets: buckets,
            total: isCumulative ? values.values.reduce(0, +) : (Stats.mean(Array(values.values)) ?? 0),
            dailyAverage: dailyAverage, daysWithData: values.count,
            previousSpan: previous, previousDailyAverage: period == .day ? todayPace()?.usualByNow : previousAverage,
            change: change, highest: highest, lowest: lowest,
            median: Stats.median(completeVals), variability: Stats.coefficientOfVariation(completeVals),
            activeDays: active, activeThreshold: threshold,
            weekdayAverage: Stats.mean(weekdayVals), weekendAverage: Stats.mean(weekendVals),
            usualHourly: usualHourly
        )
    }

    func groupBuckets(span: DateSpan, values: [LocalDate: Double], key: (LocalDate) -> LocalDate) -> [ChartBucket] {
        var groups: [LocalDate: [Double]] = [:]
        var dayCounts: [LocalDate: Int] = [:]
        for d in span.days {
            let k = key(d)
            dayCounts[k, default: 0] += 1
            if let v = values[d], d != ctx.today || span.dayCount == 1 { groups[k, default: []].append(v) }
        }
        return dayCounts.keys.sorted().map { k in
            let vals = groups[k] ?? []
            let lastDayOfBucket = span.days.last { key($0) == k } ?? k
            return ChartBucket(start: k, value: Stats.mean(vals), dayCount: dayCounts[k] ?? 0,
                               isPartial: lastDayOfBucket == ctx.today)
        }
    }

    // MARK: Patterns

    public func weekdayPattern(lookbackDays: Int = 84) -> WeekdayPattern {
        let span = ctx.trailing(lookbackDays)
        let vals = history.values(.steps, in: span)
        var medians: [Double?] = []
        var counts: [Int] = []
        for wd in 1...7 {
            let v = vals.filter { $0.key.weekday == wd }.map(\.value)
            counts.append(v.count)
            medians.append(v.count >= 3 ? Stats.median(v) : nil)
        }
        let indexed = medians.enumerated().compactMap { i, m in m.map { (i + 1, $0) } }
        return WeekdayPattern(
            medians: medians, observations: counts, span: span,
            busiest: indexed.count >= 5 ? indexed.max { $0.1 < $1.1 }?.0 : nil,
            quietest: indexed.count >= 5 ? indexed.min { $0.1 < $1.1 }?.0 : nil,
            weekdayMean: Stats.mean(vals.filter { !$0.key.isWeekend }.map(\.value)),
            weekendMean: Stats.mean(vals.filter { $0.key.isWeekend }.map(\.value))
        )
    }

    public func timeOfDayProfile(in span: DateSpan) -> TimeOfDayProfile? {
        let days = span.days.filter { $0 != ctx.today }.compactMap { history.hourlySteps[$0] }.filter { $0.total > 500 }
        guard days.count >= 3 else { return nil }
        var sums = Array(repeating: 0.0, count: 24)
        for d in days { for h in 0..<24 { sums[h] += d.values[h] } }
        let total = sums.reduce(0, +)
        guard total > 0 else { return nil }
        let shares = sums.map { $0 / total }
        var bestStart = 0, bestShare = 0.0
        for start in 5...20 {
            let s = shares[start..<min(24, start + 4)].reduce(0, +)
            if s > bestShare { bestShare = s; bestStart = start }
        }
        return TimeOfDayProfile(shares: shares, days: days.count, span: span, peakWindowStart: bestStart,
                                peakWindowShare: bestShare, shareBefore4PM: shares[0..<16].reduce(0, +))
    }

    public func weekConsistency() -> WeekConsistency? {
        guard let threshold = activeThreshold() else { return nil }
        let start = ctx.today.startOfWeek(firstWeekday: ctx.profile.firstWeekday)
        let days = (0..<7).map { i -> WeekConsistency.Day in
            let d = start.adding(days: i)
            let v = history.value(.steps, on: d)
            let state: WeekConsistency.DayState
            if d > ctx.today { state = .future }
            else if let v, v >= threshold { state = .met }
            else if d == ctx.today { state = .inProgress }
            else if v == nil { state = .noData }
            else { state = .notMet }
            return WeekConsistency.Day(date: d, state: state, value: v)
        }
        return WeekConsistency(days: days, metCount: days.filter { $0.state == .met }.count, threshold: threshold,
                               thresholdIsGoal: ctx.profile.dailyStepGoal != nil)
    }

    /// Weekly daily-average series for complete weeks, oldest first.
    public func weeklyAverages(_ metric: HealthMetric, weeks: Int) -> [(start: LocalDate, average: Double, days: Int)] {
        let thisWeek = ctx.today.startOfWeek(firstWeekday: ctx.profile.firstWeekday)
        return (1...weeks).reversed().compactMap { i in
            let s = thisWeek.adding(days: -7 * i)
            let vals = Array(history.values(metric, in: DateSpan(s, s.adding(days: 6))).values)
            guard vals.count >= 4, let m = Stats.mean(vals) else { return nil }
            return (s, m, vals.count)
        }
    }

    // MARK: Records & anomalies

    public func personalBest(_ metric: HealthMetric, in span: DateSpan, highest: Bool = true) -> DayValue? {
        let vals = history.values(metric, in: span).filter { $0.key != ctx.today }
        let best = highest ? vals.max { $0.value < $1.value } : vals.min { $0.value < $1.value }
        return best.map { DayValue(date: $0.key, value: $0.value) }
    }

    /// Week (by the user's first weekday) with the highest total, among complete weeks.
    public func bestWeek(_ metric: HealthMetric = .steps, in span: DateSpan) -> (start: LocalDate, total: Double, average: Double)? {
        let thisWeek = ctx.today.startOfWeek(firstWeekday: ctx.profile.firstWeekday)
        var best: (LocalDate, Double, Double)?
        var s = span.start.startOfWeek(firstWeekday: ctx.profile.firstWeekday)
        while s < thisWeek {
            let vals = Array(history.values(metric, in: DateSpan(s, s.adding(days: 6))).values)
            if vals.count >= 5 {
                let total = vals.reduce(0, +)
                if total > (best?.1 ?? -1) { best = (s, total, total / Double(vals.count)) }
            }
            s = s.adding(days: 7)
        }
        return best.map { (start: $0.0, total: $0.1, average: $0.2) }
    }

    public struct Anomaly: Sendable, Hashable {
        public var date: LocalDate
        public var value: Double
        public var baseline: Double
        public var zScore: Double
    }

    /// Days more than 2 standard deviations from the preceding 28-day window.
    public func anomalies(_ metric: HealthMetric, in span: DateSpan) -> [Anomaly] {
        span.days.filter { $0 != ctx.today }.compactMap { d in
            guard let v = history.value(metric, on: d) else { return nil }
            let window = Array(history.values(metric, in: DateSpan(d.adding(days: -28), d.adding(days: -1))).values)
            guard window.count >= 14, let m = Stats.mean(window), let sd = Stats.standardDeviation(window), sd > 0 else { return nil }
            let z = (v - m) / sd
            return abs(z) >= 2 ? Anomaly(date: d, value: v, baseline: m, zScore: z) : nil
        }
    }

    public struct Correlation: Sendable, Hashable {
        public var metricA: HealthMetric
        public var metricB: HealthMetric
        public var lagDays: Int
        public var coefficient: Double
        public var pairs: Int
        public var strength: String
    }

    /// Pearson correlation between A on day d and B on day d + lag.
    public func correlation(_ a: HealthMetric, _ b: HealthMetric, in span: DateSpan, lagDays: Int = 0) -> Correlation? {
        let va = history.values(a, in: span)
        let vb = history.values(b, in: DateSpan(span.start.adding(days: lagDays), span.end.adding(days: lagDays)))
        var xs: [Double] = [], ys: [Double] = []
        for (d, x) in va.sorted(by: { $0.key < $1.key }) where d.adding(days: lagDays) != ctx.today {
            if let y = vb[d.adding(days: lagDays)] { xs.append(x); ys.append(y) }
        }
        guard xs.count >= 10, let r = Stats.pearson(xs, ys) else { return nil }
        let strength: String
        switch abs(r) {
        case ..<0.1: strength = "none"
        case ..<0.3: strength = "weak"
        case ..<0.5: strength = "moderate"
        default: strength = "strong"
        }
        return Correlation(metricA: a, metricB: b, lagDays: lagDays, coefficient: r, pairs: xs.count, strength: strength)
    }
}
