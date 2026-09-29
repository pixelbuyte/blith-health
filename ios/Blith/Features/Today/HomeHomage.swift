import BlithCore
import SwiftUI

// MARK: - Home top designs (v2)
//
// Three reworks of the top of the home screen — the area in the screenshot: status line, greeting,
// scores hero, and the block under it. Sample data; nothing here reads HealthKit and nothing in the
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
// A live pulse is the one signal that exists before any history does, which makes it the right
// thing to lead with on day one. It pounds at the real rate — see `Beat` in HeartBeat.swift.

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
    static var pulse: HeartRatePulse {
        HeartRatePulse(reading: LiveHeartRate(bpm: bpm, at: Date(), sourceName: "Apple Watch", isWatch: true),
                       restingBaseline: restingBaseline)
    }
    static let lowHigh = (low: 61.0, high: 96.0)

    // Still calibrating, exactly as in the screenshot.
    static let nightsLogged = 0
    static let nightsNeeded = 14
    static let load = "1.2"
    static let loadUsual = "1.9–3.7"
}

// MARK: - Shared pieces

/// Calibration said once, quietly, in a strip — not as the biggest number on the screen.
struct CalibrationStrip: View {
    var logged: Int
    var needed: Int
    var tint: Color = Palette.signal
    var onWhy: (() -> Void)?

    private var remaining: Int { max(0, needed - logged) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("READINESS & SLEEP").font(Typo.eyebrow).tracking(0.9).foregroundStyle(Palette.secondaryInk)
                Spacer()
                Text("\(logged)/\(needed) NIGHTS").font(Typo.mono(11, .medium)).foregroundStyle(Palette.tertiaryInk)
            }
            SegmentedProgress(total: needed, done: logged, color: tint)
            Text(logged == 0
                 ? "Wear your watch overnight and scores start after \(needed) nights."
                 : "\(remaining) more \(remaining == 1 ? "night" : "nights") and your scores unlock.")
                .font(Typo.geist(13, relativeTo: .footnote))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A greeting row that keeps the person's name and the date without eating a third of the screen.
struct HomageHeader: View {
    var serif = false
    var onDark = true

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(HomageSample.dateLine).font(Typo.eyebrow).tracking(1)
                    .foregroundStyle(Palette.secondaryInk)
                Text(HomageSample.greeting)
                    .font(serif ? .system(.title, design: .serif) : Typo.pageTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            Text(HomageSample.initial)
                .font(Typo.geist(15, .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.signal.opacity(0.14)))
                .overlay(Circle().strokeBorder(Palette.signal.opacity(0.55), lineWidth: 1))
        }
    }
}

/// The low / high of the live window, plus where the pulse sits between them.
struct PulseRangeRow: View {
    var pulse: HeartRatePulse
    var low: Double
    var high: Double
    var muted: Color = Palette.secondaryInk

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let span = max(high - low, 1)
                let x = g.size.width * min(1, max(0, (pulse.bpm - low) / span))
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.sunken).frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.recovery, pulse.zone.tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: x, height: 4)
                    Circle().fill(Palette.ink).frame(width: 9, height: 9).offset(x: max(0, x - 4.5))
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

/// The pulse is the hero: a pounding heart, the rate as a tall numeral, a live ECG, and the
/// comparison against the person's own resting rate. Calibration sits underneath as one strip.
struct VitalSignTop: View {
    var bpm: Double = HomageSample.bpm

