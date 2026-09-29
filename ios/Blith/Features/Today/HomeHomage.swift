import BlithCore
import SwiftUI

// MARK: - Home top designs (v3)
//
// Three reworks of the top of the home screen — the area in the screenshot: status line, greeting,
// the hero, and the block under it. Sample data; nothing here reads HealthKit and nothing in the
// app points at this file yet.
//
// What was wrong with the screen these replace:
//
//   1. The largest element on the screen said "0/14 CALIBRATING" — the most prominent thing was the
//      app admitting it had nothing. Calibration is now a thin strip that states progress once.
//   2. Two of the three dials were empty ("–" sleep), and three of the four chips under them read
//      "–". Empty instruments look broken rather than patient.
//   3. The Health monitor block below spent five tall rows saying "NO READING LAST NIGHT" five
//      times, and the resting-heart row drew a coral bar that reads as an alert with no reading
//      behind it. That block is the least valuable thing on the screen, so it is what the live
//      pulse replaces.
//
// Two structural rules hold all three together:
//
//   • One hero, one row. The pulse is the only large object — it is the one signal that exists
//     before any history does. Everything else is a short bar in a scrolling row, so context costs
//     one card of height instead of five stacked blocks.
//   • The hero is a drawn object, not a glyph. `GlossyHeart` is a real curve with volume, and it
//     pounds at the measured rate — see `Beat` in HeartBeat.swift.

enum HomeTopStyle: String, CaseIterable, Identifiable {
    case vitalSign, paperChart, pulseAurora
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vitalSign: "Vital Sign"
        case .paperChart: "Paper Chart"
        case .pulseAurora: "Pulse Aurora"
        }
    }
    var caption: String {
        switch self {
        case .vitalSign: "A · dark instrument — the pulse is the hero"
        case .paperChart: "B · editorial light — clinical chart on paper"
        case .pulseAurora: "C · vibe glow — the pulse as an orb"
        }
    }
}

/// Sample numbers shared by the three designs so they compare like-for-like. Deliberately mirrors
/// the *hard* case from the screenshot: a brand-new account with no nights logged yet.
enum HomageSample {
    static let dateLine = "TUE · SEP 29"
    static let greeting = "Good evening, Zen"
    static let initial = "Z"

    // The live pulse — the only signal a new account already has.
    static let bpm: Double = 78
    static let restingBaseline: Double? = 54
    static let lowHigh = (low: 61.0, high: 96.0)

    // Still calibrating, exactly as in the screenshot.
    static let nightsLogged = 0
    static let nightsNeeded = 14

    static let steps = "2,657"
    static let load = "1.2"
    static let loadUsual = "1.9–3.7"
    static let loadWeek: [Double] = [0.55, 0.9, 0.42, 1.0, 0.7, 0.28, 0.34]

    static func pulse(_ bpm: Double) -> HeartRatePulse {
        HeartRatePulse(reading: LiveHeartRate(bpm: bpm, at: Date(), sourceName: "Apple Watch", isWatch: true),
                       restingBaseline: restingBaseline)
    }
}

// MARK: - Shared pieces

/// Calibration said once, quietly, in a strip — not as the biggest number on the screen.
struct CalibrationStrip: View {
    var logged: Int
    var needed: Int
    var tint: Color = Palette.signal
    var labelColor: Color = Palette.secondaryInk
    var trackColor: Color = Palette.sunken

    private var remaining: Int { max(0, needed - logged) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("READINESS & SLEEP").font(Typo.eyebrow).tracking(0.9).foregroundStyle(labelColor)
                Spacer()
                Text("\(logged)/\(needed) NIGHTS").font(Typo.mono(10.5, .medium)).foregroundStyle(labelColor.opacity(0.75))
            }
            HStack(spacing: 3) {
                ForEach(0..<needed, id: \.self) { i in
                    Capsule().fill(i < logged ? tint : trackColor).frame(height: 5)
                }
            }
            Text(logged == 0
                 ? "Wear your watch overnight and scores start after \(needed) nights."
                 : "\(remaining) more \(remaining == 1 ? "night" : "nights") and your scores unlock.")
                .font(Typo.geist(12.5, relativeTo: .footnote))
                .foregroundStyle(labelColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A greeting row that keeps the person's name and the date without eating a third of the screen.
struct HomageHeader: View {
    var serif = false
    var dateLine = HomageSample.dateLine
    var eyebrowColor: Color = Palette.secondaryInk
    var inkColor: Color = Palette.ink
    var avatarFill: Color = Palette.signal.opacity(0.14)
    var avatarStroke: Color = Palette.signal.opacity(0.55)

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine).font(Typo.eyebrow).tracking(1.2).foregroundStyle(eyebrowColor)
                Text(HomageSample.greeting)
                    .font(serif ? .system(.title, design: .serif) : Typo.geist(26, .semibold, relativeTo: .title))
                    .foregroundStyle(inkColor)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            Text(HomageSample.initial)
                .font(serif ? .system(.subheadline, design: .serif) : Typo.geist(15, .semibold))
                .foregroundStyle(inkColor)
                .frame(width: 38, height: 38)
                .background(Circle().fill(avatarFill))
                .overlay(Circle().strokeBorder(avatarStroke, lineWidth: 1))
        }
    }
}

