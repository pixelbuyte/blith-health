import BlithCore
import SwiftUI

// MARK: - Home homage gallery (design preview, sample data)
//
// Three vibe-coded homage variations of the Today / Home screen.
// Standalone file: nothing in the app points at it yet. Open
// `HomeHomageGalleryView` in Xcode Previews (or present it from a
// debug gesture) to compare A / B / C side by side, then wire the
// winner into TodayView. All numbers below are sample data.

enum HomeHomageStyle: String, CaseIterable, Identifiable {
    case midnight, porcelain, aurora
    var id: String { rawValue }
    var title: String {
        switch self {
        case .midnight: "Midnight Instrument"
        case .porcelain: "Dawn Porcelain"
        case .aurora: "Pulse Aurora"
        }
    }
    var subtitle: String {
        switch self {
        case .midnight: "A · refined v4 dark"
        case .porcelain: "B · editorial light"
        case .aurora: "C · vibe-coded glow"
        }
    }
}

/// Sample numbers shared by all three homages so they can be compared
/// like-for-like. Mirrors the shape of TodayView (greeting → hero →
/// movement → vitals → insight → streak).
enum HomageSample {
    static let dateLine = "TUE · SEP 29"
    static let greeting = "Good evening, Maya"
    static let status = "Movement is running 12% ahead of a usual Tuesday at this hour."
    static let readiness = 86
    static let sleep = 82
    static let loadText = "4.2"
    static let loadUsual = "3.1–5.4"
    static let steps = "6,412"
    static let stepsDelta = "+12%"
    static let stepsUsual = "Usually 5,720 by now on a Tuesday."
    static let weekBars: [Double] = [0.34, 0.48, 0.40, 0.58, 0.78, 0.96, 0.60]
    static let insightEyebrow = "Worth knowing · Sleep"
    static let insightHeadline = "Late nights cost you Friday steps — 1,900 fewer on average."
    static let insightBody = "Compared against your own history, not population averages."
    static let streakDays = "6"
    static let weekCount = "5/7"
}

struct HomeHomageGalleryView: View {
    @State private var style: HomeHomageStyle = .midnight

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Picker("Variation", selection: $style) {
                        ForEach(HomeHomageStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(style.subtitle.uppercased())
                        .font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
                    switch style {
                    case .midnight: MidnightHomageView()
                    case .porcelain: PorcelainHomageView()
                    case .aurora: AuroraHomageView()
                    }
                    Text("Design preview with sample data — nothing here reads HealthKit.")
                        .font(Typo.caption).foregroundStyle(Palette.tertiaryInk)
                }
                .padding(Space.page)
            }
            .background(Palette.canvas)
            .navigationTitle("Home homages")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - A · Midnight Instrument (refined v4 dark)

struct MidnightHomageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HomageSample.dateLine).font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
                Text(HomageSample.greeting).font(Typo.pageTitle).foregroundStyle(Palette.ink)
                Text(HomageSample.status).font(Typo.story).foregroundStyle(Palette.secondaryInk)
            }
            VStack(spacing: Space.m) {
                HStack {
                    Text("READINESS · YOUR RANGE").font(Typo.eyebrow).foregroundStyle(Palette.signalBright)
                    Spacer()
                    BandChip(band: .high, label: "High readiness")
                }
                HStack(alignment: .center, spacing: 0) {
                    ScoreDial(fraction: Double(HomageSample.sleep) / 100, valueText: "\(HomageSample.sleep)",
                              unit: "%", label: "Sleep", color: Palette.sleep, size: 92, usual: nil)
                        .frame(maxWidth: .infinity)
                    ScoreDial(fraction: Double(HomageSample.readiness) / 100, valueText: "\(HomageSample.readiness)",
                              unit: "%", label: "Readiness", color: Palette.band(.high), size: 160, usual: nil)
                    ScoreDial(fraction: 0.62, valueText: HomageSample.loadText,
                              label: "Load", color: Palette.cyan, size: 92, usual: 0.45...0.78)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 0) {
                    homageStat("HRV", "48 ms")
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 28)
                    homageStat("RHR", "52 bpm")
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 28)
                    homageStat("ASLEEP", "7h 12m")
                }
            }
            .card(padding: Space.l, tone: .hero)
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Eyebrow(text: "Movement · \(HomageSample.steps) steps", color: Palette.signal)
                    Spacer()
                    Text(HomageSample.stepsDelta).font(Typo.geist(14, .semibold)).foregroundStyle(Palette.recovery)
                }
                Text(HomageSample.steps).font(Typo.score(56)).foregroundStyle(Palette.ink)
                Text(HomageSample.stepsUsual).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(HomageSample.weekBars.enumerated()), id: \.offset) { i, f in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i == 5 ? Palette.signalBright : Palette.quiet)
                            .frame(height: 74 * f)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .card(padding: Space.l)
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "Health monitor · 4 of 5 in range")
                homageVital(symbol: "heart.fill", tint: Palette.heart, name: "Resting heart rate", value: "52 bpm")
                homageVital(symbol: "waveform.path.ecg", tint: Palette.recovery, name: "HRV", value: "48 ms")
                homageVital(symbol: "thermometer.medium", tint: Palette.note, name: "Wrist temperature", value: "ABOVE RANGE")
            }
            .card(padding: Space.l)
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: HomageSample.insightEyebrow, color: Palette.sleep)
                Text(HomageSample.insightHeadline).font(Typo.story).foregroundStyle(Palette.ink)
                Text(HomageSample.insightBody).font(Typo.caption).foregroundStyle(Palette.tertiaryInk)
            }
            .card(padding: Space.l, tone: .tinted(Palette.sleep))
        }
        .blithBackground(wash: Palette.signal.opacity(0.16))
    }

    func homageStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(Typo.eyebrow).foregroundStyle(Palette.tertiaryInk)
            Text(value).font(Typo.number(16)).foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
    }

    func homageVital(symbol: String, tint: Color, name: String, value: String) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(tint).frame(width: 24)
            Text(name).font(Typo.geist(15, .medium)).foregroundStyle(Palette.ink)
            Spacer()
            Text(value).font(Typo.number(15)).foregroundStyle(Palette.secondaryInk)
        }
    }
}

