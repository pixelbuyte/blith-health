import SwiftUI

enum TodaySection: String, CaseIterable, Identifiable {
    case overview, heart, vitals, insights
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .heart: "Heart"
        case .vitals: "Vitals"
        case .insights: "Insights"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Your day"
        case .heart: "Your pulse"
        case .vitals: "Night signals"
        case .insights: "Your patterns"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .heart: "heart.fill"
        case .vitals: "waveform.path"
        case .insights: "chart.xyaxis.line"
        }
    }

    var tint: Color {
        switch self {
        case .overview: Palette.signal
        case .heart: Palette.heart
        case .vitals: Palette.recovery
        case .insights: Palette.sleep
        }
    }

    /// Existing CI scroll destinations continue to select the content that owns them.
    static var initial: TodaySection {
        if let raw = LaunchOptions.args.string(forKey: "BlithTodaySection"), let section = Self(rawValue: raw) {
            return section
        }
        switch LaunchOptions.args.string(forKey: "BlithScrollTo") {
        case "heart": return .heart
        case "monitor", "context": return .vitals
        case "week", "rhythm", "ribbon", "milestones", "scores": return .insights
        default: return .overview
        }
    }
}

/// A persistent, horizontally scrollable section bar; each selection replaces the page below.
struct TodaySectionBar: View {
    @Binding var selection: TodaySection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Space.s) {
                    ForEach(TodaySection.allCases) { item in
                        Button { selection = item } label: {
                            HStack(spacing: Space.s) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(item.tint)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(Typo.cardTitle).foregroundStyle(Palette.ink)
                                    Text(item.subtitle).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                                }
                                if selection == item {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(item.tint).accessibilityHidden(true)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, Space.m).padding(.vertical, Space.m)
                            .frame(minHeight: 58)
                            .background(selection == item ? item.tint.opacity(0.12) : Palette.surface,
                                        in: RoundedRectangle(cornerRadius: Radius.inner))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.inner)
                                    .strokeBorder(selection == item ? item.tint.opacity(0.6) : Palette.hairline,
                                                  lineWidth: selection == item ? 1.5 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityHint("Shows \(item.subtitle.lowercased())")
                        .accessibilityAddTraits(selection == item ? .isSelected : [])
                        .id(item)
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selection, initial: true) { _, selected in
                withAnimation(Motion.respecting(reduceMotion, .easeOut(duration: 0.2))) {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today sections")
    }
}
