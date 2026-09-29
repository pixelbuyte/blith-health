import Foundation

/// Runs deterministic detectors over the user's history, then filters and ranks the results
/// so only a few meaningful observations reach the screen.
///
/// Every detector requires enough data, a meaningful magnitude and states its comparison
/// windows explicitly. Relationships between metrics always carry a causation caveat.
public struct InsightEngine: Sendable {
    public let ctx: AnalyticsContext
    let a: HealthAnalytics

    public static let relationshipCaveat = "This is a pattern in your data, not proof that one caused the other."

    public init(_ ctx: AnalyticsContext) {
        self.ctx = ctx
        self.a = HealthAnalytics(ctx)
    }

    /// All eligible insights, highest score first.
    public func allInsights() -> [Insight] {
        let detectors: [() -> Insight?] = [
            baselineChange, consistency, momentum, dayOfWeek, weekdayDecline, timing, personalBest,
            longTermChange, pace, weightTrend, weightActivity, rebound, sleepMovement, sleepTiming, noteContext,
        ]
        return detectors.compactMap { $0() }.sorted { $0.score > $1.score }
    }

    /// The ranked feed for Today: at most `limit`, one per family, above the quality bar.
    public func feed(limit: Int = 4) -> [Insight] {
        var families = Set<String>()
        var out: [Insight] = []
        for i in allInsights() where i.score >= 0.3 {
            guard !families.contains(i.kind.family) else { continue }
            families.insert(i.kind.family)
            out.append(i)
            if out.count == limit { break }
        }
        return out
    }

    // MARK: Helpers

    var units: UnitSystem { ctx.units }
    var goals: Set<UserGoal> { ctx.profile.goals }

    func goalBoost(_ relevant: Set<UserGoal>) -> Double { goals.isDisjoint(with: relevant) ? 0 : 0.15 }

    func confidence(coverage: Double, observations: Int, minimum: Int) -> InsightConfidence {
        if coverage >= 0.85 && observations >= minimum * 2 { return .high }
        if coverage >= 0.6 && observations >= minimum { return .moderate }
        return .low
    }

    func coverageText(_ n: Int, of total: Int) -> String { "\(n) of \(total) days" }

    func spanText(_ s: DateSpan) -> String { "\(Fmt.shortDate(s.start)) – \(Fmt.shortDate(s.end))" }

    func id(_ kind: InsightKind, _ suffix: String = "") -> String { "\(kind.rawValue)-\(ctx.today)\(suffix.isEmpty ? "" : "-" + suffix)" }

    // MARK: Detectors

    /// Last 7 days vs the 28 days before them.
    func baselineChange() -> Insight? {
        let current = ctx.trailing(7)
        let baseline = ctx.trailing(28, endingDaysAgo: 8)
        guard let cur = a.average(.steps, in: current), cur.days >= 5,
              let base = a.average(.steps, in: baseline), base.days >= 14,
              let change = Stats.percentChange(from: base.value, to: cur.value), abs(change) >= 0.08 else { return nil }
        let up = change > 0
        let coverage = Double(cur.days + base.days) / 35
        return Insight(
            id: id(.baselineChange), kind: .baselineChange,
            headline: up ? "You're walking more than usual" : "Your walking has been quieter lately",
            explanation: "You've averaged \(Fmt.int(cur.value)) steps a day over the last 7 days, about \(Fmt.percent(change)) \(up ? "above" : "below") your previous 4-week average of \(Fmt.int(base.value)).",
            metric: .steps, currentValue: cur.value, comparisonValue: base.value, change: change,
            currentRange: current, comparisonRange: baseline,
            confidence: confidence(coverage: coverage, observations: cur.days + base.days, minimum: 14),
            sampleCount: cur.days + base.days, source: ctx.sourceLabel(.steps),
            evidence: [
                EvidenceRow("Last 7 days", "\(Fmt.int(cur.value)) / day"),
                EvidenceRow("Previous 4 weeks", "\(Fmt.int(base.value)) / day"),
                EvidenceRow("Difference", Fmt.signedPercent(change)),
                EvidenceRow("Compared", "\(spanText(current)) vs \(spanText(baseline))"),
                EvidenceRow("Days with data", "\(coverageText(cur.days, of: 7)) · \(coverageText(base.days, of: 28))"),
            ],
            emphasis: Fmt.signedPercent(change), emphasisCaption: "vs your 4-week baseline",
            score: min(1, abs(change) / 0.3) * 0.7 + 0.15 + goalBoost([.walkMore, .consistency, .buildStamina]),
            createdAt: ctx.now, link: .walk(.week)
        ).with(points: [EvidencePoint("Previous 4 wks", base.value), EvidencePoint("Last 7 days", cur.value, highlighted: true)])
    }

