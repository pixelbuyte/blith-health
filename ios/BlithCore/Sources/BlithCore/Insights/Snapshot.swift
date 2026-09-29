import Foundation

/// Walk DNA: plain-language observations about how this person walks. Every sentence is
/// backed by a calculation and a stated window; nothing is scored.
public enum WalkPatterns {
    public static func observations(_ ctx: AnalyticsContext) -> [PatternObservation] {
        let a = HealthAnalytics(ctx)
        var out: [PatternObservation] = []

        if let tod = a.timeOfDayProfile(in: ctx.trailing(28)) {
            out.append(PatternObservation(
                id: "peak", symbol: "clock",
                text: "Most of your movement happens between \(Fmt.hour(tod.peakWindowStart)) and \(Fmt.hour(tod.peakWindowStart + 4)).",
                detail: "\(Fmt.percent(tod.peakWindowShare)) of your steps over the last 4 weeks (\(tod.days) days)."))
        }
        let p = a.weekdayPattern()
        if let b = p.busiest, let m = p.medians[b - 1] {
            out.append(PatternObservation(
                id: "weekday", symbol: "calendar",
                text: "\(Fmt.weekdayNames[b - 1]) is usually your busiest day.",
                detail: "Typical \(Fmt.weekdayNames[b - 1]): \(Fmt.int(m)) steps, over the last 12 weeks."))
        }
        if let wd = p.weekdayMean, let we = p.weekendMean, let change = Stats.percentChange(from: wd, to: we), abs(change) >= 0.1 {
            out.append(PatternObservation(
                id: "weekend", symbol: change > 0 ? "sun.max" : "briefcase",
                text: change > 0 ? "You move more on weekends than weekdays." : "Your weekdays are more active than your weekends.",
                detail: "Weekends \(Fmt.int(we)) vs weekdays \(Fmt.int(wd)) steps a day (\(Fmt.signedPercent(change)))."))
        }
        // Fewer-but-longer walks: walking workouts, last 8 weeks vs the 8 weeks before.
        let now = ctx.now
        let recentWalks = ctx.history.workouts.filter { $0.isWalking && $0.start >= now.addingTimeInterval(-56 * 86_400) }
        let earlierWalks = ctx.history.workouts.filter {
            $0.isWalking && $0.start < now.addingTimeInterval(-56 * 86_400) && $0.start >= now.addingTimeInterval(-112 * 86_400)
        }
        if recentWalks.count >= 4, earlierWalks.count >= 4,
           let rd = Stats.mean(recentWalks.map(\.duration)), let ed = Stats.mean(earlierWalks.map(\.duration)),
           let dChange = Stats.percentChange(from: ed, to: rd), abs(dChange) >= 0.15 {
            let fewer = recentWalks.count < earlierWalks.count
            let text = dChange > 0
                ? (fewer ? "You take fewer but longer walks than two months ago." : "Your walks have gotten longer lately.")
                : "Your recorded walks are shorter than two months ago."
            out.append(PatternObservation(
                id: "walks", symbol: "figure.walk",
                text: text,
                detail: "\(recentWalks.count) walks averaging \(Fmt.duration(rd)) in the last 8 weeks vs \(earlierWalks.count) averaging \(Fmt.duration(ed)) before."))
        }
        // Weekday consistency: share of weekdays near usual, last 4 weeks vs the 4 before.
        if let t = a.activeThreshold() {
            func weekdayRate(_ span: DateSpan) -> (Double, Int)? {
                let vals = ctx.history.values(.steps, in: span).filter { !$0.key.isWeekend }.map(\.value)
                guard vals.count >= 10 else { return nil }
                return (Double(vals.filter { $0 >= t }.count) / Double(vals.count), vals.count)
            }
            if let recent = weekdayRate(ctx.trailing(28)), let before = weekdayRate(ctx.trailing(28, endingDaysAgo: 29)),
               recent.0 - before.0 >= 0.15 {
                out.append(PatternObservation(
                    id: "weekday-consistency", symbol: "chart.bar.fill",
                    text: "Your weekday consistency has improved.",
                    detail: "\(Fmt.percent(recent.0)) of weekdays near your usual in the last 4 weeks, up from \(Fmt.percent(before.0))."))
            }
        }
        if let pace = InsightEngine(ctx).pace() {
            out.append(PatternObservation(id: "speed", symbol: "speedometer", text: pace.headline + ".", detail: pace.explanation))
        }
        return out
    }
}

