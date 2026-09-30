import BlithCore
import SwiftUI

extension HeartZone {
    var color: Color {
        switch self {
        case .resting: Palette.mint
        case .warm: Palette.cyan
        case .elevated: Palette.amber
        case .hard: Palette.coral
        case .peak: Palette.heart
        }
    }
}

/// Carries the beat phase between frames and eases the rate toward each new reading, so the heart
/// speeds up and slows down smoothly instead of jumping when a new sample arrives.
final class BeatClock {
    private(set) var phase = 0.0
    private(set) var bpm = 70.0
    private var last: Date?

    func advance(to now: Date, target: Double) -> (phase: Double, bpm: Double) {
        guard let last else {
            self.last = now
            bpm = target
            return (phase, bpm)
        }
        let dt = min(0.25, max(0, now.timeIntervalSince(last)))
        self.last = now
        bpm += (target - bpm) * min(1, dt / 0.8)
        phase = (phase + dt * bpm / 60).truncatingRemainder(dividingBy: 1)
        return (phase, bpm)
    }
}

/// Live heart rate: the heart pounds at exactly the measured BPM (a "lub-dub" every 60/BPM seconds)
/// and harder as the rate climbs above the person's resting rate; the ECG trace's spacing follows
/// the same rate. Honest about freshness: LIVE under 90 s, otherwise how long ago the reading was.
struct LiveHeartCard: View {
    let live: LiveHeartRate
    var isDemo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = BeatClock()

    private let heartArea: CGFloat = 132
    private let ecgHeight: CGFloat = 58