    /// Days at/above the user's threshold: last 7 days vs the prior 4 weeks' weekly rate.
    func consistency() -> Insight? {
        guard let threshold = a.activeThreshold() else { return nil }
        let current = ctx.trailing(7)
        let prior = ctx.trailing(28, endingDaysAgo: 8)
        let cur = ctx.history.values(.steps, in: current)
        let pri = ctx.history.values(.steps, in: prior)
        guard cur.count >= 6, pri.count >= 21 else { return nil }
        let hits = cur.values.filter { $0 >= threshold }.count
        let priorRate = Double(pri.values.filter { $0 >= threshold }.count) / Double(pri.count) * 7
        let thresholdText = "\(Fmt.int(threshold)) steps"
        let basis = ctx.profile.dailyStepGoal != nil ? "your goal of \(thresholdText)" : thresholdText

        // Most consistent week in N weeks?
        let weekHits: [Int] = (0..<12).map { w in
            let s = DateSpan(ctx.today.adding(days: -7 * (w + 1)), ctx.today.adding(days: -7 * w - 1))
            return ctx.history.values(.steps, in: s).values.filter { $0 >= threshold }.count
        }
        // How many preceding weeks in a row had fewer such days than the last 7.
        var bestInWeeks = 0
        for w in 1..<weekHits.count {
            if weekHits[w] < weekHits[0] { bestInWeeks = w } else { break }
        }

        let improved = Double(hits) - priorRate >= 1.5 && hits >= 4
        let dropped = priorRate - Double(hits) >= 2 && priorRate >= 3
        guard improved || dropped else { return nil }
        let headline: String
        if improved && bestInWeeks >= 5 {
            headline = "Your most consistent walking week in \(bestInWeeks + 1) weeks"
        } else if improved {
            headline = "You've been more consistent this week"
        } else {
            headline = "Fewer days near your usual this week"
        }
        let explanation = "You've passed \(basis) on \(hits) of the last 7 days. Over the 4 weeks before, that happened about \(Fmt.decimal(priorRate, digits: 0)) days a week."
        return Insight(
            id: id(.consistency), kind: .consistency, headline: headline, explanation: explanation,
            metric: .steps, currentValue: Double(hits), comparisonValue: priorRate,
            currentRange: current, comparisonRange: prior,
            confidence: confidence(coverage: Double(cur.count + pri.count) / 35, observations: cur.count + pri.count, minimum: 14),
            sampleCount: cur.count + pri.count, source: ctx.sourceLabel(.steps),
            evidence: [
                EvidenceRow("Threshold", ctx.profile.dailyStepGoal != nil ? "Your goal: \(thresholdText)" : "\(thresholdText) (85% of your typical day)"),
                EvidenceRow("Last 7 days", "\(hits) of 7 days"),
                EvidenceRow("Previous 4 weeks", "\(Fmt.decimal(priorRate)) days per week"),
                EvidenceRow("Compared", "\(spanText(current)) vs \(spanText(prior))"),
            ],
            emphasis: "\(hits)/7", emphasisCaption: "days near your usual",
            score: min(1, abs(Double(hits) - priorRate) / 4) * 0.6 + (bestInWeeks >= 5 ? 0.2 : 0.1) + goalBoost([.consistency, .walkMore]),
            createdAt: ctx.now, link: .walk(.week)
        ).with(points: current.days.map { d in EvidencePoint(Fmt.weekdayShort[d.weekday - 1], cur[d] ?? 0, highlighted: (cur[d] ?? 0) >= threshold) })
    }

