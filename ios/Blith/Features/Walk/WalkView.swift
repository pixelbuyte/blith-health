import BlithCore
import SwiftUI

struct WalkView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if app.isDemo { SampleDataBanner() }
                    if let s = app.snapshot, s.availability[.steps] != .noData || s.todaySteps != nil {
                        summary(s)
                        VStack(alignment: .leading, spacing: Space.m) {
                            PeriodPicker(selection: $router.walkPeriod)
                            history(s, period: router.walkPeriod)
                        }
                        averages(s)
                        patterns(s)
                        gait(s)
                        workouts(s)
                        Button { router.sheet = .sources } label: {
                            Label("Data sources", systemImage: "square.stack.3d.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .card()
                    } else {
                        EmptyStateView(symbol: "figure.walk", title: "No steps yet",
                                       message: "Steps come from your iPhone or Apple Watch through Apple Health. If you've turned off Motion & Fitness or limited access, you can change that in Settings › Health › Data Access.",
                                       actionTitle: "Connected data") { router.sheet = .profile }
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
            }
            .background(Palette.background)
            .refreshable { await app.refresh(force: true) }
            .navigationTitle("Walking")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.sheet = .profile } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Profile and settings")
                }
            }
        }
    }

    // MARK: Summary

    func summary(_ s: HealthSnapshot) -> some View {
        let units = s.ctx.units
        return VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.int(s.todaySteps ?? 0)).font(Typo.number(heroSize)).monospacedDigit().contentTransition(.numericText())
                Text("steps today").font(.headline).foregroundStyle(.secondary)
            }
            HStack(spacing: Space.l) {
                StatTile(title: "Distance", value: s.todayDistance.map { Fmt.distance($0, units: units) } ?? "—")
                StatTile(title: "Exercise", value: s.todayExercise.map { "\(Fmt.int($0)) min" } ?? "—")
                StatTile(title: "Walking speed",
                         value: s.ctx.history.value(.walkingSpeed, on: s.ctx.today).map { Fmt.speed($0, units: units) }
                            ?? HealthAnalytics(s.ctx).rollingAverage(.walkingSpeed, days: 7).map { Fmt.speed($0.value, units: units) } ?? "—",
                         caption: s.ctx.history.value(.walkingSpeed, on: s.ctx.today) == nil ? "7-day avg" : nil)
                if let e = s.todayEnergy {
                    StatTile(title: "Active energy", value: "\(Fmt.int(e))", caption: "kcal")
                }
            }
        }
        .padding(.top, Space.s)
    }

    // MARK: History

    func history(_ s: HealthSnapshot, period: WalkPeriod) -> some View {
        let p = s.periods[period] ?? HealthAnalytics(s.ctx).periodSummary(.steps, period: period)
        return VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(period == .day ? "TODAY SO FAR" : "DAILY AVERAGE · \(period.title.uppercased())").font(Typo.eyebrow).foregroundStyle(.secondary)
                    Text(Fmt.int(period == .day ? (s.todaySteps ?? 0) : (p.dailyAverage ?? 0)))
                        .font(Typo.number(34)).monospacedDigit().contentTransition(.numericText())
                }
                Spacer()
                if let c = p.change {
                    DeltaBadge(change: c, caption: period == .day ? "vs usual by now" : "vs previous")
                }
            }
            StepHistoryChart(buckets: p.buckets, unit: p.bucketUnit, average: period == .day ? nil : p.dailyAverage, usualHourly: p.usualHourly)
                .id(period)
            if period == .day {
                Text("Bars are this hour-by-hour; the dashed line is your usual \(Fmt.weekday(s.ctx.today)).")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                periodStats(p)
            }
        }
        .card(padding: Space.xl)
    }

    func periodStats(_ p: PeriodSummary) -> some View {
        let columns = [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
            StatTile(title: "Previous", value: p.previousDailyAverage.map(Fmt.int) ?? "—", caption: "avg / day")
            StatTile(title: "Total", value: Fmt.int(p.total))
            StatTile(title: "Median day", value: p.median.map(Fmt.int) ?? "—")
            StatTile(title: "Highest", value: p.highest.map { Fmt.int($0.value) } ?? "—", caption: p.highest.map { Fmt.dayLabel($0.date) })
            StatTile(title: "Lowest", value: p.lowest.map { Fmt.int($0.value) } ?? "—", caption: p.lowest.map { Fmt.dayLabel($0.date) })
            StatTile(title: "Near usual", value: p.activeThreshold == nil ? "—" : "\(p.activeDays)",
                     caption: p.activeThreshold.map { "days ≥ \(Fmt.int($0))" })
            StatTile(title: "Weekdays", value: p.weekdayAverage.map(Fmt.int) ?? "—", caption: "avg / day")
            StatTile(title: "Weekends", value: p.weekendAverage.map(Fmt.int) ?? "—", caption: "avg / day")
            StatTile(title: "Day-to-day", value: p.variability.map { "±\(Fmt.percent($0))" } ?? "—", caption: "variability")
        }
    }

    // MARK: Averages

    func averages(_ s: HealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Your averages", subtitle: "Complete days, today excluded")
            VStack(spacing: 0) {
                averageRow("7 days", s.average7)
                Divider()
                averageRow("30 days", s.average30)
                Divider()
                averageRow("90 days", s.average90)
            }
            .card(padding: Space.l)
        }
    }

    func averageRow(_ label: String, _ a: AverageResult?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let a {
                if a.days < a.span.dayCount {
                    Text("\(a.days) days of data").font(.caption).foregroundStyle(.tertiary)
                }
                Text(Fmt.int(a.value)).font(.headline).monospacedDigit()
            } else {
                Text("Not enough data").font(.subheadline).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: Walk DNA

    @ViewBuilder
    func patterns(_ s: HealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Patterns", subtitle: "How you tend to walk")
            if s.patterns.isEmpty {
                EmptyStateView(symbol: "hourglass", title: "Still learning",
                               message: "Patterns appear after a few weeks of history.")
            } else {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(s.patterns) { p in
                        HStack(alignment: .top, spacing: Space.m) {
                            Image(systemName: p.symbol)
                                .foregroundStyle(Palette.accent)
                                .frame(width: 32, height: 32)
                                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.text).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                Text(p.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card(padding: Space.xl)
            }
            if s.weekdayPattern.medians.compactMap({ $0 }).count >= 5 {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Typical day of the week").font(Typo.cardTitle)
                    Text("Median steps per weekday, last 12 weeks").font(.footnote).foregroundStyle(.secondary)
                    WeekdayBars(pattern: s.weekdayPattern, firstWeekday: s.ctx.profile.firstWeekday)
                }
                .card(padding: Space.xl)
            }
            if let tod = s.timeOfDay {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("When you move").font(Typo.cardTitle)
                    Text("Share of steps by hour, last 4 weeks · \(Fmt.percent(tod.shareBefore4PM)) before 4 PM").font(.footnote).foregroundStyle(.secondary)
                    TimeOfDayBars(profile: tod)
                }
                .card(padding: Space.xl)
            }
        }
    }

    // MARK: Gait

    @ViewBuilder
    func gait(_ s: HealthSnapshot) -> some View {
        let a = HealthAnalytics(s.ctx)
        let units = s.ctx.units
        let metrics: [HealthMetric] = [.walkingSpeed, .walkingStepLength, .walkingAsymmetry, .walkingDoubleSupport]
        let available = metrics.filter { a.rollingAverage($0, days: 28) != nil }
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "How you walk", subtitle: "Measured by your iPhone while you walk")
            if available.isEmpty {
                EmptyStateView(symbol: "speedometer", title: s.availability[.walkingSpeed] == .unsupported ? "Not recorded on this device" : "No walking metrics yet",
                               message: "Walking speed and step length are measured automatically when you carry your iPhone in a pocket. They'll appear here once recorded.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(available.enumerated()), id: \.offset) { index, metric in
                        let recent = a.rollingAverage(metric, days: 28)!
                        let earlier = a.average(metric, in: s.ctx.trailing(28, endingDaysAgo: 57))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.displayName).font(.subheadline.weight(.semibold))
                                Text("28-day average").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.value(recent.value, metric: metric, units: units)).font(.headline).monospacedDigit()
                                if let e = earlier, let c = Stats.percentChange(from: e.value, to: recent.value) {
                                    Text("\(Fmt.signedPercent(c)) vs 2 months ago").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, Space.m)
                        .accessibilityElement(children: .combine)
                        if index < available.count - 1 { Divider() }
                    }
                }
                .card(padding: Space.l)
                Text("These describe walking patterns, not a diagnosis.").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Workouts

    @ViewBuilder
    func workouts(_ s: HealthSnapshot) -> some View {
        let recent = s.ctx.history.workouts.filter { $0.start >= Date().addingTimeInterval(-30 * 86_400) }.sorted { $0.start > $1.start }
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "Recent workouts", subtitle: "\(recent.count) in the last 30 days")
                WorkoutList(workouts: Array(recent.prefix(5)), units: s.ctx.units)
                    .card(padding: Space.l)
            }
        }
    }
}

struct WorkoutList: View {
    let workouts: [WorkoutRecord]
    let units: UnitSystem

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(workouts.enumerated()), id: \.offset) { index, w in
                HStack(spacing: Space.m) {
                    Image(systemName: w.isWalking ? "figure.walk" : (w.activity == "Running" ? "figure.run" : "figure.mixed.cardio"))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.activity).font(.subheadline.weight(.semibold))
                        Text(w.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.duration(w.duration)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        if let d = w.distanceMeters, d > 0 {
                            Text(Fmt.distance(d, units: units)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, Space.s)
                .accessibilityElement(children: .combine)
                if index < workouts.count - 1 { Divider() }
            }
        }
    }
}
