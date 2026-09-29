import BlithCore
import SwiftUI

/// The last 24 hours on one line: movement rising above the axis, sleep stages hanging below it,
/// now at the right edge. Older hours are quieter than recent ones. Hours with no record draw
/// nothing, so a missing hour never looks like a still one.
struct DayRibbon: View {
    let ctx: AnalyticsContext
    var height: CGFloat = 104

    struct HourBar: Identifiable {
        let start: Date
        let steps: Double
        var id: Date { start }
    }

    var span: (start: Date, end: Date) { (ctx.now.addingTimeInterval(-24 * 3600), ctx.now) }

    var bars: [HourBar] {
        var out: [HourBar] = []
        for day in [ctx.yesterday, ctx.today] {
            guard let hours = ctx.history.hourlySteps[day] else { continue }
            let dayStart = day.startDate(in: ctx.calendar)
            for i in 0..<24 {
                guard let start = ctx.calendar.date(byAdding: .hour, value: i, to: dayStart),
                      start.addingTimeInterval(3600) > span.start, start < span.end, hours.values[i] > 0 else { continue }
                out.append(HourBar(start: start, steps: hours.values[i]))
            }
        }
        return out
    }

    var segments: [SleepSegment] {
        [ctx.yesterday, ctx.today].compactMap { ctx.history.sleepNights[$0] }
            .flatMap(\.segments)
            .filter { $0.stage != .inBed && $0.end > span.start && $0.start < span.end }
    }

    var asleep: TimeInterval {
        SleepNight.unionDuration(segments.filter { $0.stage.isAsleep }.map { seg in
            var s = seg
            s.start = max(seg.start, span.start)
            s.end = min(seg.end, span.end)
            return s
        })
    }

    var steps: Double { bars.reduce(0) { $0 + $1.steps } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Last 24 hours", icon: "bl.progress")
                Spacer()
                legend(Palette.sleep, "Sleep")
                legend(Palette.signal, "Steps")
            }
            ribbon.frame(height: height)
            HStack(spacing: Space.l) {
                figure(asleep > 0 ? Fmt.duration(asleep) : "–", "asleep")
                figure(steps > 0 ? Fmt.int(steps) : "–", "steps")
                Spacer()
            }
        }
        .card(padding: Space.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 24 hours")
        .accessibilityValue("\(asleep > 0 ? "Asleep \(Fmt.duration(asleep))" : "No sleep recorded"), \(Fmt.int(steps)) steps")
    }

    func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text.uppercased()).font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
        }
    }

    func figure(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(Typo.number(20)).foregroundStyle(Palette.ink)
            Text(unit).font(Typo.geist(13, relativeTo: .footnote)).foregroundStyle(Palette.secondaryInk)
        }
    }

    var ribbon: some View {
        let bars = self.bars
        let segments = self.segments
        let peak = max(bars.map(\.steps).max() ?? 1, 1)
        let total = span.end.timeIntervalSince(span.start)
        return Canvas { ctx, size in
            let axisY = size.height * 0.56
            let labelH: CGFloat = 12
            let sleepH = size.height - axisY - labelH - 6
            func x(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(span.start) / total) * size.width }

            // Axis and 6-hour gridlines on clock hours, with labels.
            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: axisY)); grid.addLine(to: CGPoint(x: size.width, y: axisY))
            ctx.stroke(grid, with: .color(Palette.hairline), lineWidth: 1)
            var mark = self.ctx.calendar.dateInterval(of: .hour, for: span.start)?.end ?? span.start
            while mark < span.end {
                let hour = self.ctx.calendar.component(.hour, from: mark)
                if hour % 6 == 0 {
                    let px = x(mark)
                    var p = Path()
                    p.move(to: CGPoint(x: px, y: 0)); p.addLine(to: CGPoint(x: px, y: size.height - labelH - 2))
                    ctx.stroke(p, with: .color(Palette.hairline), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    let label = hour == 0 ? "12A" : hour == 12 ? "12P" : hour < 12 ? "\(hour)A" : "\(hour - 12)P"
                    ctx.draw(Text(label).font(Typo.mono(9)).foregroundStyle(Palette.tertiaryInk),
                             at: CGPoint(x: px, y: size.height - labelH / 2), anchor: .center)
                }
                mark = mark.addingTimeInterval(3600)
            }

            // Movement: one bar per hour, brighter as it gets closer to now.
            let slot = size.width / 24
            for b in bars {
                let h = max(2, CGFloat(b.steps / peak) * (axisY - 4))
                let rect = CGRect(x: x(b.start) + 1, y: axisY - h - 1, width: max(2, slot - 2), height: h)
                let recency = b.start.timeIntervalSince(span.start) / total
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Palette.signal.opacity(0.35 + 0.65 * recency)))
            }

            // Sleep: a small hypnogram hanging below the axis (awake highest, deep lowest).
            for seg in segments {
                let lane: CGFloat = switch seg.stage {
                case .awake: 0
                case .rem: 1
                case .core, .asleepUnspecified: 2
                case .deep: 3
                case .inBed: 2
                }
                let laneH = sleepH / 4
                let x0 = x(max(seg.start, span.start)), x1 = x(min(seg.end, span.end))
                let rect = CGRect(x: x0, y: axisY + 4 + lane * laneH, width: max(1.5, x1 - x0), height: laneH - 1)
                let style: SleepStageStyle = switch seg.stage {
                case .awake: .awake
                case .rem: .rem
                case .deep: .deep
                default: .core
                }
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Palette.sleep(style)))
            }

            // Now.
            let nowX = size.width - 1
            ctx.fill(Path(ellipseIn: CGRect(x: nowX - 4, y: axisY - 4, width: 8, height: 8)), with: .color(Palette.ink))
        }
        .accessibilityHidden(true)
    }
}