    /// Weekly averages rising (or falling) for 3+ consecutive complete weeks.
    func momentum() -> Insight? {
        let weeks = a.weeklyAverages(.steps, weeks: 6)
        guard weeks.count >= 4 else { return nil }
        var ups = 0, downs = 0
        for i in stride(from: weeks.count - 1, to: 0, by: -1) {
            let d = weeks[i].average - weeks[i - 1].average
            if d > 0 && downs == 0 { ups += 1 } else if d < 0 && ups == 0 { downs += 1 } else { break }
        }
        let run = max(ups, downs)
        guard run >= 3 else { return nil }
        let startWeek = weeks[weeks.count - 1 - run]
        let endWeek = weeks[weeks.count - 1]
        guard let change = Stats.percentChange(from: startWeek.average, to: endWeek.average), abs(change) >= 0.08 else { return nil }
        let up = ups > 0
        return Insight(
            id: id(.momentum), kind: .momentum,
            headline: up ? "Your walking has climbed \(run) weeks in a row" : "Your walking has eased \(run) weeks in a row",
            explanation: "Your weekly average went from \(Fmt.int(startWeek.average)) steps a day (week of \(Fmt.shortDate(startWeek.start))) to \(Fmt.int(endWeek.average)) last week.",
            metric: .steps, currentValue: endWeek.average, comparisonValue: startWeek.average, change: change,
            currentRange: DateSpan(endWeek.start, endWeek.start.adding(days: 6)),
            comparisonRange: DateSpan(startWeek.start, startWeek.start.adding(days: 6)),
            confidence: run >= 4 ? .high : .moderate, sampleCount: weeks.suffix(run + 1).reduce(0) { $0 + $1.days },
            source: ctx.sourceLabel(.steps),
            evidence: weeks.suffix(run + 1).map { EvidenceRow("Week of \(Fmt.shortDate($0.start))", "\(Fmt.int($0.average)) / day") }
                + [EvidenceRow("Change", Fmt.signedPercent(change))],
            emphasis: Fmt.signedPercent(change), emphasisCaption: "over \(run) weeks",
            score: min(1, abs(change) / 0.3) * 0.5 + 0.1 * Double(run - 2) + 0.2 + goalBoost([.walkMore, .buildStamina]),
            createdAt: ctx.now, link: .walk(.sixMonths)
        ).with(points: weeks.suffix(run + 1).enumerated().map { i, w in
            EvidencePoint(Fmt.shortDate(w.start), w.average, highlighted: i == run)
        })
    }

    func dayOfWeek() -> Insight? {
        let p = a.weekdayPattern(lookbackDays: 84)
        guard let busiest = p.busiest, let top = p.medians[busiest - 1] else { return nil }
        let others = p.medians.enumerated().compactMap { $0.offset + 1 == busiest ? nil : $0.element }
        guard others.count >= 4, let rest = Stats.mean(others), let change = Stats.percentChange(from: rest, to: top), change >= 0.15 else { return nil }
        let name = Fmt.weekdayNames[busiest - 1]
        return Insight(
            id: id(.dayOfWeek), kind: .dayOfWeek,
            headline: "\(name) is usually your most active day",
            explanation: "Over the last 12 weeks your typical \(name) is \(Fmt.int(top)) steps, about \(Fmt.percent(change)) more than your other days.",
            metric: .steps, currentValue: top, comparisonValue: rest, change: change,
            currentRange: p.span, confidence: p.observations[busiest - 1] >= 8 ? .high : .moderate,
            sampleCount: p.observations.reduce(0, +), source: ctx.sourceLabel(.steps),
            evidence: (1...7).compactMap { wd in p.medians[wd - 1].map { EvidenceRow("Typical \(Fmt.weekdayNames[wd - 1])", Fmt.int($0)) } },
            emphasis: Fmt.weekdayShort[busiest - 1], emphasisCaption: "busiest day",
            score: 0.32, createdAt: ctx.now, link: .walk(.month)
        ).with(points: (1...7).compactMap { wd in p.medians[wd - 1].map { EvidencePoint(Fmt.weekdayShort[wd - 1], $0, highlighted: wd == busiest) } })
    }

    /// The same weekday falling four occurrences in a row.
    func weekdayDecline() -> Insight? {
        var best: Insight?
        for wd in 1...7 {
            let dates = (0..<5).map { i -> LocalDate in
                var d = ctx.yesterday
                while d.weekday != wd { d = d.adding(days: -1) }
                return d.adding(days: -7 * i)
            }.reversed()
            let vals = dates.compactMap { d in ctx.history.value(.steps, on: d).map { (d, $0) } }
            guard vals.count == 4 || vals.count == 5 else { continue }
            let last4 = Array(vals.suffix(4))
            let falling = zip(last4, last4.dropFirst()).allSatisfy { $1.1 < $0.1 }
            guard falling, let change = Stats.percentChange(from: last4[0].1, to: last4[3].1), change <= -0.25 else { continue }
            let name = Fmt.weekdayNames[wd - 1]
            let insight = Insight(
                id: id(.weekdayDecline, String(wd)), kind: .weekdayDecline,
                headline: "Your \(name)s have gotten quieter four weeks running",
                explanation: "Each of your last four \(name)s had fewer steps than the one before, from \(Fmt.int(last4[0].1)) to \(Fmt.int(last4[3].1)).",
                metric: .steps, currentValue: last4[3].1, comparisonValue: last4[0].1, change: change,
                currentRange: DateSpan(last4[0].0, last4[3].0), confidence: .moderate, sampleCount: 4,
                source: ctx.sourceLabel(.steps),
                evidence: last4.map { EvidenceRow(Fmt.dayLabel($0.0), Fmt.int($0.1)) },
                emphasis: Fmt.signedPercent(change), emphasisCaption: "over 4 \(name)s",
                score: 0.3 + min(0.3, abs(change) / 2), createdAt: ctx.now, link: .walk(.month)
            ).with(points: last4.enumerated().map { EvidencePoint(Fmt.shortDate($0.element.0), $0.element.1, highlighted: $0.offset == 3) })
            if (best?.score ?? 0) < insight.score { best = insight }
        }
        return best
    }

