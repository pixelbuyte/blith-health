import BlithCore
import SwiftUI
import UIKit

// MARK: - Color

/// Centralized palette. Accent is an electric-soft blue; data colors are distinct so charts
/// stay readable and not everything is blue. Nothing here encodes "good/bad" — deltas use
/// neutral styling unless there is real context.
enum Palette {
    static let accent = Color.accentColor
    static let accentSoft = Color(light: UIColor(red: 0.259, green: 0.478, blue: 1, alpha: 0.12),
                                  dark: UIColor(red: 0.408, green: 0.580, blue: 1, alpha: 0.22))
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardRaised = Color(uiColor: .tertiarySystemGroupedBackground)
    static let separator = Color(uiColor: .separator)
    /// "Your usual" lines and bars.
    static let baseline = Color(light: UIColor(white: 0.62, alpha: 1), dark: UIColor(white: 0.5, alpha: 1))
    static let weight = Color(light: UIColor(red: 0.10, green: 0.62, blue: 0.56, alpha: 1),
                              dark: UIColor(red: 0.30, green: 0.82, blue: 0.74, alpha: 1))
    static let sleepCore = Color(red: 0.36, green: 0.55, blue: 1.0)
    static let sleepDeep = Color(red: 0.33, green: 0.26, blue: 0.86)
    static let sleepREM = Color(red: 0.38, green: 0.78, blue: 0.98)
    static let sleepAwake = Color(red: 1.0, green: 0.56, blue: 0.44)
    static let warm = Color(red: 1.0, green: 0.63, blue: 0.30)
    static let heroGradientTop = Color(light: UIColor(red: 0.259, green: 0.478, blue: 1, alpha: 0.18),
                                       dark: UIColor(red: 0.26, green: 0.36, blue: 0.95, alpha: 0.28))

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

extension Color {
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
    /// Horizontal page margin.
    static let page: CGFloat = 20
}

enum Radius {
    static let card: CGFloat = 26
    static let inner: CGFloat = 16
    static let chip: CGFloat = 12
}

enum Motion {
    static let standard = Animation.smooth(duration: 0.35)
    static let snappy = Animation.snappy(duration: 0.25)

    static func respecting(_ reduceMotion: Bool, _ animation: Animation = standard) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Typography

enum Typo {
    /// Big rounded numbers. Pair with `@ScaledMetric` sizes in views for Dynamic Type.
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let title = Font.system(.title2, design: .rounded, weight: .bold)
    static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    static let cardTitle = Font.system(.headline, design: .rounded, weight: .semibold)
    static let metric = Font.system(.title3, design: .rounded, weight: .semibold)
    static let caption = Font.footnote
    static let eyebrow = Font.system(.caption, design: .rounded, weight: .semibold)
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    var padding: CGFloat = Space.l
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Space.l) -> some View { modifier(CardBackground(padding: padding)) }

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
}

// MARK: - Chart helpers

extension LocalDate {
    /// Noon on this day in the current calendar — a safe x value for charts across DST.
    var chartDate: Date { startDate(in: .current).addingTimeInterval(12 * 3600) }
}