    private var pulse: HeartRatePulse {
        HeartRatePulse(reading: LiveHeartRate(bpm: bpm, at: Date(), sourceName: "Apple Watch", isWatch: true),
                       restingBaseline: HomageSample.restingBaseline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HomageHeader()
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: 6) {
                    Circle().fill(pulse.zone.tint).frame(width: 6, height: 6)
                    Text("LIVE · APPLE WATCH").font(Typo.eyebrow).tracking(1).foregroundStyle(pulse.zone.tint)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: pulse.zone.glyph).font(.system(size: 10, weight: .bold))
                        Text(pulse.zone.label.uppercased()).font(Typo.eyebrow).tracking(0.9)
                    }
                    .foregroundStyle(pulse.zone.tint)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(pulse.zone.tint.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(pulse.zone.tint.opacity(0.3), lineWidth: 1))
                }
                HStack(alignment: .center, spacing: Space.l) {
                    PoundingHeart(bpm: bpm, tint: pulse.zone.tint, size: 76)
                    VStack(alignment: .leading, spacing: -4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(bpm.rounded()))")
                                .font(Typo.score(64))
                                .foregroundStyle(Palette.ink)
                                .contentTransition(.numericText())
                            Text("BPM").font(Typo.mono(13, .medium)).foregroundStyle(Palette.secondaryInk)
                        }
                        Text(pulse.summary).font(Typo.geist(13, relativeTo: .footnote)).foregroundStyle(Palette.secondaryInk)
                    }
                    Spacer()
                }
                ECGTrace(bpm: bpm, tint: pulse.zone.tint).frame(height: 54)
                PulseRangeRow(pulse: pulse, low: HomageSample.lowHigh.low, high: HomageSample.lowHigh.high)
            }
            .card(padding: Space.l, tone: .hero)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pulse.spokenLabel)

            VStack(spacing: Space.m) {
                CalibrationStrip(logged: HomageSample.nightsLogged, needed: HomageSample.nightsNeeded)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack(spacing: 0) {
                    miniStat("LOAD", HomageSample.load, "usual \(HomageSample.loadUsual)", Palette.cyan)
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 34)
                    miniStat("SLEEP", "–", "not tracked yet", Palette.sleep)
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 34)
                    miniStat("HRV", "–", "after 1st night", Palette.recovery)
                }
            }
            .card(padding: Space.l)
        }
        .blithBackground(wash: Palette.heart.opacity(0.14))
    }

    func miniStat(_ title: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(Typo.eyebrow).tracking(0.9).foregroundStyle(tint)
            Text(value).font(Typo.number(19)).foregroundStyle(value == "–" ? Palette.tertiaryInk : Palette.ink)
            Text(caption).font(Typo.geist(10.5, relativeTo: .caption2)).foregroundStyle(Palette.tertiaryInk)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - B · Paper Chart (editorial light)

/// A clinical chart on warm paper: the rate in serif numerals on an ink slab, the ECG drawn on a
/// measurement grid the way a real trace is printed.
struct PaperChartTop: View {
    var bpm: Double = HomageSample.bpm

    private let paper = Color(hex: 0xF4F0E8)
    private let slab = Color(hex: 0x101828)
    private let paperInk = Color(hex: 0x101828)
    private let paperSub = Color(hex: 0x4C5665)
    private let grid = Color(hex: 0xC9BFA9)

    private var pulse: HeartRatePulse {
        HeartRatePulse(reading: LiveHeartRate(bpm: bpm, at: Date(), sourceName: "Apple Watch", isWatch: true),
                       restingBaseline: HomageSample.restingBaseline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TUESDAY, SEPTEMBER 29").font(Typo.eyebrow).tracking(1).foregroundStyle(Color(hex: 0x8A7A5F))
                    Text("Good evening, Zen.").font(.system(.title, design: .serif)).foregroundStyle(paperInk)
                }
                Spacer()
                Text(HomageSample.initial).font(.system(.subheadline, design: .serif))
                    .foregroundStyle(paperInk)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(paperInk.opacity(0.35), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0xFF6B5E)).frame(width: 6, height: 6)
                        Text("LIVE PULSE").font(Typo.eyebrow).tracking(1.2).foregroundStyle(Color(hex: 0xC9BFA9))
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: pulse.zone.glyph).font(.system(size: 10, weight: .bold))
                        Text(pulse.zone.label.uppercased()).font(Typo.eyebrow).tracking(0.9)
                    }
                    .foregroundStyle(slab)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0xF4F0E8)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(bpm.rounded()))")
                        .font(.system(size: 66, design: .serif))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("bpm").font(.system(.body, design: .serif)).foregroundStyle(.white.opacity(0.7))
                        Text(pulse.summary).font(.system(.caption, design: .serif).italic())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    PoundingHeart(bpm: bpm, tint: Color(hex: 0xFF8D82), size: 54, shockwave: false)
                }
                ZStack {
                    PaperGrid(color: .white.opacity(0.14), step: 13)
                    ECGTrace(bpm: bpm, tint: Color(hex: 0x7DFCD0), lineWidth: 1.8, fadeIn: false)
                }
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(slab))
            .shadow(color: slab.opacity(0.22), radius: 18, y: 9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pulse.spokenLabel)

            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("READINESS & SLEEP").font(Typo.eyebrow).tracking(0.9).foregroundStyle(paperSub)
                    Spacer()
                    Text("\(HomageSample.nightsLogged)/\(HomageSample.nightsNeeded) NIGHTS")
                        .font(Typo.mono(11, .medium)).foregroundStyle(paperSub)
                }
                HStack(spacing: 3) {
                    ForEach(0..<HomageSample.nightsNeeded, id: \.self) { i in
                        Capsule()
                            .fill(i < HomageSample.nightsLogged ? slab : paperInk.opacity(0.13))
                            .frame(height: 5)
                    }
                }
                Text("Wear your watch overnight and scores start after \(HomageSample.nightsNeeded) nights.")
                    .font(.system(.footnote, design: .serif)).foregroundStyle(paperSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(paperInk.opacity(0.10), lineWidth: 1))

            HStack(spacing: Space.m) {
                paperTile("Load today", HomageSample.load, "usual \(HomageSample.loadUsual)")
                paperTile("Resting", "54", "learned from nights")
            }
        }
        .padding(Space.page)
        .background(paper)
        .preferredColorScheme(.light)
    }

    func paperTile(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(Typo.eyebrow).tracking(0.9).foregroundStyle(paperSub)
            Text(value).font(.system(size: 32, design: .serif)).foregroundStyle(paperInk)
            Text(caption).font(Typo.geist(11, relativeTo: .caption)).foregroundStyle(paperSub).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m + 2)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(paperInk.opacity(0.10), lineWidth: 1))
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