    /// Share of steps before 4 PM: last 7 days vs the prior 4 weeks.
    func timing() -> Insight? {
        guard let recent = a.timeOfDayProfile(in: ctx.trailing(7)), recent.days >= 5,
              let usual = a.timeOfDayProfile(in: ctx.trailing(28, endingDaysAgo: 8)), usual.days >= 14 else { return nil }
        let diff = recent.shareBefore4PM - usual.shareBefore4PM
        guard abs(diff) >= 0.12 else { return nil }
        let later = diff < 0
        return Insight(
            id: id(.timing), kind: .timing,
            headline: later ? "You've been walking later than usual" : "You've been walking earlier than usual",
            explanation: "You normally get about \(Fmt.percent(usual.shareBefore4PM)) of your steps before 4 PM. Over the last 7 days it's been \(Fmt.percent(recent.shareBefore4PM)).",
            metric: .steps, currentValue: recent.shareBefore4PM, comparisonValue: usual.shareBefore4PM, change: diff,
            currentRange: recent.span, comparisonRange: usual.span,
            confidence: confidence(coverage: Double(recent.days + usual.days) / 35, observations: recent.days + usual.days, minimum: 14),
            sampleCount: recent.days + usual.days, source: ctx.sourceLabel(.steps),
            evidence: [
                EvidenceRow("Before 4 PM, last 7 days", Fmt.percent(recent.shareBefore4PM)),
                EvidenceRow("Before 4 PM, previous 4 weeks", Fmt.percent(usual.shareBefore4PM)),
                EvidenceRow("Busiest window lately", "\(Fmt.hour(recent.peakWindowStart)) – \(Fmt.hour(recent.peakWindowStart + 4))"),
                EvidenceRow("Usual busiest window", "\(Fmt.hour(usual.peakWindowStart)) – \(Fmt.hour(usual.peakWindowStart + 4))"),
            ],
            emphasis: Fmt.percent(recent.shareBefore4PM), emphasisCaption: "of steps before 4 PM (usually \(Fmt.percent(usual.shareBefore4PM)))",
            score: min(1, abs(diff) / 0.3) * 0.5 + 0.15, createdAt: ctx.now, link: .walk(.day)
        )
    }

    func personalBest() -> Insight? {
        // Best complete week vs as many prior weeks as we have (min 8, max 26).
        let thisWeek = ctx.today.startOfWeek(firstWeekday: ctx.profile.firstWeekday)
        let lastWeek = thisWeek.adding(days: -7)
        let firstData = ctx.history.firstDate(.steps, calendar: ctx.calendar) ?? ctx.today
        let weeksAvailable = min(26, firstData.days(until: lastWeek) / 7)
        if weeksAvailable >= 8,
           let best = a.bestWeek(.steps, in: DateSpan(lastWeek.adding(days: -7 * weeksAvailable), lastWeek.adding(days: 6))),
           best.start == lastWeek {
            let label = weeksAvailable >= 26 ? "6 months" : "\(weeksAvailable + 1) weeks"
            return Insight(
                id: id(.personalBest, "week"), kind: .personalBest,
                headline: "Last week was your most active in \(label)",
                explanation: "You walked \(Fmt.int(best.total)) steps (\(Fmt.int(best.average)) a day), more than any week since \(Fmt.shortDate(lastWeek.adding(days: -7 * weeksAvailable))).",
                metric: .steps, currentValue: best.total, currentRange: DateSpan(lastWeek, lastWeek.adding(days: 6)),
                comparisonRange: DateSpan(lastWeek.adding(days: -7 * weeksAvailable), lastWeek.adding(days: -1)),
                confidence: .high, sampleCount: weeksAvailable * 7, source: ctx.sourceLabel(.steps),
                evidence: [
                    EvidenceRow("Week", spanText(DateSpan(lastWeek, lastWeek.adding(days: 6)))),
                    EvidenceRow("Total", "\(Fmt.int(best.total)) steps"),
                    EvidenceRow("Weeks compared", "\(weeksAvailable + 1)"),
                ],
                emphasis: Fmt.int(best.total), emphasisCaption: "steps last week",
                score: 0.55 + min(0.25, Double(weeksAvailable) / 100) + goalBoost([.walkMore]),
                createdAt: ctx.now, link: .walk(.sixMonths)
            )
        }
        // Yesterday as the biggest day in 90 days.
        let window = ctx.trailing(90)
        if let best = a.personalBest(.steps, in: window), best.date == ctx.yesterday,
           ctx.history.values(.steps, in: window).count >= 45 {
            return Insight(
                id: id(.personalBest, "day"), kind: .personalBest,
                headline: "Yesterday was your biggest day in 3 months",
                explanation: "You took \(Fmt.int(best.value)) steps yesterday, the most of any day since \(Fmt.shortDate(window.start)).",
                metric: .steps, currentValue: best.value, currentRange: DateSpan(best.date, best.date), comparisonRange: window,
                confidence: .high, sampleCount: ctx.history.values(.steps, in: window).count, source: ctx.sourceLabel(.steps),
                evidence: [EvidenceRow("Yesterday", "\(Fmt.int(best.value)) steps"), EvidenceRow("Compared with", spanText(window))],
                emphasis: Fmt.int(best.value), emphasisCaption: "steps yesterday",
                score: 0.5 + goalBoost([.walkMore, .buildStamina]), createdAt: ctx.now, link: .walk(.month)
            )
        }
        return nil
    }