/// The zone as a chip: glyph, word and colour together, so it never depends on hue alone.
struct ZoneChip: View {
    var zone: HeartRateZone
    var tint: Color
    var solid = false
    var solidInk: Color = Color(hex: 0x06121F)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: zone.glyph).font(.system(size: 9.5, weight: .bold))
            Text(zone.label.uppercased()).font(Typo.eyebrow).tracking(0.9)
        }
        .foregroundStyle(solid ? solidInk : tint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(solid ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.13))))
        .overlay(Capsule().strokeBorder(tint.opacity(solid ? 0 : 0.32), lineWidth: 1))
    }
}

/// The low / high of the live window, plus where the pulse sits between them.
struct PulseRangeRow: View {
    var pulse: HeartRatePulse
    var low: Double
    var high: Double
    var muted: Color = Palette.secondaryInk
    var track: Color = Palette.sunken
    var knob: Color = Palette.ink

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let span = max(high - low, 1)
                let x = g.size.width * min(1, max(0, (pulse.bpm - low) / span))
                ZStack(alignment: .leading) {
                    Capsule().fill(track).frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.recovery, pulse.zone.tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: x, height: 4)
                    Circle().fill(knob).frame(width: 9, height: 9).offset(x: max(0, x - 4.5))
                }
                .frame(height: 10)
            }
            .frame(height: 10)
            HStack {
                Text("LOW \(Int(low))").font(Typo.mono(10)).foregroundStyle(muted)
                Spacer()
                Text("LAST 3 MIN").font(Typo.mono(10)).foregroundStyle(muted)
                Spacer()
                Text("HIGH \(Int(high))").font(Typo.mono(10)).foregroundStyle(muted)
            }
        }
    }
}

// MARK: - A · Vital Sign (dark instrument)

/// The pulse as an object: a drawn heart with the rate read inside it, a live ECG beside it, and
/// the day's context divided into a scrolling row of bars underneath.
struct VitalSignTop: View {
    var bpm: Double = HomageSample.bpm

    private var pulse: HeartRatePulse { HomageSample.pulse(bpm) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HomageHeader()

            VStack(spacing: Space.m) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(pulse.zone.tint).frame(width: 6, height: 6)
                        Text("LIVE · APPLE WATCH").font(Typo.eyebrow).tracking(1.2).foregroundStyle(pulse.zone.tint)
                    }
                    Spacer()
                    ZoneChip(zone: pulse.zone, tint: pulse.zone.tint)
                }

                GlossyHeart(bpm: bpm, value: "\(Int(bpm.rounded()))", caption: "bpm", size: 176)
                    .padding(.top, 2)

                Text(pulse.summary)
                    .font(Typo.geist(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.secondaryInk)

                ECGTrace(bpm: bpm, tint: pulse.zone.tint).frame(height: 46)
                PulseRangeRow(pulse: pulse, low: HomageSample.lowHigh.low, high: HomageSample.lowHigh.high)
            }
            .card(padding: Space.l, tone: .hero)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pulse.spokenLabel)

            SummaryBars {
                StatBar(evidence: .bars(HomageSample.loadWeek, Palette.cyan), title: "Load",
                        value: HomageSample.load, caption: "usual \(HomageSample.loadUsual)", tint: Palette.cyan)
                StatBar(evidence: .glyph("figure.walk", Palette.recovery), title: "Steps",
                        value: HomageSample.steps, caption: "so far today", tint: Palette.recovery)
                StatBar(evidence: .glyph("heart.text.square", Palette.heart), title: "Resting",
                        value: "54 bpm", caption: "your baseline", tint: Palette.heart)
                StatBar(evidence: .waiting("moon.zzz"), title: "Sleep", value: "–", caption: "tonight")
                StatBar(evidence: .waiting("waveform.path.ecg"), title: "HRV", value: "–", caption: "after 1st night")
            }

            CalibrationStrip(logged: HomageSample.nightsLogged, needed: HomageSample.nightsNeeded)
                .card(padding: Space.l)
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.l)
        .blithBackground(wash: Palette.heart.opacity(0.16))
    }
}

// MARK: - B · Paper Chart (editorial light)