// MARK: - B · Dawn Porcelain (editorial light)

struct PorcelainHomageView: View {
    private let paper = Color(hex: 0xF3EEE4)
    private let slab = Color(hex: 0x101828)
    private let paperInk = Color(hex: 0x101828)
    private let paperSub = Color(hex: 0x4C5665)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tuesday, September 29").font(Typo.eyebrow).foregroundStyle(Color(hex: 0x8A7A5F))
                Text(HomageSample.greeting + ".")
                    .font(.system(.title, design: .serif))
                    .foregroundStyle(paperInk)
                Text("Your 30-day average is the highest in six months.")
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(paperSub)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text("READINESS · HIGH").font(Typo.eyebrow).foregroundStyle(Color(hex: 0xC9BFA9))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(HomageSample.readiness)").font(.system(size: 64, design: .serif)).foregroundStyle(.white)
                    Text("/ 100").font(Typo.body).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("▲ HIGH").font(Typo.eyebrow).foregroundStyle(slab)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Palette.recovery))
                }
                Capsule().fill(.white.opacity(0.16)).frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).frame(width: 220, height: 6)
                    }
                HStack {
                    Text("SLEEP \(HomageSample.sleep)").font(Typo.eyebrow).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("LOAD \(HomageSample.loadText) · USUAL \(HomageSample.loadUsual)")
                        .font(Typo.eyebrow).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(slab))
            .shadow(color: slab.opacity(0.25), radius: 20, y: 10)
            HStack(spacing: Space.m) {
                porcelainTile("Steps", HomageSample.steps, "+12% vs usual", Palette.signal)
                porcelainTile("Sleep", "7h 12m", "needs 7h 30m", Palette.sleep)
            }
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("MOVEMENT · YOUR USUAL DAY").font(Typo.eyebrow).foregroundStyle(paperSub)
                    Spacer()
                    Text("AVG 8,204").font(Typo.eyebrow).foregroundStyle(paperSub)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(HomageSample.weekBars.enumerated()), id: \.offset) { i, f in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i == 5 ? slab : Color(hex: 0xD8DEE8))
                            .frame(height: 74 * f)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(paperInk.opacity(0.09), lineWidth: 1))
            VStack(alignment: .leading, spacing: Space.s) {
                Text("INSIGHT · WEEKLY RHYTHM").font(Typo.eyebrow).foregroundStyle(paperSub)
                Text("Saturdays are your strongest days — 11,200 on average.")
                    .font(.system(.headline, design: .serif)).foregroundStyle(paperInk)
                HStack(spacing: Space.s) {
                    Text("See the days").font(Typo.geist(14, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(slab))
                    Text("Why this?").font(Typo.geist(14, .semibold)).foregroundStyle(Palette.signal)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.signal.opacity(0.12)))
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(paperInk.opacity(0.09), lineWidth: 1))
        }
        .padding(Space.page)
        .background(paper)
        .preferredColorScheme(.light)
    }

    func porcelainTile(_ title: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(Typo.eyebrow).foregroundStyle(paperSub)
            Text(value).font(.system(size: 34, design: .serif)).foregroundStyle(paperInk).minimumScaleFactor(0.7).lineLimit(1)
            Text(caption).font(Typo.geist(12)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m + 2)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(paperInk.opacity(0.09), lineWidth: 1))
    }
}

