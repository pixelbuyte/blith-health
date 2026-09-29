import BlithCore
import SwiftUI

/// "What should I know about myself today?" — one movement hero, a few ranked insights,
/// weight and sleep context when they exist, and a gentle week view. Not a tile wall.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    header
                    if app.isDemo { SampleDataBanner() }
                    if let s = app.snapshot {
                        content(s)
                    } else {
                        EmptyStateView(symbol: "heart.text.square", title: "Connect Apple Health",
                                       message: "Connect Apple Health to start building your personal baseline.",
                                       actionTitle: "Open settings") { router.sheet = .profile }
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.section)
            }
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Palette.background
                    LinearGradient(colors: [Palette.heroGradientTop, Palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 420)
                }
                .ignoresSafeArea()
            }
            .refreshable { await app.refresh(force: true) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: AppClock.now())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let name = app.profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppClock.now().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                        .font(Typo.eyebrow)
                        .foregroundStyle(.secondary)
                    Text(greeting)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                AvatarButton(name: app.profile.name) { router.sheet = .profile }
            }
            if let headline = app.snapshot?.headline {
                Text(headline)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .padding(.top, Space.l)
    }

    @ViewBuilder
    func content(_ s: HealthSnapshot) -> some View {
        movementHero(s)
        if !s.feed.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "Worth knowing")
                ForEach(s.feed) { insight in
                    InsightCard(insight: insight) { router.sheet = .insight(insight) }
                }
            }
        } else if s.ctx.history.values(.steps, in: s.ctx.trailing(28)).count < 7 {
            EmptyStateView(symbol: "hourglass", title: "Learning your normal",
                           message: "We need a few more days before we can understand your normal walking pattern. Insights appear once there's a meaningful change against your own baseline.")
        }
        if let consistency = s.consistency {
            weekCard(consistency)
        }
        weightSection(s)
        sleepSection(s)
        if let history = app.history {
            SyncStatusLine(history: history, isSyncing: app.isSyncing)
        }
    }

    // MARK: Movement hero

    func movementHero(_ s: HealthSnapshot) -> some View {
        Button { router.open(.walk(.day), snapshot: s) } label: {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Movement", systemImage: "figure.walk").font(Typo.eyebrow).foregroundStyle(Palette.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.int(s.todaySteps ?? 0))
                        .font(Typo.number(heroSize))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("steps today").font(.headline).foregroundStyle(.secondary)
                }
                if let pace = s.pace, let change = pace.change {
                    DeltaBadge(change: change, caption: pace.basis == .sameWeekday ? "vs your usual \(Fmt.weekday(s.ctx.today)) by now" : "vs your usual day by now")
                } else if let usual = s.pace?.usualByNow {
                    Text("Usually around \(Fmt.int(usual)) by this time on a \(Fmt.weekday(s.ctx.today)).")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Your usual pace appears after a few days of history.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let pace = s.pace, !pace.usualCurve.isEmpty {
                    AccumulationChart(pace: pace, compact: true)
                        .frame(height: 130)
                    HStack(spacing: Space.l) {
                        legend(color: Palette.accent, dashed: false, text: "Today")
                        legend(color: Palette.baseline, dashed: true, text: pace.basis == .sameWeekday ? "Usual \(Fmt.weekday(s.ctx.today))" : "Usual day")
                    }
                }
                Divider()
                HStack {
                    StatTile(title: "7-day average", value: s.average7.map { Fmt.int($0.value) } ?? "—", caption: coverage(s.average7, of: 7))
                    StatTile(title: "30-day average", value: s.average30.map { Fmt.int($0.value) } ?? "—", caption: coverage(s.average30, of: 30))
                    if let d = s.todayDistance {
                        StatTile(title: "Distance", value: Fmt.distance(d, units: s.ctx.units))
                    }
                }
            }
            .card(padding: Space.xl)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens walking details")
    }

    /// "3 days of data" when an average covers fewer days than its window.
    func coverage(_ a: AverageResult?, of days: Int) -> String? {
        guard let a, a.days < days else { return nil }
        return "\(a.days) \(a.days == 1 ? "day" : "days") of data"
    }

    func legend(color: Color, dashed: Bool, text: String) -> some View {
        HStack(spacing: Space.xs) {
            Capsule().fill(dashed ? AnyShapeStyle(color.opacity(0.6)) : AnyShapeStyle(color)).frame(width: 14, height: 3)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Week

    func weekCard(_ c: WeekConsistency) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(Typo.cardTitle)
                Spacer()
                Text("\(c.metCount) \(c.metCount == 1 ? "day" : "days") near your usual")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ConsistencyDots(week: c)
            Text(c.thresholdIsGoal ? "Filled days reached your goal of \(Fmt.int(c.threshold)) steps." :
                    "Filled days reached \(Fmt.int(c.threshold)) steps, about 85% of your typical day. Missing a day doesn't reset anything.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: Space.xl)
    }

    // MARK: Weight & sleep

    @ViewBuilder
    func weightSection(_ s: HealthSnapshot) -> some View {
        let units = s.ctx.units
        if let w = s.weight {
            Button { router.sheet = .weight } label: {
                HStack(alignment: .center, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Label("Weight trend", systemImage: "scalemass").font(Typo.eyebrow).foregroundStyle(Palette.weight)
                        Text(Fmt.weight(w.trendNow, units: units)).font(Typo.number(30)).monospacedDigit()
                        if let c = w.change30Days {
                            Text("\(Fmt.weightChange(c, units: units)) over 30 days").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("\(w.sampleCount) readings so far").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if w.isStale {
                            Text("No recent readings").font(.caption).foregroundStyle(Palette.warm)
                        }
                    }
                    Spacer()
                    Sparkline(values: w.points.suffix(45).map(\.trend), color: Palette.weight)
                        .frame(width: 120, height: 56)
                }
                .card(padding: Space.xl)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens weight details")
        } else if s.ctx.profile.goals.contains(.weightManagement) {
            EmptyStateView(symbol: "scalemass", title: "No weight data yet",
                           message: "Connect a source that records weight, like a smart scale or manual entries in Apple Health, to see your trend here.")
        }
    }

    @ViewBuilder
    func sleepSection(_ s: HealthSnapshot) -> some View {
        if let night = s.sleep.lastNight {
            Button { router.sheet = .sleep(night.date) } label: {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("Last night", systemImage: "bed.double").font(Typo.eyebrow).foregroundStyle(Palette.sleepDeep)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(Fmt.duration(night.asleepDuration)).font(Typo.number(30)).monospacedDigit()
                        if let d = s.sleep.differenceFromAverage, abs(d) >= 10 * 60 {
                            Text("\(Fmt.duration(abs(d))) \(d >= 0 ? "more" : "less") than usual").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if night.hasStages {
                        SleepTimelineView(night: night, height: 64)
                    }
                }
                .card(padding: Space.xl)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens sleep details")
        }
    }
}
