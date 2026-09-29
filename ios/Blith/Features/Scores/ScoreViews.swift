import BlithCore
import Charts
import SwiftUI

/// Readiness for one day: the dial, every factor against the person's usual, the last 30 days and
/// how the score is built.
struct ReadinessDetailView: View {
    let date: LocalDate?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LocalDate?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = app.snapshot {
                    content(s).padding(Space.page)
                }
            }
            .scrollIndicators(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Readiness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    func content(_ s: HealthSnapshot) -> some View {
        let day = selected ?? date ?? s.ctx.today
        let engine = ScoreEngine(s.ctx)
        let r = engine.readiness(on: day)
        let color = Palette.band(r.band)
        VStack(alignment: .leading, spacing: Space.l) {
            WeekStrip(days: Array(s.scoreHistory.suffix(7)), selected: day) { d in withAnimation(Motion.standard) { selected = d } }
                .card(padding: Space.m)
            VStack(spacing: Space.m) {
                Eyebrow(text: Fmt.dayLabel(day))
                ScoreDial(fraction: r.score.map { Double($0) / 100 }, valueText: r.score.map(String.init) ?? "\(r.calibrationDays)",
                          unit: r.score == nil ? "/\(ScoreEngine.calibrationDays)" : "%", label: r.score == nil ? "Calibrating" : "Readiness",
                          color: r.score == nil ? Palette.secondaryInk : color, size: 190)
                    .id(day)
                if let b = r.band { BandChip(band: b, label: "\(b.label) readiness · \(b == .high ? "67–100" : b == .moderate ? "34–66" : "0–33")") }
                Text(r.summary).font(Typo.story).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card(padding: Space.xl, tone: .hero)

            if !r.factors.isEmpty {
                VStack(alignment: .leading, spacing: Space.l) {
                    SectionHeader(title: "Why this score", subtitle: "Each signal against your own last 30 days")
                    ForEach(r.factors) { FactorRow(factor: $0, color: color) }
                }
                .card(padding: Space.l)
            }

            trend(s)

            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "Last 13 weeks")
                ScoreHeatmap(days: s.scoreHistory, mode: .readiness, selected: day) { d in withAnimation(Motion.standard) { selected = d } }
                HStack(spacing: Space.l) {
                    legend(Palette.band(.high), "High")
                    legend(Palette.band(.moderate), "Moderate")
                    legend(Palette.band(.low), "Low")
                    legend(nil, "No score")
                }
            }
            .card(padding: Space.l)

            KeyValueCard(title: "How readiness works", rows: [
                ("Heart rate variability", "50% · vs your 30-day log average"),
                ("Resting heart rate", "20% · lower than usual scores higher"),
                ("Sleep performance", "30% · hours vs need, efficiency, stages"),
                ("Respiratory rate", "−5 if well above your usual"),
                ("Calibration", "\(ScoreEngine.calibrationDays) nights of heart data"),
            ])
            Text("Readiness describes overnight signals relative to your own history. It isn't a medical assessment and can't tell you why a signal changed.")
                .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.tertiaryInk)
        }
    }

    func legend(_ c: Color?, _ t: String) -> some View {
        HStack(spacing: 5) {
            Group {
                if let c { RoundedRectangle(cornerRadius: 3).fill(c) } else { RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.hairline, lineWidth: 1) }
            }
            .frame(width: 10, height: 10)
            Text(t.uppercased()).font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
        }
    }

    @ViewBuilder
    func trend(_ s: HealthSnapshot) -> some View {
        let days = s.scoreHistory.suffix(30).filter { $0.readiness != nil }
        if days.count >= 5 {
            let avg = Stats.mean(days.compactMap(\.readiness).map(Double.init)) ?? 0
            VStack(alignment: .leading, spacing: Space.m) {
                SectionHeader(title: "30 days", subtitle: "Average \(Fmt.int(avg))")
                Chart {
                    ForEach(Array(days)) { d in
                        BarMark(x: .value("Day", d.date.chartDate, unit: .day), y: .value("Readiness", d.readiness ?? 0))
                            .foregroundStyle(Palette.band(d.band))
                            .cornerRadius(2)
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 33, 66, 100]) { _ in AxisGridLine().foregroundStyle(Palette.hairline); AxisValueLabel().font(Typo.mono(10)).foregroundStyle(Palette.tertiaryInk) } }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(Typo.mono(10)).foregroundStyle(Palette.tertiaryInk) } }
                .frame(height: 160)
            }
            .card(padding: Space.l)
        }
    }
}

