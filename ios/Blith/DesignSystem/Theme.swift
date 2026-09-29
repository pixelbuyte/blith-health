import BlithCore
import SwiftUI
import UIKit

// MARK: - Color

/// Blith's palette. Every color carries one meaning across Today, Walk, Sleep, Body and Ask:
///  • cobalt  — walking and movement, the brand
///  • cyan    — highlights, "now", the assistant's spark
///  • teal    — sleep and recovery
///  • coral   — the user's own body notes
///  • amber   — things worth reviewing (sample data, stale data)
///  • violet  — weight
/// Deltas are never red/green verdicts.
enum Palette {
    static let cobalt = Color(light: 0x2F5BFF, dark: 0x5B82FF)
    static let cobaltDeep = Color(hex: 0x1B37D6)
    static let navy = Color(hex: 0x0B1230)
    static let cyan = Color(light: 0x14AEE3, dark: 0x4FD6FF)
    static let sleep = Color(light: 0x0E9E90, dark: 0x35D0C0)
    static let note = Color(light: 0xEE5A3A, dark: 0xFF8466)
    static let review = Color(light: 0xC77E00, dark: 0xFFB23F)
    static let weight = Color(light: 0x6246F0, dark: 0x9A86FF)

    static let ink = Color(light: 0x0B1230, dark: 0xEEF2FF)
    static let secondaryInk = Color(light: 0x55608A, dark: 0x9AA6CF)
    static let background = Color(light: 0xF2F5FC, dark: 0x060A1A)
    static let card = Color(light: 0xFFFFFF, dark: 0x0E1530)
    static let cardRaised = Color(light: 0xF5F7FF, dark: 0x16204A)
    static let stroke = Color(light: 0xE1E7F7, dark: 0x1D2856)
    static let separator = Color(light: 0xD5DCEF, dark: 0x25305E)
    /// "Your usual" lines and comparison bars.
    static let baseline = Color(light: 0x9AA3BF, dark: 0x6D78A3)

    static let accent = cobalt
    static let accentSoft = Color(light: UIColor(hex: 0x2F5BFF, alpha: 0.10), dark: UIColor(hex: 0x5B82FF, alpha: 0.20))
    static let noteSoft = Color(light: UIColor(hex: 0xEE5A3A, alpha: 0.10), dark: UIColor(hex: 0xFF8466, alpha: 0.18))
    static let sleepSoft = Color(light: UIColor(hex: 0x0E9E90, alpha: 0.10), dark: UIColor(hex: 0x35D0C0, alpha: 0.16))
    static let reviewSoft = Color(light: UIColor(hex: 0xC77E00, alpha: 0.10), dark: UIColor(hex: 0xFFB23F, alpha: 0.16))
    static let weightSoft = Color(light: UIColor(hex: 0x6246F0, alpha: 0.10), dark: UIColor(hex: 0x9A86FF, alpha: 0.18))

    // Sleep stages stay in the teal family; awake is the only warm stage.
    static let sleepDeep = Color(light: 0x0A5E74, dark: 0x1E8FA8)
    static let sleepCore = sleep
    static let sleepREM = Color(light: 0x3CC8E0, dark: 0x6FE3F2)
    static let sleepAwake = Color(light: 0xF28B6A, dark: 0xFF9C7A)

    /// The story card: deep cobalt into vivid blue.
    static let heroGradient = LinearGradient(colors: [Color(hex: 0x1430C8), Color(hex: 0x2A55FF), Color(hex: 0x3F8CFF)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let askGradient = LinearGradient(colors: [Color(hex: 0x2F5BFF), Color(hex: 0x22B8F0)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroGradientTop = Color(light: UIColor(hex: 0x2F5BFF, alpha: 0.14), dark: UIColor(hex: 0x2F5BFF, alpha: 0.30))

    // Compatibility names.
    static let warm = review

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

    init(light: UInt32, dark: UInt32) {
        self.init(light: UIColor(hex: light), dark: UIColor(hex: dark))
    }

    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
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
    static let section: CGFloat = 36
    static let page: CGFloat = 18
}

enum Radius {
    static let card: CGFloat = 28
    static let inner: CGFloat = 18
    static let chip: CGFloat = 12
}

enum Motion {
    static let standard = Animation.smooth(duration: 0.35)
    static let snappy = Animation.snappy(duration: 0.25)
    static let reveal = Animation.spring(response: 0.7, dampingFraction: 0.86)

    static func respecting(_ reduceMotion: Bool, _ animation: Animation = standard) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Typography

/// New York serif carries the story, SF Rounded carries numbers, SF Mono carries labels.
/// All styles are text-style based so Dynamic Type scales them.
enum Typo {
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let story = Font.system(.title2, design: .serif, weight: .semibold)
    static let storySmall = Font.system(.title3, design: .serif, weight: .semibold)
    static let title = Font.system(.title2, design: .serif, weight: .semibold)
    static let sectionTitle = Font.system(.title3, design: .serif, weight: .semibold)
    static let cardTitle = Font.system(.headline, design: .rounded, weight: .semibold)
    static let metric = Font.system(.title3, design: .rounded, weight: .semibold)
    static let caption = Font.footnote
    static let eyebrow = Font.system(.caption2, design: .monospaced, weight: .semibold)
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
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: 16, y: 6)
    }

    @ViewBuilder var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        switch tone {
        case .plain: shape.fill(Palette.card)
        case .tinted(let c): shape.fill(Palette.card).overlay(shape.fill(c.opacity(scheme == .dark ? 0.16 : 0.07)))
        case .hero: shape.fill(Palette.heroGradient)
        }
    }

    var borderColor: Color {
        switch tone {
        case .hero: Color.white.opacity(0.14)
        case .tinted(let c): c.opacity(0.22)
        case .plain: Palette.stroke
        }
    }

    var shadowColor: Color {
        if scheme == .dark { return .clear }
        switch tone {
        case .hero: return Color(hex: 0x1B37D6, opacity: 0.28)
        default: return Color(hex: 0x1B2A6B, opacity: 0.05)
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

    /// Screen background: calm paper with a soft cobalt wash at the top.
    func blithBackground(wash: Color = Palette.heroGradientTop) -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                Palette.background
                LinearGradient(colors: [wash, Palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 380)
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
