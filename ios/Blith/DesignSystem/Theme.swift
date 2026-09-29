import BlithCore
import SwiftUI
import UIKit

// MARK: - Color

/// Blith's instrument palette: a near-black canvas where colour only ever means something.
///  • mint / amber / coral — readiness bands (high / moderate / low), never verdicts on the person
///  • cobalt               — movement and load, the brand
///  • cyan                 — "now", highlights, the assistant
///  • violet               — sleep
///  • rose                 — heart signals
///  • orange               — the person's own body notes
/// The app is dark by design, like a precision instrument.
enum Palette {
    static let canvas = Color(hex: 0x07080B)
    static let surface = Color(hex: 0x101217)
    static let raised = Color(hex: 0x181B22)
    static let hairline = Color.white.opacity(0.07)

    static let ink = Color(hex: 0xF2F4F8)
    static let secondaryInk = Color(hex: 0x8A90A0)
    static let tertiaryInk = Color(hex: 0x565C6B)

    static let cobalt = Color(hex: 0x4C8DFF)
    static let cobaltDeep = Color(hex: 0x1F4FE0)
    static let cyan = Color(hex: 0x3DDCFF)
    static let mint = Color(hex: 0x34E0A1)
    static let amber = Color(hex: 0xFFB547)
    static let coral = Color(hex: 0xFF5E57)
    static let sleep = Color(hex: 0x9B8CFF)
    static let heart = Color(hex: 0xFF4D6D)
    static let note = Color(hex: 0xFF8A4C)
    static let weight = Color(hex: 0xC792FF)

    // Semantic aliases used across features.
    static let background = canvas
    static let card = surface
    static let cardRaised = raised
    static let stroke = hairline
    static let separator = Color.white.opacity(0.06)
    static let baseline = Color(hex: 0x5E6576)
    static let review = amber
    static let warm = amber
    static let navy = Color(hex: 0x0A0F24)
    static let accent = cobalt

    static let accentSoft = cobalt.opacity(0.16)
    static let noteSoft = note.opacity(0.16)
    static let sleepSoft = sleep.opacity(0.16)
    static let reviewSoft = amber.opacity(0.16)
    static let weightSoft = weight.opacity(0.16)

    // Sleep stages: a cool ramp from light to deep; awake is the only warm stage.
    static let sleepAwake = Color(hex: 0xFF8A7A)
    static let sleepREM = Color(hex: 0x5FD4FF)
    static let sleepCore = Color(hex: 0x7E8BFF)
    static let sleepDeep = Color(hex: 0x5B3FD9)

    static let heroGradient = LinearGradient(colors: [Color(hex: 0x10204F), Color(hex: 0x0B1330)], startPoint: .top, endPoint: .bottom)
    static let askGradient = LinearGradient(colors: [cobalt, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroGradientTop = cobalt.opacity(0.22)

    static func band(_ band: ScoreBand?) -> Color {
        switch band {
        case .high: mint
        case .moderate: amber
        case .low: coral
        case nil: secondaryInk
        }
    }

    static func sleep(_ stage: SleepStageStyle) -> Color {
        switch stage {
        case .awake: sleepAwake
        case .rem: sleepREM
        case .core: sleepCore
        case .deep: sleepDeep
        }
    }
}

enum SleepStageStyle: CaseIterable { case awake, rem, core, deep }

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }
}

// MARK: - Spacing, radius, motion

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let section: CGFloat = 30
    static let page: CGFloat = 16
}

enum Radius {
    static let card: CGFloat = 22
    static let inner: CGFloat = 14
    static let chip: CGFloat = 10
}

enum Motion {
    /// iOS sheet easing (Skintel's `ease-ios`).
    static let standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.45)
    static let snappy = Animation.snappy(duration: 0.25)
    static let reveal = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.9)

    static func respecting(_ reduceMotion: Bool, _ animation: Animation = standard) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Typography

/// Condensed SF Pro for instrument numerals, expanded caps for section heads, SF Mono for data
/// labels, and a New York serif for the few sentences that interpret. All scale with Dynamic Type
/// except the big dial numerals, which scale with their container.
enum Typo {
    /// Tall condensed numerals for scores and hero values.
    static func score(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.compressed)
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    static let display = Font.system(.largeTitle, design: .serif, weight: .regular)
    static let story = Font.system(.title3, design: .serif, weight: .regular)
    static let storySmall = Font.system(.body, design: .serif, weight: .regular)
    static let title = Font.system(.title2, weight: .bold).width(.condensed)
    static let sectionTitle = Font.system(.footnote, weight: .heavy).width(.expanded)
    static let cardTitle = Font.system(.subheadline, weight: .semibold)
    static let metric = Font.system(.title2, weight: .semibold).width(.condensed)
    static let caption = Font.footnote
    static let eyebrow = Font.system(.caption2, design: .monospaced, weight: .medium)
}

// MARK: - Surfaces

enum CardTone {
    case plain
    case tinted(Color)
    case hero
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = Space.l
    var tone: CardTone = .plain

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
    }

    @ViewBuilder var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        switch tone {
        case .plain: shape.fill(Palette.surface)
        case .tinted(let c):
            shape.fill(Palette.surface)
                .overlay(shape.fill(LinearGradient(colors: [c.opacity(0.16), c.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        case .hero:
            shape.fill(Palette.heroGradient)
                .overlay(alignment: .topTrailing) {
                    RadialGradient(colors: [Palette.cobalt.opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                        .clipShape(shape)
                }
        }
    }

    var borderColor: Color {
        switch tone {
        case .hero: Palette.cobalt.opacity(0.28)
        case .tinted(let c): c.opacity(0.22)
        case .plain: Palette.hairline
        }
    }
}

extension View {
    func card(padding: CGFloat = Space.l, tone: CardTone = .plain) -> some View {
        modifier(CardBackground(padding: padding, tone: tone))
    }

    /// Liquid Glass on iOS 26+, a material fallback before that.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Glass button style on iOS 26+, bordered fallback before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// The canvas, with a soft glow at the top in the screen's signal colour.
    func blithBackground(wash: Color = Palette.heroGradientTop) -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                Palette.canvas
                RadialGradient(colors: [wash.opacity(0.9), wash.opacity(0)], center: .top, startRadius: 0, endRadius: 420)
                    .frame(height: 460)
                    .blur(radius: 10)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Chart helpers

extension LocalDate {
    /// Noon on this day in the current calendar — a safe x value for charts across DST.
    var chartDate: Date { startDate(in: .current).addingTimeInterval(12 * 3600) }
}