/// One vital over time with the person's own range.
struct VitalDetailView: View {
    let metric: HealthMetric
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = app.snapshot { content(s).padding(Space.page) }
            }
            .background(Palette.canvas)
            .navigationTitle(metric.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    func content(_ s: HealthSnapshot) -> some View {
        let days = metric == .vo2Max ? 180 : 60
        let values = s.ctx.history.values(metric, in: s.ctx.trailing(days)).map { DayValue(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        let reading = ScoreEngine(s.ctx).vital(metric, on: s.ctx.today)
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: metric == .vo2Max ? "Latest estimate" : "Last night", icon: metric.icon, color: metric.tint)
                Text((reading.value ?? values.last?.value).map { metric.format($0) } ?? "–")
                    .font(Typo.score(64)).foregroundStyle(Palette.ink).monospacedDigit()
                if let r = reading.range {
                    Text("Your range \(metric.format(r.lowerBound)) – \(metric.format(r.upperBound)) · average \(reading.mean.map { metric.format($0) } ?? "–")")
                        .font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                }
            }
            if values.count >= 3 {
                Chart {
                    if let r = reading.range, metric != .vo2Max {
                        RectangleMark(xStart: .value("Start", values.first!.date.chartDate), xEnd: .value("End", values.last!.date.chartDate),
                                      yStart: .value("Low", r.lowerBound), yEnd: .value("High", r.upperBound))
                            .foregroundStyle(metric.tint.opacity(0.12))
                    }
                    ForEach(values, id: \.date) { v in
                        LineMark(x: .value("Day", v.date.chartDate), y: .value(metric.shortName, v.value))
                            .foregroundStyle(metric.tint.opacity(0.8))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", v.date.chartDate), y: .value(metric.shortName, v.value))
                            .foregroundStyle(reading.range.map { $0.contains(v.value) } ?? true ? metric.tint : Palette.amber)
                            .symbolSize(18)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Palette.hairline); AxisValueLabel().font(Typo.mono(10)).foregroundStyle(Palette.tertiaryInk) } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(Typo.mono(10)).foregroundStyle(Palette.tertiaryInk) } }
                .frame(height: 200)
                .card(padding: Space.l)
            } else {
                EmptyStateView(symbol: metric.icon, title: "Not enough readings", message: "This appears once a few nights of \(metric.shortName.lowercased()) are recorded.")
            }
            Text(about).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk).card(padding: Space.l)
            Text("Your range is your own recent history (±1.5 standard deviations over 30 days). A reading outside it isn't a diagnosis; if something feels wrong, talk to a clinician.")
                .font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.tertiaryInk)
        }
    }

    var about: String {
        switch metric {
        case .restingHeartRate: "Resting heart rate is your heart rate while fully at rest, usually measured overnight. It tends to rise with short sleep, hard training days, heat, alcohol or illness."
        case .hrv: "Heart rate variability (SDNN) is the variation in time between heartbeats, measured overnight by Apple Watch. Higher than your usual generally reflects a more rested nervous system. It varies a lot between people, so only your own trend matters."
        case .respiratoryRate: "Breaths per minute while you sleep. It's usually very stable for a person, so a change of more than about one breath per minute is worth noticing."
        case .oxygenSaturation: "Blood oxygen measured by Apple Watch, mostly overnight. Readings vary with fit and movement; single low readings are common and usually not meaningful."
        case .wristTemperature: "Apple Watch measures wrist temperature while you sleep. Only the change from your own baseline is meaningful; it can shift with room temperature, the menstrual cycle or illness."
        case .vo2Max: "Cardio fitness (VO₂ max) is Apple Watch's estimate of how much oxygen your body can use during exercise, from outdoor walks, runs and hikes. It changes slowly over weeks."
        default: metric.displayName
        }
    }
}