/// The pulse as a glowing orb: a conic ring holding a pounding heart, shockwaves on every beat,
/// and the rate in gradient numerals.
struct AuroraPulseTop: View {
    var bpm: Double = HomageSample.bpm

    private var pulse: HeartRatePulse {
        HeartRatePulse(reading: LiveHeartRate(bpm: bpm, at: Date(), sourceName: "Apple Watch", isWatch: true),
                       restingBaseline: HomageSample.restingBaseline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x7DFCD0)).frame(width: 6, height: 6)
                        Text("LIVE · TUESDAY").font(Typo.eyebrow).tracking(1).foregroundStyle(Color(hex: 0x7DFCD0))
                    }
                    Text("Good evening, Zen")
                        .font(Typo.pageTitle)
                        .foregroundStyle(LinearGradient(colors: [.white, Palette.ice], startPoint: .leading, endPoint: .trailing))
                }
                Spacer()
                Text(HomageSample.initial).font(Typo.geist(15, .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.10)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            }

            VStack(spacing: Space.s) {
                ZStack {
                    Circle()
                        .stroke(AngularGradient(colors: [Palette.recovery, Palette.signal, pulse.zone.tint, Palette.weight, Palette.recovery],
                                                center: .center),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .shadow(color: pulse.zone.tint.opacity(0.55), radius: 16)
                    PoundingHeart(bpm: bpm, tint: Color(hex: 0xFF8D82), size: 86)
                }
                .frame(width: 150, height: 150)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(bpm.rounded()))")
                        .font(Typo.score(50))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0x7DFCD0), .white], startPoint: .top, endPoint: .bottom))
                        .contentTransition(.numericText())
                    Text("BPM").font(Typo.mono(12, .medium)).foregroundStyle(Palette.ice)
                }
                Text(pulse.summary).font(Typo.geist(13, relativeTo: .footnote)).foregroundStyle(Palette.ice.opacity(0.85))
                HStack(spacing: Space.s) {
                    auroraChip("\(pulse.zone.label.uppercased())", glyph: pulse.zone.glyph, solid: true, tint: pulse.zone.tint)
                    auroraChip("LOW \(Int(HomageSample.lowHigh.low))")
                    auroraChip("HIGH \(Int(HomageSample.lowHigh.high))")
                }
            }
            .auroraGlass()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pulse.spokenLabel)

            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("READINESS & SLEEP").font(Typo.eyebrow).tracking(0.9).foregroundStyle(Palette.ice)
                    Spacer()
                    Text("\(HomageSample.nightsLogged)/\(HomageSample.nightsNeeded) NIGHTS")
                        .font(Typo.mono(11, .medium)).foregroundStyle(Palette.ice.opacity(0.7))
                }
                HStack(spacing: 3) {
                    ForEach(0..<HomageSample.nightsNeeded, id: \.self) { i in
                        Capsule()
                            .fill(i < HomageSample.nightsLogged
                                  ? AnyShapeStyle(LinearGradient(colors: [Palette.recovery, Palette.signal], startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Color.white.opacity(0.14)))
                            .frame(height: 5)
                    }
                }
                Text("Your pulse is live now. Scores arrive after \(HomageSample.nightsNeeded) nights of sleep.")
                    .font(Typo.geist(13, relativeTo: .footnote)).foregroundStyle(Palette.ice.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .auroraGlass()

            HStack(spacing: Space.m) {
                VStack(spacing: 1) {
                    Text("LOAD").font(Typo.eyebrow).foregroundStyle(Palette.ice)
                    Text(HomageSample.load).font(Typo.score(28)).foregroundStyle(.white)
                    Text("usual \(HomageSample.loadUsual)").font(Typo.geist(10.5, relativeTo: .caption2)).foregroundStyle(Palette.ice.opacity(0.7))
                }
                .frame(maxWidth: .infinity).auroraGlass()
                VStack(spacing: 1) {
                    Text("RESTING").font(Typo.eyebrow).foregroundStyle(Palette.ice)
                    Text("54").font(Typo.score(28)).foregroundStyle(.white)
                    Text("from your nights").font(Typo.geist(10.5, relativeTo: .caption2)).foregroundStyle(Palette.ice.opacity(0.7))
                }
                .frame(maxWidth: .infinity).auroraGlass()
            }
        }
        .padding(Space.page)
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

    func auroraChip(_ text: String, glyph: String? = nil, solid: Bool = false, tint: Color = .white) -> some View {
        HStack(spacing: 4) {
            if let glyph { Image(systemName: glyph).font(.system(size: 9, weight: .bold)) }
            Text(text).font(Typo.eyebrow).tracking(0.9)
        }
        .foregroundStyle(solid ? Color(hex: 0x06121F) : .white)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(solid ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.10))))
        .overlay(Capsule().strokeBorder(.white.opacity(solid ? 0 : 0.22), lineWidth: 1))
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
#Preview("Pulse · rate ladder") {
    VStack(spacing: Space.xl) {
        ForEach([48.0, 78, 122, 158], id: \.self) { rate in
            HStack(spacing: Space.l) {
                PoundingHeart(bpm: rate, tint: HeartRateZone.of(bpm: rate, resting: 54).tint, size: 60)
                VStack(alignment: .leading) {
                    Text("\(Int(rate)) BPM").font(Typo.number(20)).foregroundStyle(Palette.ink)
                    Text(HeartRateZone.of(bpm: rate, resting: 54).label).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
                ECGTrace(bpm: rate, tint: HeartRateZone.of(bpm: rate, resting: 54).tint).frame(height: 44)
            }
        }
    }
    .padding(Space.page)
    .background(Palette.canvas)
}
