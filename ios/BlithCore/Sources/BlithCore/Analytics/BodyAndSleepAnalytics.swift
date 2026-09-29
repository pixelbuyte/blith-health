import Foundation

public struct WeightPoint: Sendable, Hashable, Codable, Identifiable {
    public var date: Date
    public var value: Double
    public var trend: Double
    public var id: Date { date }
}

public struct WeightTrend: Sendable, Hashable {
    public enum Direction: String, Sendable { case down, up, stable }

    public var points: [WeightPoint]
    public var latest: WeightPoint
    /// Smoothed trend now (exponentially weighted, 7-day time constant).
    public var trendNow: Double
    public var trend30DaysAgo: Double?
    public var change30Days: Double?
    public var trendAtStart: Double
    public var startDate: Date
    public var changeSinceStart: Double
    /// Trend change per week over the last 28 days.
    public var weeklyRate: Double?
    public var direction: Direction
    public var readingsLast7Days: Int
    public var rangeLast7Days: ClosedRange<Double>?
    public var trendChangeLast7Days: Double?
    public var goalKg: Double?
    public var distanceToGoal: Double?
    public var isStale: Bool
    public var sampleCount: Int
}

public struct SleepSummary: Sendable, Hashable {
    public var lastNight: SleepNight?
    public var lastNightAsleep: Double?
    public var average7: Double?
    public var average28: Double?
    public var nights28: Int
    /// Last night minus the 28-night average (seconds).
    public var differenceFromAverage: Double?
    /// Standard deviation of bedtimes over 28 nights, in minutes.
    public var bedtimeVariabilityMinutes: Double?
    public var stagePercentages: [SleepStage: Double]
}

public enum WeightAnalytics {
    /// Time constant of the smoothing (days). Daily water swings are mostly filtered out,
    /// while a real trend shows within a week or two.
    public static let tauDays = 7.0

    public static func smoothed(_ samples: [HealthSample]) -> [WeightPoint] {
        // One reading per timestamp; average readings on the same day first.
        let sorted = samples.sorted { $0.start < $1.start }
        var points: [WeightPoint] = []
        var trend: Double?
        var lastDate: Date?
        for s in sorted {
            if let t = trend, let ld = lastDate {
                let dtDays = max(0, s.start.timeIntervalSince(ld) / 86_400)
                let alpha = 1 - exp(-max(dtDays, 0.25) / tauDays)
                trend = t + alpha * (s.value - t)
            } else {
                trend = s.value
            }
            lastDate = s.start
            points.append(WeightPoint(date: s.start, value: s.value, trend: trend!))
        }
        return points
    }

    public static func trend(_ ctx: AnalyticsContext) -> WeightTrend? {
        let points = smoothed(ctx.history.weights)
        guard let latest = points.last, let first = points.first else { return nil }
        let now = ctx.now
        func trendAt(_ date: Date) -> Double? { points.last { $0.date <= date }?.trend }
        let thirtyAgo = now.addingTimeInterval(-30 * 86_400)
        let trend30 = first.date <= thirtyAgo ? trendAt(thirtyAgo) : nil
        let recent28 = points.filter { $0.date >= now.addingTimeInterval(-28 * 86_400) }
        let weeklyRate: Double? = recent28.count >= 4 ? Stats.slope(
            x: recent28.map { $0.date.timeIntervalSince(now) / (7 * 86_400) }, y: recent28.map(\.trend)) : nil
        let last7 = points.filter { $0.date >= now.addingTimeInterval(-7 * 86_400) }
        let range = last7.isEmpty ? nil : (last7.map(\.value).min()!...last7.map(\.value).max()!)
        let trend7 = trendAt(now.addingTimeInterval(-7 * 86_400))
        let change30 = trend30.map { latest.trend - $0 }
        let direction: WeightTrend.Direction
        if let c = change30 ?? weeklyRate.map({ $0 * 4 }) {
            direction = c <= -0.3 ? .down : (c >= 0.3 ? .up : .stable)
        } else {
            direction = .stable
        }
        let goal = ctx.profile.goalWeightKg
        return WeightTrend(
            points: points, latest: latest, trendNow: latest.trend,
            trend30DaysAgo: trend30, change30Days: change30,
            trendAtStart: first.trend, startDate: first.date, changeSinceStart: latest.trend - first.trend,
            weeklyRate: weeklyRate, direction: direction,
            readingsLast7Days: last7.count, rangeLast7Days: range,
            trendChangeLast7Days: trend7.map { latest.trend - $0 },
            goalKg: goal, distanceToGoal: goal.map { latest.trend - $0 },
            isStale: now.timeIntervalSince(latest.date) > Double(HealthMetric.weight.staleAfterDays) * 86_400,
            sampleCount: points.count
        )
    }
}

public enum SleepAnalytics {
    public static func summary(_ ctx: AnalyticsContext) -> SleepSummary {
        let h = ctx.history
        let today = ctx.today
        let lastNight = h.sleepNights[today] ?? h.sleepNights[ctx.yesterday]
        let nights28 = LocalDate.range(today.adding(days: -28), today).compactMap { h.sleepNights[$0] }
        let nights7 = LocalDate.range(today.adding(days: -7), today).compactMap { h.sleepNights[$0] }
        let avg28 = Stats.mean(nights28.map(\.asleepDuration))
        let avg7 = Stats.mean(nights7.map(\.asleepDuration))
        let bedtimes: [Double] = nights28.compactMap { n in
            guard let s = n.start else { return nil }
            // Minutes relative to midnight, continuous across it (11 PM = -60).
            let c = ctx.calendar.dateComponents([.hour, .minute], from: s)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if m > 12 * 60 { m -= 24 * 60 }
            return m
        }
        var stages: [SleepStage: Double] = [:]
        if let n = lastNight, n.hasStages, n.asleepDuration > 0 {
            for st in [SleepStage.core, .deep, .rem] { stages[st] = n.duration(of: st) / n.asleepDuration }
        }
        return SleepSummary(
            lastNight: lastNight, lastNightAsleep: lastNight?.asleepDuration,
            average7: avg7, average28: avg28, nights28: nights28.count,
            differenceFromAverage: {
                guard let l = lastNight?.asleepDuration, nights28.count >= 5 else { return nil }
                let others = nights28.filter { $0.date != lastNight?.date }.map(\.asleepDuration)
                return Stats.mean(others).map { l - $0 }
            }(),
            bedtimeVariabilityMinutes: bedtimes.count >= 5 ? Stats.standardDeviation(bedtimes) : nil,
            stagePercentages: stages
        )
    }
}
