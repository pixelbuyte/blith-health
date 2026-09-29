import BlithCore
import SwiftUI

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