/// One-line status at the top of Today, generated from calculations.
public enum TodayHeadline {
    public static func make(_ ctx: AnalyticsContext, pace: TodayPace?, feed: [Insight]) -> String {
        let a = HealthAnalytics(ctx)
        let stepDays = ctx.history.values(.steps, in: ctx.trailing(28)).count
        if stepDays < 5 {
            return stepDays == 0 && ctx.history.value(.steps, on: ctx.today) == nil
                ? "Once steps arrive, we'll start learning your normal."
                : "We're still learning your normal. A few more days will sharpen this."
        }
        let weekday = Fmt.weekdayNames[ctx.today.weekday - 1]
        if let pace, let change = pace.change, ctx.hourNow >= 10, pace.observations >= 3 {
            let comparison = pace.basis == .sameWeekday ? "your usual \(weekday)" : "your usual day"
            if change >= 0.1 { return "Your movement is running ahead of \(comparison)." }
            if change <= -0.15 { return "Today's a bit quieter than \(comparison) so far." }
            if abs(change) < 0.1 { return "You're right around \(comparison) so far." }
        }
        if let c = feed.first(where: { $0.kind == .consistency }), (c.currentValue ?? 0) >= 5 {
            return "You've been more consistent this week than usual."
        }
        if let cur = a.rollingAverage(.steps, days: 7), cur.days >= 5,
           let base = a.average(.steps, in: ctx.trailing(28, endingDaysAgo: 8)),
           let change = Stats.percentChange(from: base.value, to: cur.value) {
            if change >= 0.08 { return "This week is running \(Fmt.percent(change)) above your recent normal." }
            if change <= -0.08 { return "This week has been quieter than your recent normal." }
            return "Your week is tracking close to your normal."
        }
        return ctx.hourNow < 10 ? "Early in the day. Here's how your week is shaping up." : "Here's what stands out today."
    }
}

/// Everything the three tabs render, computed once per sync/refresh off the main thread.
public struct HealthSnapshot: Sendable {
    public var ctx: AnalyticsContext
    public var headline: String
    public var pace: TodayPace?
    public var todaySteps: Double?
    public var todayDistance: Double?
    public var todayExercise: Double?
    public var todayEnergy: Double?
    public var average7: AverageResult?
    public var average30: AverageResult?
    public var average90: AverageResult?
    public var feed: [Insight]
    public var allInsights: [Insight]
    public var consistency: WeekConsistency?
    public var weight: WeightTrend?
    public var sleep: SleepSummary
    public var periods: [WalkPeriod: PeriodSummary]
    public var weekdayPattern: WeekdayPattern
    public var timeOfDay: TimeOfDayProfile?
    public var patterns: [PatternObservation]
    public var walkingSpeed: PeriodSummary
    public var availability: [HealthMetric: MetricAvailability]

    public static func build(history: HealthHistory, profile: UserProfile, now: Date, calendar: Calendar) -> HealthSnapshot {
        let ctx = AnalyticsContext(history: history, profile: profile, now: now, calendar: calendar)
        let a = HealthAnalytics(ctx)
        let engine = InsightEngine(ctx)
        let all = engine.allInsights()
        var feed: [Insight] = []
        var families = Set<String>()
        for i in all where i.score >= 0.3 && !families.contains(i.kind.family) {
            families.insert(i.kind.family)
            feed.append(i)
            if feed.count == 4 { break }
        }
        let pace = a.todayPace()
        var periods: [WalkPeriod: PeriodSummary] = [:]
        for p in WalkPeriod.allCases { periods[p] = a.periodSummary(.steps, period: p) }
        var availability: [HealthMetric: MetricAvailability] = [:]
        for m in HealthMetric.allCases { availability[m] = history.availability(m, today: ctx.today, calendar: calendar) }
        return HealthSnapshot(
            ctx: ctx,
            headline: TodayHeadline.make(ctx, pace: pace, feed: feed),
            pace: pace,
            todaySteps: history.value(.steps, on: ctx.today),
            todayDistance: history.value(.distanceWalkingRunning, on: ctx.today),
            todayExercise: history.value(.exerciseMinutes, on: ctx.today),
            todayEnergy: history.value(.activeEnergy, on: ctx.today),
            average7: a.rollingAverage(.steps, days: 7),
            average30: a.rollingAverage(.steps, days: 30),
            average90: a.rollingAverage(.steps, days: 90),
            feed: feed, allInsights: all,
            consistency: a.weekConsistency(),
            weight: WeightAnalytics.trend(ctx),
            sleep: SleepAnalytics.summary(ctx),
            periods: periods,
            weekdayPattern: a.weekdayPattern(),
            timeOfDay: a.timeOfDayProfile(in: ctx.trailing(28)),
            patterns: WalkPatterns.observations(ctx),
            walkingSpeed: a.periodSummary(.walkingSpeed, period: .sixMonths),
            availability: availability
        )
    }

    public func insight(id: String) -> Insight? { allInsights.first { $0.id == id } }
}