/// A clinical chart on warm paper. The heart is printed onto an ink slab beside the serif numerals
/// the way a chart prints its headline reading, and the row of bars below is the margin notes.
struct PaperChartTop: View {
    var bpm: Double = HomageSample.bpm

    private let paper = Color(hex: 0xF4F0E8)
    private let slab = Color(hex: 0x101828)
    private let paperInk = Color(hex: 0x101828)
    private let paperSub = Color(hex: 0x4C5665)

    private var pulse: HeartRatePulse { HomageSample.pulse(bpm) }
    private var cardSurface: AnyShapeStyle { AnyShapeStyle(Color.white) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HomageHeader(serif: true, dateLine: "TUESDAY, SEPTEMBER 29",
                         eyebrowColor: Color(hex: 0x8A7A5F), inkColor: paperInk,
                         avatarFill: .clear, avatarStroke: paperInk.opacity(0.35))

            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0xFF6B5E)).frame(width: 6, height: 6)
                        Text("LIVE PULSE").font(Typo.eyebrow).tracking(1.4).foregroundStyle(Color(hex: 0xC9BFA9))
                    }
                    Spacer()
                    ZoneChip(zone: pulse.zone, tint: paper, solid: true, solidInk: slab)
                }

                HStack(alignment: .center, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(bpm.rounded()))")
                            .font(.system(size: 72, design: .serif))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("beats per minute")
                            .font(.system(.footnote, design: .serif))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(pulse.summary)
                            .font(.system(.footnote, design: .serif).italic())
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.top, 5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    GlossyHeart(bpm: bpm, size: 120)
                }

                ZStack {
                    PaperGrid(color: .white.opacity(0.14), step: 13)
                    ECGTrace(bpm: bpm, tint: Color(hex: 0x7DFCD0), lineWidth: 1.8, fadeIn: false)
                }
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(slab))
            .shadow(color: slab.opacity(0.22), radius: 18, y: 9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pulse.spokenLabel)

            SummaryBars {
                StatBar(evidence: .bars(HomageSample.loadWeek, slab), title: "Load", value: HomageSample.load,
                        caption: "usual \(HomageSample.loadUsual)", tint: paperSub,
                        surface: cardSurface, border: paperInk.opacity(0.10))
                StatBar(evidence: .glyph("figure.walk", slab), title: "Steps", value: HomageSample.steps,
                        caption: "so far today", tint: paperSub,
                        surface: cardSurface, border: paperInk.opacity(0.10))
                StatBar(evidence: .glyph("heart.text.square", Color(hex: 0xC0392B)), title: "Resting",
                        value: "54 bpm", caption: "your baseline", tint: paperSub,
                        surface: cardSurface, border: paperInk.opacity(0.10))
                StatBar(evidence: .waiting("moon.zzz"), title: "Sleep", value: "–", caption: "tonight",
                        surface: cardSurface, border: paperInk.opacity(0.10))
            }

            CalibrationStrip(logged: HomageSample.nightsLogged, needed: HomageSample.nightsNeeded,
                             tint: slab, labelColor: paperSub, trackColor: paperInk.opacity(0.13))
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(paperInk.opacity(0.10), lineWidth: 1))
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.l)
        .background(paper)
        .preferredColorScheme(.light)
    }
}

/// The faint printed grid an ECG is drawn on.
struct PaperGrid: View {
    var color: Color
    var step: CGFloat = 13

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(color), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - C · Pulse Aurora (vibe glow)

/// The heart floating in an aurora with nothing around it but its own light, and the rest of the
/// day reduced to a row of glass bars.
struct AuroraPulseTop: View {
    var bpm: Double = HomageSample.bpm

    private var pulse: HeartRatePulse { HomageSample.pulse(bpm) }
    private var glass: AnyShapeStyle { AnyShapeStyle(Color.white.opacity(0.07)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x7DFCD0)).frame(width: 6, height: 6)
                        Text("LIVE · TUESDAY").font(Typo.eyebrow).tracking(1.2).foregroundStyle(Color(hex: 0x7DFCD0))
                    }
                    Text(HomageSample.greeting)
                        .font(Typo.geist(26, .semibold, relativeTo: .title))
                        .foregroundStyle(LinearGradient(colors: [.white, Palette.ice], startPoint: .leading, endPoint: .trailing))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer()
                Text(HomageSample.initial).font(Typo.geist(15, .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.10)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            }