    /// Last 30 days vs the 30 days ending three months ago.
    func longTermChange() -> Insight? {
        let recent = ctx.trailing(30)
        let earlier = ctx.trailing(30, endingDaysAgo: 91)
        guard let r = a.average(.steps, in: recent), r.days >= 20,
              let e = a.average(.steps, in: earlier), e.days >= 20,
              let change = Stats.percentChange(from: e.value, to: r.value), abs(change) >= 0.1 else { return nil }
        let month = Fmt.monthNames[earlier.end.month - 1]
        let up = change > 0
        return Insight(
            id: id(.longTermChange), kind: .longTermChange,
            headline: up ? "You're walking more than you were in \(month)" : "You're walking less than you were in \(month)",
            explanation: "Your 30-day step average has \(up ? "increased" : "decreased") from \(Fmt.int(e.value)) to \(Fmt.int(r.value)) since \(month).",
            metric: .steps, currentValue: r.value, comparisonValue: e.value, change: change,
            currentRange: recent, comparisonRange: earlier,
            confidence: confidence(coverage: Double(r.days + e.days) / 60, observations: r.days + e.days, minimum: 30),
            sampleCount: r.days + e.days, source: ctx.sourceLabel(.steps),
            evidence: [
                EvidenceRow("Last 30 days", "\(Fmt.int(r.value)) / day"),
                EvidenceRow("30 days ending \(Fmt.shortDate(earlier.end))", "\(Fmt.int(e.value)) / day"),
                EvidenceRow("Change", Fmt.signedPercent(change)),
            ],
            emphasis: Fmt.signedPercent(change), emphasisCaption: "30-day average since \(month)",
            score: min(1, abs(change) / 0.35) * 0.6 + 0.1 + goalBoost([.walkMore, .buildStamina, .understandHealth]),
            createdAt: ctx.now, link: .walk(.sixMonths)
        ).with(points: [EvidencePoint(month, e.value), EvidencePoint("Last 30 days", r.value, highlighted: true)])
    }

    func pace() -> Insight? {
        let weeks = a.weeklyAverages(.walkingSpeed, weeks: 8)
        guard weeks.count >= 5, let first = weeks.first, let last = weeks.last,
              let slope = Stats.slope(x: weeks.indices.map(Double.init), y: weeks.map(\.average)) else { return nil }
        let fitted = slope * Double(weeks.count - 1)
        guard let change = Stats.percentChange(from: first.average, to: first.average + fitted), abs(change) >= 0.03 else { return nil }
        let up = change > 0
        return Insight(
            id: id(.pace), kind: .pace,
            headline: up ? "Your walking speed has been picking up" : "Your walking speed has eased off",
            explanation: "Your average walking speed has gradually \(up ? "increased" : "decreased") over the last \(weeks.count) weeks, from about \(Fmt.speed(first.average, units: units)) to \(Fmt.speed(last.average, units: units)).",
            metric: .walkingSpeed, currentValue: last.average, comparisonValue: first.average, change: change,
            currentRange: DateSpan(first.start, last.start.adding(days: 6)),
            confidence: weeks.count >= 7 ? .high : .moderate, sampleCount: weeks.reduce(0) { $0 + $1.days },
            source: ctx.sourceLabel(.walkingSpeed),
            evidence: weeks.map { EvidenceRow("Week of \(Fmt.shortDate($0.start))", Fmt.speed($0.average, units: units)) }
                + [EvidenceRow("Trend over period", Fmt.signedPercent(change))],
            emphasis: Fmt.signedPercent(change), emphasisCaption: "walking speed, \(weeks.count) weeks",
            score: min(1, abs(change) / 0.1) * 0.45 + 0.1 + goalBoost([.buildStamina, .understandHealth]),
            createdAt: ctx.now, link: .walk(.sixMonths)
        )
    }

