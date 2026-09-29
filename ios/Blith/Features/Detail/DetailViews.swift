import BlithCore
import SwiftUI

struct SleepDetailView: View {
    let initialDate: LocalDate?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LocalDate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if app.isDemo { SampleDataBanner() }
                    if let s = app.snapshot, !s.ctx.history.sleepNights.isEmpty {
                        content(s)
                    } else {
                        EmptyStateView(symbol: "bed.double", title: "No sleep data",
                                       message: "Sleep comes from Apple Watch, iPhone Sleep Focus or a sleep app that writes to Apple Health. If you connected Sleep and still see nothing, check Settings › Health › Data Access › Blith.")
                    }
                }
                .padding(Space.page)
            }
            .background(Palette.background)
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    func content(_ s: HealthSnapshot) -> some View {
        let nights = s.ctx.history.sleepNights.values.sorted { $0.date > $1.date }.prefix(14)
        let current = selected.flatMap { s.ctx.history.sleepNights[$0] } ?? initialDate.flatMap { s.ctx.history.sleepNights[$0] } ?? nights.first
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: Space.s) {
                ForEach(Array(nights.reversed())) { n in
                    let isSel = n.date == current?.date
                    Button { selected = n.date } label: {
                        VStack(spacing: Space.xs) {
                            Capsule()
                                .fill(isSel ? AnyShapeStyle(Palette.sleepDeep.gradient) : AnyShapeStyle(Palette.sleepCore.opacity(0.35)))
                                .frame(width: 22, height: max(12, CGFloat(n.asleepDuration / 3600) * 11))
                            Text(Fmt.weekdayShort[n.date.weekday - 1].prefix(2)).font(.caption2).foregroundStyle(isSel ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Fmt.dayLabel(n.date)), \(Fmt.duration(n.asleepDuration))")
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
        if let night = current {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("NIGHT ENDING \(Fmt.dayLabel(night.date).uppercased())").font(Typo.eyebrow).foregroundStyle(.secondary)
                Text(Fmt.duration(night.asleepDuration)).font(Typo.number(44)).monospacedDigit()
                Text("asleep · \(Fmt.duration(night.inBedDuration)) from first to last sample").font(.subheadline).foregroundStyle(.secondary)
                if night.hasStages {
                    SleepTimelineView(night: night)
                    HStack {
                        ForEach([SleepStage.awake, .rem, .core, .deep], id: \.self) { stage in
                            StatTile(title: stage.displayName, value: Fmt.duration(night.duration(of: stage)))
                        }
                    }
                } else {
                    Text("This source records time asleep without stages.").font(.footnote).foregroundStyle(.secondary)
                }
                SourceBadge(text: night.source.name)
            }
            .card(padding: Space.xl)
        }
        let timing = SleepAnalytics.timing(s.ctx, nights: 28)
        if timing.count >= 5 {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "When you slept · last \(timing.count) nights", icon: "bl.sleep", color: Palette.sleep)
                SleepTimingChart(points: timing)
                if let bed = Stats.median(timing.map(\.bedMinutes)), let wake = Stats.median(timing.map(\.wakeMinutes)) {
                    Text("Usually asleep around \(SleepAnalytics.clock(bed)) and up around \(SleepAnalytics.clock(wake)).")
                        .font(.footnote).foregroundStyle(Palette.secondaryInk)
                }
            }
            .card(padding: Space.l)
        }
        VStack(spacing: 0) {
            row("7-night average", s.sleep.average7.map { Fmt.duration($0) })
            Divider()
            row("28-night average", s.sleep.average28.map { Fmt.duration($0) })
            Divider()
            row("Nights recorded (28 days)", "\(s.sleep.nights28)")
            Divider()
            row("Bedtime consistency", s.sleep.bedtimeVariabilityMinutes.map { "±\(Int($0)) min" })
        }
        .card(padding: Space.l)
        Text("Sleep stage estimates come from your devices and aren't a clinical sleep study.")
            .font(.caption).foregroundStyle(.tertiary)
    }

    func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—").fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, Space.m)
    }
}

struct WeightDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var range = 90

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if app.isDemo { SampleDataBanner() }
                    if let s = app.snapshot, let w = s.weight {
                        content(w, units: s.ctx.units)
                    } else {
                        EmptyStateView(symbol: "scalemass", title: "No weight data",
                                       message: "Connect a source that records weight, such as a smart scale, or log weight in Apple Health, to see your trend here.")
                    }
                }
                .padding(Space.page)
            }
            .background(Palette.background)
            .navigationTitle("Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    func content(_ w: WeightTrend, units: UnitSystem) -> some View {
        let cutoff = AppClock.now().addingTimeInterval(-Double(range) * 86_400)
        let points = range == 0 ? w.points : w.points.filter { $0.date >= cutoff }
        VStack(alignment: .leading, spacing: Space.m) {
            Text("SMOOTHED TREND").font(Typo.eyebrow).foregroundStyle(Palette.weight)
            Text(Fmt.weight(w.trendNow, units: units)).font(Typo.number(44)).monospacedDigit()
            if let c = w.change30Days {
                Text("\(Fmt.weightChange(c, units: units)) over 30 days").font(.headline).foregroundStyle(.secondary)
            }
            Picker("Range", selection: $range) {
                Text("30D").tag(30)
                Text("90D").tag(90)
                Text("1Y").tag(365)
                Text("All").tag(0)
            }
            .pickerStyle(.segmented)
            if points.count >= 2 {
                WeightTrendChart(points: points, goalKg: w.goalKg, units: units, height: 240)
            } else {
                Text("Not enough readings in this range.").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: Space.l) {
                legendDot(Palette.baseline.opacity(0.6), "Readings")
                legendLine(Palette.weight, "Trend")
            }
        }
        .card(padding: Space.xl)

        VStack(spacing: 0) {
            row("Latest reading", "\(Fmt.weight(w.latest.value, units: units)) · \(w.latest.date.formatted(date: .abbreviated, time: .omitted))")
            Divider()
            row("Readings this week", w.rangeLast7Days.map { "\(w.readingsLast7Days) · \(Fmt.weight($0.lowerBound, units: units))–\(Fmt.weight($0.upperBound, units: units))" } ?? "\(w.readingsLast7Days)")
            Divider()
            row("Trend change this week", w.trendChangeLast7Days.map { Fmt.weightChange($0, units: units) })
            Divider()
            row("Rate (last 4 weeks)", w.weeklyRate.map { "\(Fmt.weightChange($0, units: units)) / week" })
            Divider()
            row("Since \(w.startDate.formatted(date: .abbreviated, time: .omitted))", Fmt.weightChange(w.changeSinceStart, units: units))
            if let goal = w.goalKg, let d = w.distanceToGoal {
                Divider()
                row("Goal", "\(Fmt.weight(goal, units: units)) · \(Fmt.weight(abs(d), units: units)) \(d > 0 ? "to go" : "below")")
            }
        }
        .card(padding: Space.l)

        Text("Daily readings swing with water, food and timing. The trend line smooths those swings (exponential smoothing with a 7-day time constant), so it moves only when the change is sustained.")
            .font(.footnote).foregroundStyle(.secondary)
        if w.isStale {
            Label("No readings in over \(HealthMetric.weight.staleAfterDays) days.", systemImage: "clock.badge.exclamationmark")
                .font(.footnote).foregroundStyle(Palette.warm)
        }
    }

    func row(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: Space.m)
            Text(value ?? "—").fontWeight(.semibold).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, Space.m)
    }

    func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    func legendLine(_ color: Color, _ text: String) -> some View {
        HStack(spacing: Space.xs) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
