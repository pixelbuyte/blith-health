import BlithCore
import SwiftUI

/// Today: three dials (sleep, readiness, load) against the person's own usual, the vitals behind
/// them, movement so far compared with the same time on a usual day, and one insight with its evidence.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @State private var scrollTarget: String?

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    if let sync = app.huaweiSync, sync.freshness != .current {
                        CompanionSyncCard(status: sync,
                                          onRefresh: { Task { await app.refresh(force: true) } },
                                          onDetails: { router.sheet = .sources })
                    }
                    if let s = app.snapshot {
                        scores(s).id("scores")
                        DayRibbon(ctx: s.ctx).id("ribbon")
                        movement(s).id("movement")
                        insights(s).id("insight")
                        week(s).id("week")
                        monitor(s).id("monitor")
                        rhythm(s).id("rhythm")
                        milestones
                        context(s)
                        moreInsights(s)
                        if let history = app.history {
                            SyncStatusLine(history: history, isSyncing: app.isSyncing).padding(.top, Space.s)
                        }
                    } else {
                        EmptyStateView(symbol: "bl.today", title: "Connect Apple Health",
                                       message: "Connect Apple Health to start building your personal baseline.",
                                       actionTitle: "Open settings", action: { router.sheet = .profile })
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollTarget, anchor: .top)
            .task { await LaunchOptions.scroll { scrollTarget = $0 } }
            .scrollIndicators(.hidden)
            .blithBackground(wash: Palette.signal.opacity(0.16))
            .refreshable { await app.refresh(force: true) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $router.showAchievements) { AchievementsView() }
        }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: AppClock.now())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = app.profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// One personal sentence computed from the day so far: movement against the same time on a
    /// usual day, else the readiness story. Never generic encouragement.
    var statusLine: String? {
        guard let s = app.snapshot else { return nil }
        if let pace = s.pace, let change = pace.change, pace.usualByNow != nil, abs(change) >= 0.08 {
            let day = pace.basis == .sameWeekday ? Fmt.weekday(s.ctx.today) : "day"
            return change > 0
                ? "Your movement is running \(Fmt.percent(change)) ahead of a usual \(day) at this hour."
                : "You're \(Fmt.percent(abs(change))) behind a usual \(day) at this hour, with the evening still to come."
        }
        return s.readiness.score == nil ? nil : s.readiness.summary
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: AppClock.now().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    if app.isDemo { SampleDataBanner() }
                }
                Text(greeting)
                    .font(Typo.pageTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if let line = statusLine {
                    Text(line)
                        .font(Typo.story)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer()
            AvatarButton(name: app.profile.name) { router.sheet = .profile }
        }
        .padding(.top, Space.s)
    }

    // MARK: Scores

    func scores(_ s: HealthSnapshot) -> some View {
        let r = s.readiness
        let band = Palette.band(r.band)
        let load = s.load
        let usual = load?.usualRange.map { ($0.lowerBound / LoadResult.maximum)...($0.upperBound / LoadResult.maximum) }
        return VStack(spacing: Space.l) {
            HStack(alignment: .center, spacing: 0) {
                Button { router.open(.sleep(nil), snapshot: s) } label: {
                    ScoreDial(fraction: s.sleepScore.map { Double($0.score) / 100 }, valueText: s.sleepScore.map { "\($0.score)" } ?? "–",
                              unit: s.sleepScore == nil ? nil : "%", label: "Sleep", color: Palette.sleep, size: 92)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button { router.sheet = .readiness(nil) } label: {
                    ScoreDial(fraction: r.score.map { Double($0) / 100 }, valueText: r.score.map(String.init) ?? "\(r.calibrationDays)",
                              unit: r.score == nil ? "/\(ScoreEngine.calibrationDays)" : "%", label: r.score == nil ? "Calibrating" : "Readiness",
                              color: r.score == nil ? Palette.tertiaryInk : band, size: 168)
                }
                .buttonStyle(.plain)
                Button { router.open(.walk(.day), snapshot: s) } label: {
                    ScoreDial(fraction: load.map { $0.value / LoadResult.maximum }, valueText: load.map { Fmt.decimal($0.value) } ?? "–",
                              label: "Load", color: Palette.cyan, size: 92, usual: usual)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            if let b = r.band {
                BandChip(band: b, label: "\(b.label) readiness")
            }
            HStack(spacing: 0) {
                chip("HRV", s.ctx.history.value(.hrv, on: s.ctx.today).map { "\(Fmt.int($0)) ms" })
                divider
                chip("RHR", s.ctx.history.value(.restingHeartRate, on: s.ctx.today).map { "\(Fmt.int($0)) bpm" })
                divider
                chip("Asleep", s.sleepScore.map { Fmt.duration($0.asleep) })
                divider
                chip("Load usual", load?.usualRange.map { "\(Fmt.decimal($0.lowerBound))–\(Fmt.decimal($0.upperBound))" })
            }
            WhyButton(tint: Palette.signal, title: "What's behind these scores") { router.sheet = .readiness(nil) }
        }
        .card(padding: Space.l, tone: .hero)
    }

    var divider: some View { Rectangle().fill(Palette.hairline).frame(width: 1, height: 28) }

    func chip(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased()).font(Typo.eyebrow).tracking(0.8).foregroundStyle(Palette.tertiaryInk).lineLimit(1)
            Text(value ?? "–").font(Typo.number(16)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Week

    @ViewBuilder
    func week(_ s: HealthSnapshot) -> some View {
        let days = Array(s.scoreHistory.suffix(7))
        if days.contains(where: { $0.readiness != nil }) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow(text: "Last 7 days · readiness", icon: "bl.readiness")
                    Spacer()
                    let avg = Stats.mean(days.compactMap(\.readiness).map(Double.init))
                    Text("AVG \(avg.map { Fmt.int($0) } ?? "–")").font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
                }
                WeekStrip(days: days, selected: s.ctx.today) { d in router.sheet = .readiness(d) }
            }
            .card(padding: Space.l)
        }
    }

    // MARK: Health monitor

    func monitor(_ s: HealthSnapshot) -> some View {
        let m = s.monitor
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Health monitor").font(Typo.sectionTitle).foregroundStyle(Palette.ink)
                Spacer()
                if m.measured > 0 {
                    MonoPill(text: "\(m.within) of \(m.measured) in your range", color: m.within == m.measured ? Palette.secondaryInk : Palette.note)
                }
            }
            ForEach(m.vitals) { v in
                Button { router.sheet = .vital(v.metric) } label: { VitalRow(reading: v) }
                    .buttonStyle(.plain)
                if v.id != m.vitals.last?.id { Rectangle().fill(Palette.separator).frame(height: 1) }
            }
            Text("Ranges are your own: the middle of your last 30 nights. Outside your range isn't a diagnosis.")
                .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.tertiaryInk)
        }
        .card(padding: Space.l)
    }

    // MARK: Movement

    func movement(_ s: HealthSnapshot) -> some View {
        let time = AppClock.now().formatted(date: .omitted, time: .shortened)
        let weekday = Fmt.weekday(s.ctx.today)
        return Button { router.open(.walk(.day), snapshot: s) } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow(text: "Movement · \(time)", icon: "bl.steps", color: Palette.signal)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiaryInk)
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.int(s.todaySteps ?? 0))
                        .font(Typo.score(60))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text("steps").font(Typo.geist(17, .medium, relativeTo: .headline)).foregroundStyle(Palette.secondaryInk)
                    Spacer()
                    if let change = s.pace?.change {
                        DeltaBadge(change: change, tint: change >= 0 ? Palette.signalBright : Palette.secondaryInk)
                    }
                }
                if let pace = s.pace, let usual = pace.usualByNow {
                    Text("Usually \(Fmt.int(usual)) by \(time) on a \(pace.basis == .sameWeekday ? weekday : "typical day"). The shaded area is your usual day.")
                        .font(Typo.geist(14, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let pace = s.pace, !pace.usualCurve.isEmpty {
                    AccumulationChart(pace: pace, compact: true).frame(height: 128)
                }
                HStack(spacing: Space.s) {
                    StatTile(title: "Distance", value: s.todayDistance.map { Fmt.distance($0, units: s.ctx.units) } ?? "–")
                    StatTile(title: "Active", value: s.todayEnergy.map { "\(Fmt.int($0)) kcal" } ?? "–")
                    StatTile(title: "Exercise", value: s.todayExercise.map { "\(Fmt.int($0)) min" } ?? "–")
                    StatTile(title: "7-day avg", value: s.average7.map { Fmt.int($0.value) } ?? "–")
                }
            }
            .card(padding: Space.l)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens today's activity")
    }

    // MARK: Insights

    @ViewBuilder
    func insights(_ s: HealthSnapshot) -> some View {
        if let top = s.feed.first {
            InsightCard(insight: top, featured: true, onWhy: { router.sheet = .insight(top) },
                        onOpen: { router.open(top.link, snapshot: s) })
        } else {
            let days = s.ctx.history.values(.steps, in: s.ctx.trailing(28)).count
            EmptyStateView(symbol: "bl.calendar", title: days < 7 ? "Learning your normal" : "Nothing unusual right now",
                           message: days < 7
                               ? "Blith compares you with your own history. It has \(days) of the 7 days it needs before it can say what's normal for you."
                               : "Your recent weeks are close to your usual. When something meaningful changes, it will show up here with the evidence.")
        }
    }

    @ViewBuilder
    func moreInsights(_ s: HealthSnapshot) -> some View {
        let rest = Array(s.feed.dropFirst())
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "Also worth knowing")
                ForEach(rest) { insight in
                    InsightCard(insight: insight, onWhy: { router.sheet = .insight(insight) },
                                onOpen: { router.open(insight.link, snapshot: s) })
                }
            }
        }
    }

    // MARK: Rhythm (bento: streak + week)

    func rhythm(_ s: HealthSnapshot) -> some View {
        let streak = app.streak
        let next = [3, 7, 14, 30, 60, 100].first { $0 > streak.current } ?? streak.current + 1
        return HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "Check-in streak", icon: "bl.streak", color: Palette.signal)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streak.current)").font(Typo.score(50)).foregroundStyle(Palette.ink)
                    Text(streak.current == 1 ? "day" : "days").font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                }
                SegmentedProgress(total: min(next, 14), done: min(next, 14) * streak.current / max(next, 1), color: Palette.signal)
                Text("\(next - streak.current) to \(next) · best \(streak.best)").font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .card(padding: Space.l)
            if let c = s.consistency {
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow(text: "Walking week", icon: "bl.steptrail")
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(c.metCount)").font(Typo.score(50)).foregroundStyle(Palette.ink)
                        Text("/7").font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                    }
                    ConsistencyDots(week: c)
                    Text(c.thresholdIsGoal ? "days at your goal" : "days near your usual").font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .card(padding: Space.l)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Milestones

    @ViewBuilder
    var milestones: some View {
        let list = app.achievements.sorted { a, b in
            if a.isUnlocked != b.isUnlocked { return a.isUnlocked }
            return a.progress > b.progress
        }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "Milestones", subtitle: "\(list.filter(\.isUnlocked).count) of \(list.count) earned from your own records",
                              trailing: "See all") { router.showAchievements = true }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Space.m) {
                        ForEach(list.prefix(8)) { AchievementBadge(achievement: $0) }
                    }
                    .padding(.vertical, Space.s)
                }
            }
        }
    }

    // MARK: Context

    @ViewBuilder
    func context(_ s: HealthSnapshot) -> some View {
        let units = s.ctx.units
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: "Around your day")
            HStack(alignment: .top, spacing: Space.m) {
                vo2Tile(s)
                weightTile(s, units: units)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let note = s.ctx.history.bodyNotes.first(where: { $0.isActive(on: s.ctx.today) }) ?? s.ctx.history.bodyNotes.first {
                noteTile(note, today: s.ctx.today)
            }
        }
    }

    func vo2Tile(_ s: HealthSnapshot) -> some View {
        let values = s.ctx.history.values(.vo2Max, in: s.ctx.trailing(180)).sorted { $0.key < $1.key }
        return Button { router.sheet = .vital(.vo2Max) } label: {
            MetricTile(title: "Cardio fitness", icon: "bl.vo2", value: values.last.map { Fmt.decimal($0.value) } ?? "–", unit: values.isEmpty ? nil : "VO₂",
                       caption: values.count >= 2 ? "\(signed(values.last!.value - values.first!.value)) since \(Fmt.shortDate(values.first!.key))" : "From outdoor walks and runs",
                       color: Palette.heart, spark: values.map(\.value))
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
    }

    func signed(_ v: Double) -> String { (v >= 0 ? "+" : "−") + Fmt.decimal(abs(v)) }

    func weightTile(_ s: HealthSnapshot, units: UnitSystem) -> some View {
        Button { router.sheet = .weight } label: {
            MetricTile(title: "Weight trend", icon: "bl.weight", value: s.weight.map { Fmt.weight($0.trendNow, units: units) } ?? "–",
                       caption: s.weight.map { w in w.change30Days.map { "\(Fmt.weightChange($0, units: units)) in 30 days" } ?? "\(w.sampleCount) readings" } ?? "From a smart scale",
                       color: Palette.weight, spark: s.weight.map { Array($0.points.suffix(45).map(\.trend)) } ?? [])
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
    }

    func noteTile(_ note: HealthEvent, today: LocalDate) -> some View {
        Button { router.open(.body(note.id), snapshot: app.snapshot) } label: {
            HStack(spacing: Space.m) {
                SignalGlyph(symbol: "bl.bodynote", tint: Palette.note, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Body note · \(note.bodyRegion?.displayName ?? "General")", color: Palette.note)
                    Text(note.title).font(Typo.cardTitle).foregroundStyle(Palette.ink).lineLimit(2)
                    Text("\(Fmt.dayLabel(note.date)) · \(note.isActive(on: today) ? "unresolved" : "resolved")")
                        .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.tertiaryInk)
            }
            .card(padding: Space.l)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the note on the body map")
    }
}

/// One vital with its personal range.
struct VitalRow: View {
    let reading: VitalReading

    var body: some View {
        HStack(spacing: Space.m) {
            BLIcon(name: reading.metric.icon, size: 17).foregroundStyle(reading.metric.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(reading.metric.shortName).font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(reading.value.map { reading.metric.format($0) } ?? "–").font(Typo.number(18)).foregroundStyle(Palette.ink)
                }
                RangeBar(value: reading.value, range: reading.range, color: reading.metric.tint)
                HStack(spacing: 5) {
                    Image(systemName: statusSymbol).font(.system(size: 9, weight: .bold)).foregroundStyle(statusColor)
                    Text(statusText).font(Typo.eyebrow).tracking(0.8).foregroundStyle(statusColor)
                    Spacer()
                    if let r = reading.range {
                        Text("\(reading.metric.format(r.lowerBound)) – \(reading.metric.format(r.upperBound))").font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    var statusText: String {
        switch reading.status {
        case .within: "IN YOUR RANGE"
        case .above: "ABOVE YOUR RANGE"
        case .below: "BELOW YOUR RANGE"
        case .learning: "LEARNING YOUR RANGE"
        case .noData: "NO READING LAST NIGHT"
        }
    }

    var statusColor: Color {
        switch reading.status {
        case .within: Palette.secondaryInk
        case .above, .below: Palette.note
        case .learning, .noData: Palette.tertiaryInk
        }
    }

    var statusSymbol: String {
        switch reading.status {
        case .within: "checkmark"
        case .above: "arrow.up"
        case .below: "arrow.down"
        case .learning: "ellipsis"
        case .noData: "minus"
        }
    }
}

extension HealthMetric {
    var shortName: String {
        switch self {
        case .restingHeartRate: "Resting heart rate"
        case .hrv: "HRV"
        case .respiratoryRate: "Respiratory rate"
        case .oxygenSaturation: "Blood oxygen"
        case .wristTemperature: "Wrist temperature"
        case .vo2Max: "Cardio fitness"
        default: displayName
        }
    }

    var icon: String {
        switch self {
        case .restingHeartRate, .walkingHeartRate: "bl.rhr"
        case .hrv: "bl.hrv"
        case .respiratoryRate: "bl.resp"
        case .oxygenSaturation: "bl.spo2"
        case .wristTemperature: "bl.temp"
        case .vo2Max: "bl.vo2"
        case .steps: "bl.steps"
        case .activeEnergy: "bl.energy"
        case .flightsClimbed: "bl.stairs"
        case .distanceWalkingRunning: "bl.distance"
        case .sleepDuration: "bl.sleep"
        case .weight, .bodyFat: "bl.weight"
        default: "bl.trend"
        }
    }

    var tint: Color {
        switch self {
        case .restingHeartRate, .walkingHeartRate, .vo2Max: Palette.heart
        case .hrv: Palette.recovery
        case .respiratoryRate: Palette.cyan
        case .oxygenSaturation: Palette.signal
        case .wristTemperature: Palette.sleep
        case .sleepDuration: Palette.sleep
        case .weight, .bodyFat: Palette.weight
        default: Palette.cobalt
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .restingHeartRate, .walkingHeartRate: "\(Fmt.int(v)) bpm"
        case .hrv: "\(Fmt.int(v)) ms"
        case .respiratoryRate: "\(Fmt.decimal(v)) /min"
        case .oxygenSaturation: "\(Fmt.decimal(v * 100))%"
        case .wristTemperature: "\(Fmt.decimal(v, digits: 2))°"
        case .vo2Max: Fmt.decimal(v)
        default: Fmt.value(v, metric: self, units: .metric)
        }
    }
}

/// All milestones, earned and in progress.
struct AchievementsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "\(app.achievements.filter(\.isUnlocked).count) of \(app.achievements.count) earned", icon: "bl.medal", color: Palette.signal)
                        Text("Milestones").font(Typo.pageTitle).foregroundStyle(Palette.ink)
                        Text("Each one is a fact from your own records, with the day it became true. Nothing expires and nothing resets.")
                            .font(Typo.body).foregroundStyle(Palette.secondaryInk)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Space.l)], spacing: Space.xl) {
                        ForEach(app.achievements) { AchievementBadge(achievement: $0, size: 72) }
                    }
                    .card(padding: Space.xl)
                }
                .padding(Space.page)
            }
            .blithBackground(wash: Palette.signal.opacity(0.14))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