    func weightTrend() -> Insight? {
        guard let t = WeightAnalytics.trend(ctx), !t.isStale, let change = t.change30Days, abs(change) >= 0.4,
              t.sampleCount >= 8 else { return nil }
        let down = change < 0
        var explanation = "Your smoothed weight trend is \(down ? "down" : "up") \(Fmt.weight(abs(change), units: units)) over 30 days."
        if let r = t.rangeLast7Days, t.readingsLast7Days >= 3, let c7 = t.trendChangeLast7Days {
            explanation += " This week's readings ranged \(Fmt.weight(r.lowerBound, units: units))–\(Fmt.weight(r.upperBound, units: units)), while the trend moved \(Fmt.weightChange(c7, units: units))."
        }
        if let d = t.distanceToGoal, abs(d) >= 0.2 { explanation += " About \(Fmt.weight(abs(d), units: units)) from your goal." }
        var evidence = [
            EvidenceRow("Trend now", Fmt.weight(t.trendNow, units: units)),
            EvidenceRow("Trend 30 days ago", t.trend30DaysAgo.map { Fmt.weight($0, units: units) } ?? "—"),
            EvidenceRow("Latest reading", Fmt.weight(t.latest.value, units: units)),
            EvidenceRow("Readings in the last 7 days", "\(t.readingsLast7Days)"),
            EvidenceRow("Method", "Exponential smoothing, 7-day time constant"),
        ]
        if let g = t.goalKg { evidence.append(EvidenceRow("Goal", Fmt.weight(g, units: units))) }
        return Insight(
            id: id(.weightTrend), kind: .weightTrend,
            headline: down ? "Your weight trend is heading down" : "Your weight trend is heading up",
            explanation: explanation, metric: .weight, currentValue: t.trendNow, comparisonValue: t.trend30DaysAgo,
            change: change / max(1, t.trend30DaysAgo ?? t.trendNow),
            currentRange: DateSpan(ctx.today.adding(days: -30), ctx.today),
            confidence: t.sampleCount >= 20 ? .high : .moderate, sampleCount: t.sampleCount, source: ctx.sourceLabel(.weight),
            evidence: evidence,
            emphasis: Fmt.weightChange(change, units: units), emphasisCaption: "trend over 30 days",
            score: min(1, abs(change) / 2) * 0.5 + 0.2 + (goals.contains(.weightManagement) ? 0.3 : 0),
            createdAt: ctx.now, link: .weight
        )
    }

    /// Weight trend falling while walking rose over the same period (timing only).
    func weightActivity() -> Insight? {
        guard let t = WeightAnalytics.trend(ctx), let change = t.change30Days, change <= -0.4 else { return nil }
        let recent = ctx.trailing(30)
        let before = ctx.trailing(30, endingDaysAgo: 31)
        guard let r = a.average(.steps, in: recent), r.days >= 20, let b = a.average(.steps, in: before), b.days >= 20,
              let stepChange = Stats.percentChange(from: b.value, to: r.value), stepChange >= 0.08 else { return nil }
        return Insight(
            id: id(.weightActivity), kind: .weightActivity,
            headline: "Your walking rose as your weight trend eased down",
            explanation: "Over the last 30 days your step average rose \(Fmt.percent(stepChange)) (to \(Fmt.int(r.value)) a day) while your weight trend fell \(Fmt.weight(abs(change), units: units)).",
            metric: .weight, secondaryMetric: .steps, currentValue: r.value, comparisonValue: b.value, change: stepChange,
            currentRange: recent, comparisonRange: before, confidence: .moderate, sampleCount: r.days + b.days + t.sampleCount,
            source: ctx.sourceLabel(.steps), caveat: Self.relationshipCaveat,
            evidence: [
                EvidenceRow("Steps, last 30 days", "\(Fmt.int(r.value)) / day"),
                EvidenceRow("Steps, 30 days before", "\(Fmt.int(b.value)) / day"),
                EvidenceRow("Weight trend change", Fmt.weightChange(change, units: units)),
            ],
            emphasis: Fmt.signedPercent(stepChange), emphasisCaption: "steps while weight trend fell",
            score: 0.45 + (goals.contains(.weightManagement) ? 0.3 : 0), createdAt: ctx.now, link: .weight
        )
    }