            VStack(spacing: Space.s) {
                GlossyHeart(bpm: bpm, value: "\(Int(bpm.rounded()))", caption: "bpm", size: 196)
                    .padding(.vertical, 2)
                Text(pulse.summary)
                    .font(Typo.geist(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.ice.opacity(0.88))
                HStack(spacing: 7) {
                    ZoneChip(zone: pulse.zone, tint: pulse.zone.tint, solid: true)
                    auroraChip("LOW \(Int(HomageSample.lowHigh.low))")
                    auroraChip("HIGH \(Int(HomageSample.lowHigh.high))")
                }
                ECGTrace(bpm: bpm, tint: Color(hex: 0x7DFCD0), lineWidth: 1.8).frame(height: 40)
            }
            .auroraGlass()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pulse.spokenLabel)

            SummaryBars {
                StatBar(evidence: .bars(HomageSample.loadWeek, Color(hex: 0x7DFCD0)), title: "Load",
                        value: HomageSample.load, caption: "usual \(HomageSample.loadUsual)",
                        tint: Color(hex: 0x7DFCD0), surface: glass, border: .white.opacity(0.16))
                StatBar(evidence: .glyph("figure.walk", Palette.ice), title: "Steps", value: HomageSample.steps,
                        caption: "so far today", tint: Palette.ice, surface: glass, border: .white.opacity(0.16))
                StatBar(evidence: .glyph("heart.text.square", Color(hex: 0xFF8D82)), title: "Resting",
                        value: "54 bpm", caption: "your baseline", tint: Color(hex: 0xFF8D82),
                        surface: glass, border: .white.opacity(0.16))
                StatBar(evidence: .waiting("moon.zzz"), title: "Sleep", value: "–", caption: "tonight",
                        surface: glass, border: .white.opacity(0.16))
            }

            CalibrationStrip(logged: HomageSample.nightsLogged, needed: HomageSample.nightsNeeded,
                             tint: Color(hex: 0x7DFCD0), labelColor: Palette.ice, trackColor: .white.opacity(0.14))
                .auroraGlass()
        }
        .padding(.horizontal, Space.page)
        .padding(.vertical, Space.l)
        .background {
            ZStack {
                Color(hex: 0x07070D)
                RadialGradient(colors: [Palette.heart.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [Palette.sleep.opacity(0.32), .clear], center: .topTrailing, startRadius: 0, endRadius: 330)
                RadialGradient(colors: [Palette.recovery.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 400)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    func auroraChip(_ text: String) -> some View {
        Text(text)
            .font(Typo.eyebrow).tracking(0.9)
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.10)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
    }
}

private struct AuroraGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Space.l)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
    }
}

private extension View {
    func auroraGlass() -> some View { modifier(AuroraGlass()) }
}

// MARK: - Gallery

/// Compare the three tops, and drag the rate to watch the pounding speed follow it.
struct HomeTopGalleryView: View {
    @State private var style: HomeTopStyle = .vitalSign
    @State private var bpm: Double = HomageSample.bpm

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                switch style {
                case .vitalSign: VitalSignTop(bpm: bpm)
                case .paperChart: PaperChartTop(bpm: bpm)
                case .pulseAurora: AuroraPulseTop(bpm: bpm)
                }
            }
            .scrollIndicators(.hidden)
            VStack(spacing: Space.s) {
                Picker("Design", selection: $style) {
                    ForEach(HomeTopStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(style.caption).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                HStack(spacing: Space.m) {
                    Text("\(Int(bpm)) BPM").font(Typo.mono(12, .medium)).foregroundStyle(Palette.ink).frame(width: 72, alignment: .leading)
                    Slider(value: $bpm, in: 44...170, step: 1)
                }
                Text("Drag to change the rate — the heart pounds that many times a minute.")
                    .font(Typo.geist(11, relativeTo: .caption2)).foregroundStyle(Palette.tertiaryInk)
            }
            .padding(Space.l)
            .background(.bar)
        }
    }
}

// MARK: - Previews

#Preview("Tops · Gallery") { HomeTopGalleryView() }
#Preview("Top · A Vital Sign") { ScrollView { VitalSignTop() } }
#Preview("Top · B Paper Chart") { ScrollView { PaperChartTop() } }
#Preview("Top · C Pulse Aurora") { ScrollView { AuroraPulseTop() } }
#Preview("Heart · rate ladder") {
    ScrollView {
        VStack(spacing: Space.xl) {
            ForEach([48.0, 78, 122, 158], id: \.self) { rate in
                HStack(spacing: Space.l) {
                    GlossyHeart(bpm: rate, value: "\(Int(rate))", size: 96)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HeartRateZone.of(bpm: rate, resting: 54).label)
                            .font(Typo.number(18)).foregroundStyle(Palette.ink)
                        Text("\(Int(rate)) beats a minute — and it pounds that often")
                            .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                        ECGTrace(bpm: rate, tint: HeartRateZone.of(bpm: rate, resting: 54).tint).frame(height: 40)
                    }
                }
            }
        }
        .padding(Space.page)
    }
    .background(Palette.canvas)
}
