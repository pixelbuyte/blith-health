import BlithCore
import SwiftUI

/// Today answers four questions in order: what's happening today, how it compares with my
/// usual at this same time, what changed recently that's worth knowing, and what to inspect next.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 64

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header
                    if let s = app.snapshot {
                        storyCard(s)
                        insights(s)
                        rhythm(s)
                        milestones
                        context(s)
                        moreInsights(s)
                        if let history = app.history {
                            SyncStatusLine(history: history, isSyncing: app.isSyncing).padding(.top, Space.s)
                        }
                    } else {
                        EmptyStateView(symbol: "bl.today", title: "Connect Apple Health",
                                       message: "Connect Apple Health to start building your personal baseline.",
                                       actionTitle: "Open settings", action: { router.sheet = .profile }, mascot: .waving)
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
            }
            .blithBackground()
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

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Eyebrow(text: AppClock.now().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    if app.isDemo { SampleDataBanner() }
                }
                Text(greeting)
                    .font(Typo.display)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            AvatarButton(name: app.profile.name) { router.sheet = .profile }
        }
        .padding(.top, Space.l)
    }

    // MARK: Story

    func storyCard(_ s: HealthSnapshot) -> some View {
        let time = AppClock.now().formatted(date: .omitted, time: .shortened)
        let weekday = Fmt.weekday(s.ctx.today)
        return Button { router.open(.walk(.day), snapshot: s) } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Eyebrow(text: "Today · \(time)", icon: "bl.walk", color: .white.opacity(0.85))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                }
                Text(s.headline)
                    .font(Typo.story)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.int(s.todaySteps ?? 0))
                        .font(Typo.number(heroSize))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("steps so far").font(.headline).foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                comparisonLine(s, time: time, weekday: weekday)
                if let pace = s.pace, !pace.usualCurve.isEmpty {
                    AccumulationChart(pace: pace, compact: true, onHero: true).frame(height: 128)
                    HStack(spacing: Space.l) {
                        legend(dashed: false, text: "Today")
                        legend(dashed: true, text: pace.basis == .sameWeekday ? "Your usual \(weekday) (\(pace.observations) weeks)" : "Your usual day (\(pace.observations) days)")
                    }
                }
                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                HStack {
                    heroStat("7-day avg", s.average7.map { Fmt.int($0.value) }, coverage(s.average7, of: 7))
                    heroStat("30-day avg", s.average30.map { Fmt.int($0.value) }, coverage(s.average30, of: 30))
                    heroStat("Distance", s.todayDistance.map { Fmt.distance($0, units: s.ctx.units) }, nil)
                }
            }
            .card(padding: Space.xl, tone: .hero)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens today's walking")
    }

    @ViewBuilder
    func comparisonLine(_ s: HealthSnapshot, time: String, weekday: String) -> some View {
        if let pace = s.pace, let usual = pace.usualByNow {
            HStack(spacing: Space.s) {
                if let change = pace.change {
                    let flat = Int((change * 100).rounded()) == 0
                    Text(flat ? "On pace" : Fmt.signedPercent(change))
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                Text("Usually \(Fmt.int(usual)) by \(time) on a \(pace.basis == .sameWeekday ? weekday : "typical day")")
                    .font(.subheadline)
            }
            .foregroundStyle(.white.opacity(0.92))
        } else {
            Text("Your usual pace for this time of day appears after a few days of history.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
        }
    }

    func heroStat(_ title: String, _ value: String?, _ caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.7))
            Text(value ?? "—").font(Typo.metric).monospacedDigit().foregroundStyle(.white)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.7)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    func legend(dashed: Bool, text: String) -> some View {
        HStack(spacing: Space.xs) {
            if dashed {
                HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(.white.opacity(0.6)).frame(width: 3, height: 3) } }
            } else {
                Capsule().fill(.white).frame(width: 14, height: 3)
            }
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
    }

    /// "3 days of data" when an average covers fewer days than its window.
    func coverage(_ a: AverageResult?, of days: Int) -> String? {
        guard let a, a.days < days else { return nil }
        return "\(a.days) \(a.days == 1 ? "day" : "days") of data"
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
                               : "Your recent weeks are close to your usual. When something meaningful changes, it will show up here with the evidence.",
                           mascot: days < 7 ? .thinking : .idle)
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

    // MARK: Rhythm

    func rhythm(_ s: HealthSnapshot) -> some View {
        let streak = app.streak
        let next = [3, 7, 14, 30, 60, 100].first { $0 > streak.current } ?? streak.current + 1
        return VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                StreakRing(progress: Double(streak.current) / Double(next)) {
                    BlithMascot(pose: streak.checkedInToday ? .waving : .idle, size: 52)
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow(text: "Check-in streak", icon: "bl.streak")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak.current)").font(.system(size: 44, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                        Text(streak.current == 1 ? "day" : "days").font(.title3).foregroundStyle(Palette.ink)
                    }
                    Text("Best \(streak.best) · \(next - streak.current) more to \(next) · \(streak.total) in all")
                        .font(.footnote).foregroundStyle(Palette.secondaryInk)
                }
            }
            if let c = s.consistency {
                ConsistencyDots(week: c)
                Label(c.thresholdIsGoal ? "\(c.metCount) days at your \(Fmt.int(c.threshold))-step goal this week" :
                        "\(c.metCount) days near your usual walking this week (≥ \(Fmt.int(c.threshold)))",
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .card(padding: Space.xl)
        .accessibilityElement(children: .contain)
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
                    .padding(.vertical, Space.xs)
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
                sleepTile(s)
                weightTile(s, units: units)
            }
            if let note = s.ctx.history.bodyNotes.first(where: { $0.isActive(on: s.ctx.today) }) ?? s.ctx.history.bodyNotes.first {
                noteTile(note, today: s.ctx.today)
            }
        }
    }

    func sleepTile(_ s: HealthSnapshot) -> some View {
        Button { router.sheet = .sleep(s.sleep.lastNight?.date) } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "Last night", icon: "bl.sleep", color: Palette.sleep)
                if let n = s.sleep.lastNight {
                    Text(Fmt.duration(n.asleepDuration)).font(Typo.number(28)).monospacedDigit().foregroundStyle(Palette.ink)
                    if let d = s.sleep.differenceFromAverage, abs(d) >= 10 * 60 {
                        Text("\(Fmt.duration(abs(d))) \(d >= 0 ? "more" : "less") than usual").font(.caption).foregroundStyle(Palette.secondaryInk)
                    } else {
                        Text("Close to your usual").font(.caption).foregroundStyle(Palette.secondaryInk)
                    }
                    if n.hasStages { SleepTimelineView(night: n, height: 44, compact: true) }
                } else {
                    Text("No sleep recorded").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("From Apple Watch or a sleep app").font(.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .card(padding: Space.l, tone: .tinted(Palette.sleep))
        }
        .buttonStyle(.plain)
    }

    func weightTile(_ s: HealthSnapshot, units: UnitSystem) -> some View {
        Button { router.sheet = .weight } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "Weight trend", icon: "bl.weight", color: Palette.weight)
                if let w = s.weight {
                    Text(Fmt.weight(w.trendNow, units: units)).font(Typo.number(24)).monospacedDigit().foregroundStyle(Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(w.change30Days.map { "\(Fmt.weightChange($0, units: units)) in 30 days" } ?? "\(w.sampleCount) readings")
                        .font(.caption).foregroundStyle(Palette.secondaryInk)
                    Sparkline(values: w.points.suffix(45).map(\.trend), color: Palette.weight).frame(height: 40)
                } else {
                    Text("No weight data").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("From a smart scale or manual entries").font(.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .card(padding: Space.l, tone: .tinted(Palette.weight))
        }
        .buttonStyle(.plain)
    }

    func noteTile(_ note: HealthEvent, today: LocalDate) -> some View {
        Button { router.open(.body(note.id), snapshot: app.snapshot) } label: {
            HStack(spacing: Space.m) {
                BLIcon(name: "bl.bodynote", size: 22)
                    .foregroundStyle(Palette.note)
                    .frame(width: 44, height: 44)
                    .background(Palette.noteSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Body note · \(note.bodyRegion?.displayName ?? "General")", color: Palette.note)
                    Text(note.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                    Text("\(Fmt.dayLabel(note.date)) · \(note.isActive(on: today) ? "unresolved" : "resolved")")
                        .font(.caption).foregroundStyle(Palette.secondaryInk)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
            .card(padding: Space.l, tone: .tinted(Palette.note))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the note on the body map")
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
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text("Milestones").font(Typo.display).foregroundStyle(Palette.ink)
                            Text("Each one is a fact from your own records, with the day it became true. Nothing expires and nothing resets.")
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        BlithMascot(pose: .celebrating, size: 72)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Space.l)], spacing: Space.xl) {
                        ForEach(app.achievements) { AchievementBadge(achievement: $0, size: 72) }
                    }
                    .card(padding: Space.xl)
                }
                .padding(Space.page)
            }
            .blithBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