    /// What happens the day after an unusually low day.
    func rebound() -> Insight? {
        let window = ctx.trailing(90, endingDaysAgo: 2)
        var events = 0, rebounds = 0
        var ratios: [Double] = []
        for d in window.days {
            guard let v = ctx.history.value(.steps, on: d) else { continue }
            let prior = Array(ctx.history.values(.steps, in: DateSpan(d.adding(days: -28), d.adding(days: -1))).values)
            guard prior.count >= 14, let med = Stats.median(prior), v < med * 0.6,
                  let next = ctx.history.value(.steps, on: d.adding(days: 1)) else { continue }
            events += 1
            ratios.append(next / med)
            if next >= med * 0.9 { rebounds += 1 }
        }
        guard events >= 4, let avgRatio = Stats.mean(ratios) else { return nil }
        let share = Double(rebounds) / Double(events)
        guard share >= 0.6 || share <= 0.25 else { return nil }
        let bounces = share >= 0.6
        return Insight(
            id: id(.rebound), kind: .rebound,
            headline: bounces ? "You usually bounce back after a quiet day" : "Quiet days tend to run into each other",
            explanation: "In the last 3 months you had \(events) unusually low days. You were back near your normal the next day \(rebounds) of \(events) times.",
            metric: .steps, currentValue: avgRatio, currentRange: window, confidence: events >= 7 ? .high : .moderate,
            sampleCount: events, source: ctx.sourceLabel(.steps),
            evidence: [
                EvidenceRow("Low day", "Under 60% of your typical day (4-week median)"),
                EvidenceRow("Low days found", "\(events)"),
                EvidenceRow("Back near normal next day", "\(rebounds) of \(events)"),
                EvidenceRow("Average next day", "\(Fmt.percent(avgRatio)) of typical"),
            ],
            emphasis: "\(rebounds)/\(events)", emphasisCaption: "quick rebounds",
            score: 0.33 + goalBoost([.recovery, .consistency]), createdAt: ctx.now, link: .walk(.month)
        )
    }

    /// Steps on days after short nights vs other days (last 60 days).
    func sleepMovement() -> Insight? {
        let window = ctx.trailing(60)
        var shortDays: [(LocalDate, Double)] = []
        var otherSteps: [Double] = []
        for d in window.days {
            guard let steps = ctx.history.value(.steps, on: d), let asleep = ctx.history.value(.sleepDuration, on: d) else { continue }
            if asleep < 6 * 3600 { shortDays.append((d, steps)) } else { otherSteps.append(steps) }
        }
        guard shortDays.count >= 4, otherSteps.count >= 10, let other = Stats.mean(otherSteps),
              let short = Stats.mean(shortDays.map(\.1)), let otherMedian = Stats.median(otherSteps) else { return nil }
        let diff = short - other
        guard let change = Stats.percentChange(from: other, to: short), change <= -0.08 else { return nil }
        let belowCount = shortDays.filter { $0.1 < otherMedian }.count
        return Insight(
            id: id(.sleepMovement), kind: .sleepMovement,
            headline: "You tend to move less after short nights",
            explanation: "On days after under 6 hours of sleep you averaged about \(Fmt.int(abs(diff))) fewer steps than other days. That happened \(belowCount) of \(shortDays.count) times in the last 2 months — worth watching, but not enough to say sleep caused it.",
            metric: .steps, secondaryMetric: .sleepDuration, currentValue: short, comparisonValue: other, change: change,
            currentRange: window, confidence: shortDays.count >= 7 ? .moderate : .low,
            sampleCount: shortDays.count + otherSteps.count, source: ctx.sourceLabel(.steps),
            caveat: Self.relationshipCaveat,
            evidence: [
                EvidenceRow("Days after < 6h sleep", "\(shortDays.count) · \(Fmt.int(short)) steps avg"),
                EvidenceRow("Other days", "\(otherSteps.count) · \(Fmt.int(other)) steps avg"),
                EvidenceRow("Difference", "\(Fmt.int(diff)) steps (\(Fmt.signedPercent(change)))"),
                EvidenceRow("Below your usual", "\(belowCount) of \(shortDays.count) short-sleep days"),
            ],
            emphasis: "\(Fmt.int(diff))", emphasisCaption: "steps after short nights",
            score: min(1, abs(change) / 0.25) * 0.4 + 0.15 + goalBoost([.recovery, .understandHealth]),
            createdAt: ctx.now, link: .sleep(nil)
        ).with(points: [EvidencePoint("Other days", other), EvidencePoint("After < 6h", short, highlighted: true)])
    }

