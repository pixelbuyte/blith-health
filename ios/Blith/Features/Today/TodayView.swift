import BlithCore
import SwiftUI

/// Today: three dials (sleep, readiness, load) against the person's own usual, the vitals behind
/// them, movement so far compared with the same time on a usual day, and one insight with its evidence.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollTarget: String?

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    header
                    if let s = app.snapshot {
                        scores(s).id("scores")
                        LiveHeartCard(live: app.liveHeart, isDemo: app.isDemo).id("live")
                        week(s).id("week")
                        monitor(s).id("monitor")
                        movement(s).id("movement")
                        insights(s).id("insight")
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
            .onAppear { startLive() }
            .onDisappear { app.liveHeart.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, router.tab == .today { startLive() } else if phase != .active { app.liveHeart.stop() }
            }
            .onChange(of: restingBaseline) { _, value in app.liveHeart.resting = value }
            .scrollIndicators(.hidden)
            .blithBackground(wash: Palette.band(app.snapshot?.readiness.band).opacity(app.snapshot?.readiness.band == nil ? 0.12 : 0.2))
            .refreshable { await app.refresh(force: true) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $router.showAchievements) { AchievementsView() }
        }
    }

    /// The person's usual resting heart rate, used to place the live rate in a zone.
    var restingBaseline: Double? {
        guard let v = app.snapshot?.monitor.vitals.first(where: { $0.metric == .restingHeartRate }) else { return nil }
        return v.mean ?? v.value
    }

    func startLive() {
        guard app.phase == .ready else { return }
        app.liveHeart.resting = restingBaseline
        app.liveHeart.start(simulated: app.isDemo)
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: AppClock.now())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = app.profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: AppClock.now().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    if app.isDemo { SampleDataBanner() }
                }
                Text(greeting)
                    .font(Typo.display)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            HStack(spacing: Space.s) {
                StreakChip(days: app.streak.current, checkedIn: app.streak.checkedInToday) { router.showAchievements = true }
                AvatarButton(name: app.profile.name) { router.sheet = .profile }
            }
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
                              unit: s.sleepScore == nil ? nil : "%", label: "Sleep", color: Palette.sleep, size: 96)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button { router.sheet = .readiness(nil) } label: {
                    ScoreDial(fraction: r.score.map { Double($0) / 100 }, valueText: r.score.map(String.init) ?? "\(r.calibrationDays)",
                              unit: r.score == nil ? "/\(ScoreEngine.calibrationDays)" : "%", label: r.score == nil ? "Calibrating" : "Readiness",
                              color: r.score == nil ? Palette.secondaryInk : band, size: 150)
                }
                .buttonStyle(.plain)
                Button { router.open(.walk(.day), snapshot: s) } label: {
                    ScoreDial(fraction: load.map { $0.value / LoadResult.maximum }, valueText: load.map { Fmt.decimal($0.value) } ?? "–",
                              label: "Load", color: Palette.cobalt, size: 96, usual: usual)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: Space.s) {
                if let b = r.band { MonoPill(text: "\(b.label) readiness", color: band) }
                Text(r.summary).font(Typo.story).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                chip("HRV", s.ctx.history.value(.hrv, on: s.ctx.today).map { "\(Fmt.int($0)) ms" })
                divider
                chip("RHR", s.ctx.history.value(.restingHeartRate, on: s.ctx.today).map { "\(Fmt.int($0)) bpm" })
                divider
                chip("Asleep", s.sleepScore.map { Fmt.duration($0.asleep) })
                divider
                chip("Load usual", load?.usualRange.map { "\(Fmt.decimal($0.lowerBound))–\(Fmt.decimal($0.upperBound))" })
            }
            WhyButton(tint: band == Palette.secondaryInk ? Palette.cobalt : band, title: "What's behind these scores") { router.sheet = .readiness(nil) }
        }
        .card(padding: Space.l, tone: .tinted(r.band == nil ? Palette.cobalt : band))
    }

    var divider: some View { Rectangle().fill(Palette.hairline).frame(width: 1, height: 28) }

    func chip(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased()).font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk).lineLimit(1)
            Text(value ?? "–").font(Typo.number(16)).foregroundStyle(Palette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
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
                    Text("AVG \(avg.map { Fmt.int($0) } ?? "–")").font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
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
                Eyebrow(text: "Health monitor", icon: "bl.heart", color: Palette.heart)
                Spacer()
                if m.measured > 0 {
                    MonoPill(text: "\(m.within)/\(m.measured) in your range", color: m.within == m.measured ? Palette.mint : Palette.amber)
                }
            }
            ForEach(m.vitals) { v in
                Button { router.sheet = .vital(v.metric) } label: { VitalRow(reading: v) }
                    .buttonStyle(.plain)
                if v.id != m.vitals.last?.id { Rectangle().fill(Palette.separator).frame(height: 1) }
            }
            Text("Ranges are your own: the middle of your last 30 nights. Outside your range isn't a diagnosis.")
                .font(.caption2).foregroundStyle(Palette.tertiaryInk)
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
                    Eyebrow(text: "Movement · \(time)", icon: "bl.steps", color: Palette.cobalt)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.tertiaryInk)
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.int(s.todaySteps ?? 0))
                        .font(Typo.score(58))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text("steps").font(Typo.number(18, weight: .medium)).foregroundStyle(Palette.secondaryInk)
                    Spacer()
                    if let change = s.pace?.change { DeltaBadge(change: change, tint: Palette.cyan) }
                }
                if let pace = s.pace, let usual = pace.usualByNow {
                    Text("Usually \(Fmt.int(usual)) by \(time) on a \(pace.basis == .sameWeekday ? weekday : "typical day").")
                        .font(.subheadline).foregroundStyle(Palette.secondaryInk)
                }
                if let pace = s.pace, !pace.usualCurve.isEmpty {
                    AccumulationChart(pace: pace, compact: true, onHero: true).frame(height: 112)
                }
                HStack(spacing: Space.s) {
                    StatTile(title: "Distance", value: s.todayDistance.map { Fmt.distance($0, units: s.ctx.units) } ?? "–")
                    StatTile(title: "Active", value: s.todayEnergy.map { "\(Fmt.int($0)) kcal" } ?? "–")
                    StatTile(title: "Exercise", value: s.todayExercise.map { "\(Fmt.int($0)) min" } ?? "–")
                    StatTile(title: "7-day avg", value: s.average7.map { Fmt.int($0.value) } ?? "–")
                }
            }
            .card(padding: Space.l, tone: .hero)
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
                BLIcon(name: "bl.bodynote", size: 20)
                    .foregroundStyle(Palette.note)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Palette.noteSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Body note · \(note.bodyRegion?.displayName ?? "General")", color: Palette.note)
                    Text(note.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                    Text("\(Fmt.dayLabel(note.date)) · \(note.isActive(on: today) ? "unresolved" : "resolved")")
                        .font(.caption).foregroundStyle(Palette.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.tertiaryInk)
            }
            .card(padding: Space.l)
            .overlay(alignment: .leading) { Capsule().fill(Palette.note).frame(width: 3).padding(.vertical, 16).padding(.leading, 1) }
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
            BLIcon(name: reading.metric.icon, size: 16).foregroundStyle(reading.metric.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(reading.metric.shortName).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(reading.value.map { reading.metric.format($0) } ?? "–").font(Typo.number(18)).foregroundStyle(Palette.ink).monospacedDigit()
                }
                RangeBar(value: reading.value, range: reading.range, color: reading.metric.tint)
                HStack {
                    Text(statusText).font(Typo.eyebrow).foregroundStyle(statusColor)
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
        case .within: Palette.mint
        case .above, .below: Palette.amber
        case .learning, .noData: Palette.secondaryInk
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
        case .hrv: Palette.mint
        case .respiratoryRate: Palette.cyan
        case .oxygenSaturation: Palette.cobalt
        case .wristTemperature: Palette.amber
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
                        Eyebrow(text: "\(app.achievements.filter(\.isUnlocked).count) of \(app.achievements.count) earned", icon: "bl.medal", color: Palette.mint)
                        Text("Milestones").font(Typo.display).foregroundStyle(Palette.ink)
                        Text("Each one is a fact from your own records, with the day it became true. Nothing expires and nothing resets.")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Space.l)], spacing: Space.xl) {
                        ForEach(app.achievements) { AchievementBadge(achievement: $0, size: 72) }
                    }
                    .card(padding: Space.xl)
                }
                .padding(Space.page)
            }
            .blithBackground(wash: Palette.mint.opacity(0.14))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The check-in streak, small: a flame and the day count. Opens the milestones.
struct StreakChip: View {
    let days: Int
    let checkedIn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                BLIcon(name: "bl.streak", size: 14)
                Text("\(days)").font(Typo.number(16)).monospacedDigit()
            }
            .foregroundStyle(checkedIn ? Palette.mint : Palette.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(Palette.raised))
            .overlay(Capsule().strokeBorder((checkedIn ? Palette.mint : Palette.hairline).opacity(checkedIn ? 0.45 : 1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(days) day check-in streak")
        .accessibilityHint("Opens milestones")
    }
}