    var body: some View {
        let summary = live.summary()
        VStack(alignment: .leading, spacing: Space.m) {
            header(summary)
            switch live.status {
            case .ready where summary.latest != nil:
                pounding(summary)
                stats(summary)
                caption(summary)
            default:
                emptyState
            }
        }
        .card(padding: Space.l, tone: .tinted(Palette.heart))
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    func header(_ s: LiveHeartSummary) -> some View {
        HStack {
            Eyebrow(text: "Live heart rate", icon: "bl.heart", color: Palette.heart)
            Spacer()
            if live.isSimulated { MonoPill(text: "Sample", color: Palette.amber) }
            if live.status == .ready, s.latest != nil { freshnessBadge }
        }
    }

    /// Re-evaluated every few seconds so "LIVE" turns into "2 MIN AGO" without a new reading.
    var freshnessBadge: some View {
        TimelineView(.periodic(from: .now, by: 5)) { tl in
            let s = live.summary(now: tl.date)
            let age = s.age(now: tl.date) ?? 0
            HStack(spacing: 5) {
                Circle().fill(color(for: s.freshness)).frame(width: 6, height: 6)
                    .opacity(s.freshness == .live && !reduceMotion ? (Int(tl.date.timeIntervalSinceReferenceDate) % 2 == 0 ? 1 : 0.35) : 1)
                Text(badgeText(s.freshness, age: age)).font(Typo.eyebrow).tracking(1.1)
            }
            .foregroundStyle(color(for: s.freshness))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color(for: s.freshness).opacity(0.14)))
            .accessibilityLabel(s.freshness == .live ? "Live" : "Last reading \(ageText(age)) ago")
        }
    }

    func color(for f: LiveHeartSummary.Freshness) -> Color {
        switch f {
        case .live: Palette.mint
        case .recent: Palette.amber
        case .stale, .none: Palette.secondaryInk
        }
    }

    func badgeText(_ f: LiveHeartSummary.Freshness, age: TimeInterval) -> String {
        f == .live ? "LIVE" : "\(ageText(age).uppercased()) AGO"
    }

    func ageText(_ age: TimeInterval) -> String {
        switch age {
        case ..<90: "\(Int(age)) s"
        case ..<3600: "\(Int((age / 60).rounded())) min"
        case ..<86_400: "\(Int((age / 3600).rounded())) h"
        default: "\(Int((age / 86_400).rounded())) d"
        }
    }

    // MARK: The pounding heart and ECG

    func pounding(_ s: LiveHeartSummary) -> some View {
        let bpm = s.bpm ?? 70
        let zone = s.zone
        // Pound while the reading is fresh enough to mean something; hold still once it's old.
        let animating = !reduceMotion && scenePhase == .active && s.freshness != .stale
        return ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { tl in
                let beat = animating ? clock.advance(to: tl.date, target: bpm) : (phase: 0.86, bpm: bpm)
                Canvas { ctx, size in
                    drawHeart(&ctx, size: size, phase: beat.phase, intensity: s.intensity, freshness: s.freshness)
                    drawECG(&ctx, size: size, phase: beat.phase, bpm: beat.bpm, color: zone.color, animating: animating)
                }
                .frame(height: heartArea + ecgHeight + Space.s)
            }
            HStack(alignment: .center, spacing: 0) {
                Spacer().frame(width: heartArea + Space.s)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(bpm.rounded()))")
                            .font(Typo.score(76)).foregroundStyle(Palette.ink)
                            .monospacedDigit().contentTransition(.numericText())
                        Text("BPM").font(Typo.eyebrow).tracking(1.2).foregroundStyle(Palette.secondaryInk)
                    }
                    HStack(spacing: Space.s) {
                        MonoPill(text: zone.label, color: zone.color, filled: zone >= .hard)
                        if let above = s.aboveResting {
                            Text(above >= 3 ? "\(Int(above.rounded())) above resting" : "at resting")
                                .font(.caption).foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: heartArea)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate \(Int(bpm.rounded())) beats per minute, \(zone.label.lowercased()) zone")
        .accessibilityValue(s.freshness == .live ? "Live" : "Last reading \(ageText(s.age(now: Date()) ?? 0)) ago")
    }

    func drawHeart(_ ctx: inout GraphicsContext, size: CGSize, phase: Double, intensity: Double, freshness: LiveHeartSummary.Freshness) {
        let thump = HeartWaveform.thump(phase: phase)
        let dim = freshness == .live ? 1.0 : (freshness == .recent ? 0.9 : 0.6)
        let center = CGPoint(x: heartArea / 2, y: heartArea / 2)
        let radius: CGFloat = 40
        // Harder beats at higher intensity: the heart swells more.
        let swell = 0.09 + 0.15 * intensity
        let scale = 1 + swell * thump
        // One bright red heart in every zone and appearance.
        let red = Self.heartRed

        // The glow underlay only shows when nothing is being monitored; while a reading is live or
        // recent the heart stands on its own.
        if freshness == .stale {
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius * 2.1, y: center.y - radius * 2.1, width: radius * 4.2, height: radius * 4.2)),
                     with: .radialGradient(Gradient(colors: [red.opacity(0.18), .clear]),
                                           center: center, startRadius: 0, endRadius: radius * 1.7))
        }

        var heart = Self.heartPath(center: center, halfWidth: radius * scale)
        ctx.fill(heart, with: .color(red.opacity(dim)))
        // A soft highlight on the upper left lobe.
        heart = Self.heartPath(center: CGPoint(x: center.x - radius * 0.34, y: center.y - radius * 0.34), halfWidth: radius * 0.22 * scale)
        ctx.fill(heart, with: .color(.white.opacity(0.22 * dim)))
    }

    /// The bright red of the heart, the same in light and dark mode.
    static let heartRed = Color(red: 1, green: 0.16, blue: 0.2)

    /// The classic parametric heart, centred and scaled to `halfWidth`.
    static func heartPath(center: CGPoint, halfWidth: CGFloat) -> Path {
        let s = halfWidth / 16
        var p = Path()
        for i in 0...96 {
            let t = Double(i) / 96 * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
            let pt = CGPoint(x: center.x + CGFloat(x) * s, y: center.y + (CGFloat(y) - 4.4) * s)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    func drawECG(_ ctx: inout GraphicsContext, size: CGSize, phase: Double, bpm: Double, color: Color, animating: Bool) {
        let top = heartArea + Space.s
        let w = size.width
        let baseline = top + ecgHeight * 0.70
        let window = 3.2 // seconds of trace on screen; the R spikes sit 60/bpm seconds apart
        var grid = Path()
        grid.move(to: CGPoint(x: 0, y: baseline))
        grid.addLine(to: CGPoint(x: w, y: baseline))
        ctx.stroke(grid, with: .color(Palette.hairline), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

        var trace = Path()
        var x: CGFloat = 0
        while x <= w {
            let age = Double((w - x) / w) * window
            let ph = phase - age * bpm / 60
            let y = baseline - CGFloat(HeartWaveform.ecg(phase: ph)) * ecgHeight * 0.62
            if x == 0 { trace.move(to: CGPoint(x: x, y: y)) } else { trace.addLine(to: CGPoint(x: x, y: y)) }
            x += 2
        }
        let fade = Gradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(0.9), location: 0.55), .init(color: color, location: 1)])
        let glow = Gradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(0.22), location: 1)])
        ctx.stroke(trace, with: .linearGradient(glow, startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                   style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        ctx.stroke(trace, with: .linearGradient(fade, startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        // The pen: a bright dot at the leading edge of the trace.
        let ny = baseline - CGFloat(HeartWaveform.ecg(phase: phase)) * ecgHeight * 0.62
        ctx.fill(Path(ellipseIn: CGRect(x: w - 9, y: ny - 9, width: 18, height: 18)), with: .radialGradient(Gradient(colors: [color.opacity(0.8), .clear]), center: CGPoint(x: w - 1, y: ny), startRadius: 0, endRadius: 9))
        ctx.fill(Path(ellipseIn: CGRect(x: w - 4, y: ny - 3, width: 6, height: 6)), with: .color(.white))
    }

    // MARK: Stats

    func stats(_ s: LiveHeartSummary) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            stat("Resting", s.resting.map { "\(Int($0.rounded()))" })
            divider
            stat("Low today", s.minToday.map { "\(Int($0.rounded()))" })
            divider
            stat("High today", s.maxToday.map { "\(Int($0.rounded()))" })
            divider
            VStack(alignment: .leading, spacing: 3) {
                Text("LAST HOUR").font(Typo.eyebrow).tracking(1).foregroundStyle(Palette.secondaryInk)
                if s.lastHour.count >= 3 {
                    MiniSpark(values: s.lastHour.map(\.bpm), color: Palette.heart).frame(height: 26)
                } else {
                    Text("–").font(Typo.number(18)).foregroundStyle(Palette.tertiaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var divider: some View { Rectangle().fill(Palette.hairline).frame(width: 1, height: 30) }

    func stat(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(Typo.eyebrow).tracking(1).foregroundStyle(Palette.secondaryInk).lineLimit(1).minimumScaleFactor(0.8)
            Text(value ?? "–").font(Typo.number(22)).foregroundStyle(Palette.ink).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    func caption(_ s: LiveHeartSummary) -> some View {
        if s.freshness == .live {
            Text("Updating as Health receives new readings.").font(.caption2).foregroundStyle(Palette.tertiaryInk)
        } else {
            Text("Apple Watch records heart rate every few minutes at rest. Start a Workout on your watch for a reading every few seconds.")
                .font(.caption2).foregroundStyle(Palette.tertiaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Empty states

    @ViewBuilder
    var emptyState: some View {
        HStack(alignment: .center, spacing: Space.l) {
            Canvas { ctx, size in
                drawHeart(&ctx, size: size, phase: 0.86, intensity: 0, freshness: .stale)
            }
            .frame(width: heartArea, height: heartArea)
            .scaleEffect(0.7)
            .frame(width: heartArea * 0.7, height: heartArea * 0.7)
            VStack(alignment: .leading, spacing: Space.s) {
                switch live.status {
                case .needsAccess:
                    Text("See your heart rate live").font(.headline).foregroundStyle(Palette.ink)
                    Text("Allow Blith to read heart rate from Apple Health. It stays on this iPhone.").font(.subheadline).foregroundStyle(Palette.secondaryInk)
                    Button { Task { await live.requestAccess() } } label: {
                        Label("Allow heart rate", systemImage: "heart.fill").font(.subheadline.weight(.semibold))
                    }
                    .glassButton(prominent: true)
                case .unavailable:
                    Text("Heart rate isn't available").font(.headline).foregroundStyle(Palette.ink)
                    Text("Health data isn't available on this device.").font(.subheadline).foregroundStyle(Palette.secondaryInk)
                case .idle:
                    Text("Listening for your heart…").font(.headline).foregroundStyle(Palette.ink)
                default:
                    Text("No heart rate in the last 24 hours").font(.headline).foregroundStyle(Palette.ink)
                    Text("Wear your Apple Watch, or start a Workout on it, and readings appear here as soon as Health receives them. If you've already allowed access, check Settings › Health › Data Access › Blith.")
                        .font(.footnote).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