// MARK: - C · Pulse Aurora (vibe-coded glow)

struct AuroraHomageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("● LIVE · TUESDAY").font(Typo.eyebrow).foregroundStyle(Color(hex: 0x7DFCD0))
                Text("Your body, in signal.")
                    .font(Typo.pageTitle).foregroundStyle(.white)
            }
            VStack(spacing: Space.s) {
                Text("READINESS · HIGH ▸").font(Typo.eyebrow).foregroundStyle(Palette.ice)
                ZStack {
                    Circle().trim(from: 0, to: 0.86)
                        .stroke(AngularGradient(colors: [Palette.recovery, Palette.signal, Palette.sleep, Palette.weight, Palette.recovery],
                                                center: .center),
                                style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Palette.signal.opacity(0.6), radius: 18)
                    Text("\(HomageSample.readiness)").font(Typo.score(52)).foregroundStyle(.white)
                        .shadow(color: Color(hex: 0x7DFCD0).opacity(0.55), radius: 16)
                }
                .frame(width: 132, height: 132)
                HStack(spacing: Space.s) {
                    auroraChip("SLEEP \(HomageSample.sleep)")
                    auroraChip("LOAD \(HomageSample.loadText)")
                    Text("▲ HIGH").font(Typo.eyebrow).foregroundStyle(Color(hex: 0x06302B))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0x7DFCD0)))
                }
            }
            .auroraGlass()
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Eyebrow(text: "Movement · \(HomageSample.steps)", color: Palette.signalBright)
                    Spacer()
                    Text(HomageSample.stepsDelta).font(Typo.geist(14, .semibold)).foregroundStyle(Color(hex: 0x7DFCD0))
                }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(HomageSample.weekBars.enumerated()), id: \.offset) { i, f in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i == 5 ? Color(hex: 0x7DFCD0) : Palette.signal.opacity(0.35 + 0.5 * f))
                            .shadow(color: i == 5 ? Color(hex: 0x7DFCD0).opacity(0.7) : .clear, radius: 8)
                            .frame(height: 74 * f)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .auroraGlass()
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "✦ Insight · sleep × steps", color: Palette.weight)
                Text(HomageSample.insightHeadline).font(Typo.geist(16, .semibold)).foregroundStyle(.white)
                Text("−1,900 avg · confidence ▮▮▯ moderate").font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                HStack(spacing: Space.s) {
                    Text("✦ Ask about this").font(Typo.geist(14, .semibold)).foregroundStyle(Color(hex: 0x04121F))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.recovery, Palette.signal], startPoint: .leading, endPoint: .trailing)))
                    Text("Evidence").font(Typo.geist(14, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.10)))
                }
            }
            .auroraGlass()
            HStack(spacing: Space.m) {
                VStack(spacing: 2) {
                    Text("🔥").font(.title3)
                    Text(HomageSample.streakDays).font(Typo.score(30)).foregroundStyle(.white)
                    Text("STREAK").font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
                }.frame(maxWidth: .infinity).auroraGlass()
                VStack(spacing: 2) {
                    Text("◍").font(.title3).foregroundStyle(Palette.signalBright)
                    Text(HomageSample.weekCount).font(Typo.score(30)).foregroundStyle(.white)
                    Text("NEAR USUAL").font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
                }.frame(maxWidth: .infinity).auroraGlass()
            }
        }
        .padding(Space.page)
        .background {
            ZStack {
                Color(hex: 0x07070D)
                RadialGradient(colors: [Palette.recovery.opacity(0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
                RadialGradient(colors: [Palette.sleep.opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [Palette.signal.opacity(0.20), .clear], center: .center, startRadius: 0, endRadius: 380)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    func auroraChip(_ text: String) -> some View {
        Text(text).font(Typo.eyebrow).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.10)))
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
    }
}

private struct AuroraGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
    }
}

private extension View {
    func auroraGlass() -> some View { modifier(AuroraGlass()) }
}

// MARK: - Previews

#Preview("Homages · Gallery") { HomeHomageGalleryView() }
#Preview("Homage · A Midnight") { ScrollView { MidnightHomageView() } }
#Preview("Homage · B Porcelain") { ScrollView { PorcelainHomageView() } }
#Preview("Homage · C Aurora") { ScrollView { AuroraHomageView() } }