    /// Bedtime over the last 7 nights vs the 3 weeks before.
    func sleepTiming() -> Insight? {
        let points = SleepAnalytics.timing(ctx, nights: 28)
        let recentStart = ctx.today.adding(days: -6)
        let recent = points.filter { $0.date >= recentStart }
        let before = points.filter { $0.date < recentStart }
        guard recent.count >= 5, before.count >= 12,
              let r = Stats.median(recent.map(\.bedMinutes)), let b = Stats.median(before.map(\.bedMinutes)) else { return nil }
        let shift = r - b
        guard abs(shift) >= 30 else { return nil }
        let later = shift > 0
        return Insight(
            id: id(.sleepTiming), kind: .sleepTiming,
            headline: later ? "Your sleep timing shifted later this week" : "You've been going to sleep earlier this week",
            explanation: "Over the last \(recent.count) nights you usually fell asleep around \(SleepAnalytics.clock(r)), about \(Int(abs(shift).rounded())) minutes \(later ? "later" : "earlier") than the 3 weeks before (\(SleepAnalytics.clock(b))).",
            metric: .sleepDuration, currentValue: r, comparisonValue: b, change: nil,
            currentRange: DateSpan(recentStart, ctx.today), comparisonRange: DateSpan(ctx.today.adding(days: -27), recentStart.adding(days: -1)),
            confidence: recent.count >= 6 && before.count >= 18 ? .high : .moderate,
            sampleCount: recent.count + before.count, source: ctx.sourceLabel(.sleepDuration),
            evidence: recent.map { EvidenceRow("Night ending \(Fmt.dayLabel($0.date))", "\(SleepAnalytics.clock($0.bedMinutes)) – \(SleepAnalytics.clock($0.wakeMinutes))") }
                + [EvidenceRow("Typical bedtime, 3 weeks before", SleepAnalytics.clock(b))],
            emphasis: "\(later ? "+" : "\u{2212}")\(Int(abs(shift).rounded())) min", emphasisCaption: "bedtime vs your usual",
            score: min(1, abs(shift) / 90) * 0.45 + 0.2 + goalBoost([.recovery, .understandHealth]),
            createdAt: ctx.now, link: .sleep(nil)
        )
    }

    /// Steps on and after a recent body note, compared with the usual for those weekdays.
    /// Shows the records side by side; never claims the note explains the change.
    func noteContext() -> Insight? {
        let window = DateSpan(ctx.today.adding(days: -60), ctx.yesterday)
        var best: Insight?
        for note in ctx.history.events where window.contains(note.date) {
            guard let steps = ctx.history.value(.steps, on: note.date) else { continue }
            let prior = (1...8).compactMap { ctx.history.value(.steps, on: note.date.adding(days: -7 * $0)) }
            guard prior.count >= 3, let usual = Stats.median(prior), usual > 0 else { continue }
            let change = (steps - usual) / usual
            guard change <= -0.2 else { continue }
            let after = (1...3).compactMap { ctx.history.value(.steps, on: note.date.adding(days: $0)) }
            let weekday = Fmt.weekday(note.date)
            var explanation = "On \(Fmt.dayLabel(note.date)), the day of your note “\(note.title)”, you recorded \(Fmt.int(steps)) steps; a typical \(weekday) for you is about \(Fmt.int(usual))."
            if let a = Stats.mean(after), after.count >= 2 { explanation += " The next \(after.count) days averaged \(Fmt.int(a))." }
            let insight = Insight(
                id: id(.noteContext, note.id), kind: .noteContext,
                headline: "Fewer steps around your \(note.bodyRegion?.displayName.lowercased() ?? "body") note",
                explanation: explanation, metric: .steps, currentValue: steps, comparisonValue: usual, change: change,
                currentRange: DateSpan(note.date, note.date.adding(days: 3)),
                confidence: prior.count >= 6 ? .moderate : .low, sampleCount: prior.count + 1 + after.count,
                source: ctx.sourceLabel(.steps),
                caveat: "Your note and your steps are shown side by side. The data can't establish what caused the change.",
                evidence: [EvidenceRow("Note", "\(note.title) · \(Fmt.dayLabel(note.date))"),
                           EvidenceRow("Steps that day", Fmt.int(steps)),
                           EvidenceRow("Typical \(weekday) (\(prior.count) before)", Fmt.int(usual))]
                    + after.enumerated().map { EvidenceRow(Fmt.dayLabel(note.date.adding(days: $0.offset + 1)), Fmt.int($0.element)) },
                emphasis: Fmt.signedPercent(change), emphasisCaption: "vs a typical \(weekday)",
                score: 0.4 + min(0.3, abs(change) / 2) + (note.date.days(until: ctx.today) <= 14 ? 0.1 : 0),
                createdAt: ctx.now, link: .body(note.id)
            ).with(points: [EvidencePoint("Usual \(Fmt.weekdayShort[note.date.weekday - 1])", usual), EvidencePoint("Note day", steps, highlighted: true)]
                   + after.enumerated().map { EvidencePoint("+\($0.offset + 1)d", $0.element) })
            if (best?.score ?? 0) < insight.score { best = insight }
        }
        return best
    }
}
