import BlithCore
import Charts
import SwiftUI

/// Maps a structured assistant block to a trusted native component. The model can only pick
/// from these; it never produces UI. Every block is tappable and opens the matching screen.
struct ChatBlockView: View {
    let block: AssistantBlock
    let open: (DeepLink) -> Void
    @Environment(AppModel.self) private var app

    var units: UnitSystem { app.profile.units }

    var body: some View {
        Button {
            if let link = block.link { open(link) }
        } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                content
                if block.link != nil {
                    HStack(spacing: Space.xs) {
                        Text(openLabel).font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
            .card(padding: Space.l)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.separator.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityHint(openLabel)
    }

    var openLabel: String {
        switch block.link {
        case .walk?: "Open in Walk"
        case .sleep?: "Open sleep"
        case .weight?: "Open weight"
        case .insight?: "See why"
        case .sources?: "Open sources"
        case .today?, nil: "Open"
        }
    }

    @ViewBuilder
    var content: some View {
        switch block {
        case .stepChart(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Steps · \(b.title)", symbol: "figure.walk")
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.int(b.average ?? 0)).font(Typo.number(28)).monospacedDigit()
                    Text(b.period == .day ? "so far" : "avg / day").foregroundStyle(.secondary)
                    Spacer()
                    if let c = b.change { DeltaBadge(change: c) }
                }
                StepHistoryChart(buckets: b.buckets, unit: b.bucketUnit, average: b.period == .day ? nil : b.average, height: 150, interactive: false)
                if b.bucketUnit == .day && b.buckets.count <= 7 {
                    HStack(spacing: 0) {
                        ForEach(b.buckets) { bucket in
                            VStack(spacing: 2) {
                                Text(Fmt.weekdayShort[bucket.start.weekday - 1]).font(.caption2).foregroundStyle(.secondary)
                                Text(bucket.value.map { Fmt.decimal($0 / 1000) + "k" } ?? "—").font(.caption.weight(.semibold)).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        case .walkingSummary(let b):
            VStack(alignment: .leading, spacing: Space.m) {
                header("Walking", symbol: "figure.walk")
                HStack {
                    StatTile(title: "Today", value: b.todaySteps.map(Fmt.int) ?? "—", caption: b.usualByNow.map { "usual by now \(Fmt.int($0))" })
                    StatTile(title: "7-day avg", value: b.average7.map(Fmt.int) ?? "—", caption: b.changeVsBaseline.map { "\(Fmt.signedPercent($0)) vs 4-wk" })
                    StatTile(title: "30-day avg", value: b.average30.map(Fmt.int) ?? "—")
                }
                Chart {
                    ForEach(b.last7, id: \.date) { d in
                        BarMark(x: .value("Day", Fmt.weekdayShort[d.date.weekday - 1]), y: .value("Steps", d.value))
                            .foregroundStyle(Palette.accent.gradient)
                            .cornerRadius(4)
                    }
                    if let base = b.baseline28 {
                        RuleMark(y: .value("Baseline", base))
                            .foregroundStyle(Palette.baseline)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
            }
        case .weightChart(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Weight", symbol: "scalemass", color: Palette.weight)
                HStack {
                    StatTile(title: "Latest", value: Fmt.weight(b.latest, units: units))
                    StatTile(title: "Trend", value: Fmt.weight(b.trend, units: units))
                    StatTile(title: "30 days", value: b.change30.map { Fmt.weightChange($0, units: units) } ?? "—")
                }
                WeightTrendChart(points: b.points, goalKg: b.goalKg, units: units, height: 140, interactive: false)
            }
        case .sleepTimeline(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Sleep · \(Fmt.dayLabel(b.night.date))", symbol: "bed.double", color: Palette.sleepDeep)
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(Fmt.duration(b.asleep)).font(Typo.number(28)).monospacedDigit()
                    if let d = b.differenceFromAverage {
                        Text("\(Fmt.duration(abs(d))) \(d >= 0 ? "more" : "less") than usual").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                SleepTimelineView(night: b.night, height: 90)
            }
        case .workouts(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Workouts", symbol: "figure.mixed.cardio")
                WorkoutList(workouts: b.workouts, units: units)
            }
        case .comparison(let b):
            VStack(alignment: .leading, spacing: Space.m) {
                header("\(b.metric.displayName) · daily average", symbol: "arrow.left.arrow.right")
                HStack(alignment: .bottom, spacing: Space.l) {
                    comparisonColumn(b.labelA, b.valueA, b.metric, max(b.valueA, b.valueB), highlight: true)
                    comparisonColumn(b.labelB, b.valueB, b.metric, max(b.valueA, b.valueB), highlight: false)
                }
                if let c = b.change { DeltaBadge(change: c, caption: "vs \(b.labelB)") }
            }
        case .metricCard(let b):
            VStack(alignment: .leading, spacing: Space.xs) {
                header(b.title, symbol: "number")
                Text(Fmt.value(b.value, metric: b.metric, units: units)).font(Typo.number(28)).monospacedDigit()
                Text(b.caption).font(.subheadline).foregroundStyle(.secondary)
            }
        case .insight(let i):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Insight", symbol: "sparkle")
                Text(i.headline).font(Typo.cardTitle)
                if let e = i.emphasis {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(e).font(Typo.number(24))
                        if let c = i.emphasisCaption { Text(c).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                Text(i.explanation).font(.subheadline).foregroundStyle(.secondary)
            }
        case .sources(let b):
            VStack(alignment: .leading, spacing: Space.s) {
                header("Sources · \(b.metric.displayName)", symbol: "square.stack.3d.up")
                let total = b.sources.reduce(0) { $0 + $1.value }
                ForEach(b.sources) { s in
                    HStack {
                        Text(s.source.name).font(.subheadline)
                        Spacer()
                        Text(total > 0 ? Fmt.percent(s.value / total) : "—").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
    }

    func header(_ title: String, symbol: String, color: Color = Palette.accent) -> some View {
        Label(title, systemImage: symbol)
            .font(Typo.eyebrow)
            .foregroundStyle(color)
    }

    func comparisonColumn(_ label: String, _ value: Double, _ metric: HealthMetric, _ maxValue: Double, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlight ? AnyShapeStyle(Palette.accent.gradient) : AnyShapeStyle(Palette.baseline.opacity(0.5)))
                .frame(height: max(8, 80 * (maxValue > 0 ? value / maxValue : 0)))
            Text(Fmt.value(value, metric: metric, units: units)).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
