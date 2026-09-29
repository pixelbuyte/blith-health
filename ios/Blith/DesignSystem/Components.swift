import BlithCore
import Charts
import SwiftUI
import UIKit

/// A Blith symbol from the asset catalog (`bl.*`), falling back to an SF Symbol name.
struct BLIcon: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if UIImage(named: name) != nil {
                Image(name).resizable().renderingMode(.template).scaledToFit()
            } else {
                Image(systemName: name).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Spaced mono data label ("LAST NIGHT · 7H 12M").
struct Eyebrow: View {
    let text: String
    var icon: String?
    var color: Color = Palette.secondaryInk

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            if let icon { BLIcon(name: icon, size: 12) }
            Text(text.uppercased()).font(Typo.eyebrow).tracking(1.3)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

/// Expanded caps section head with an optional mono action.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).font(Typo.sectionTitle).tracking(1.2).foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Space.s)
            if let trailing, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(trailing.uppercased()).font(Typo.eyebrow).tracking(1.1)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Palette.cobalt)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A change vs a baseline: an arrow and a number, no verdict.
struct DeltaBadge: View {
    let change: Double
    var caption: String?
    var tint: Color = Palette.accent

    var body: some View {
        let flat = Int((change * 100).rounded()) == 0
        HStack(spacing: Space.xs) {
            Image(systemName: flat ? "equal" : (change >= 0 ? "arrow.up.right" : "arrow.down.right"))
                .font(.caption.weight(.heavy))
            Text(flat ? "About the same" : Fmt.signedPercent(change))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let caption {
                Text(caption).font(.subheadline).foregroundStyle(Palette.secondaryInk).lineLimit(2)
            }
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(flat ? "About the same \(caption ?? "")" : "\(Fmt.percent(change)) \(change >= 0 ? "above" : "below") \(caption ?? "")")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var caption: String?
    var color: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(Typo.eyebrow).tracking(1).foregroundStyle(Palette.secondaryInk).lineLimit(1)
            Text(value).font(Typo.metric).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(Palette.secondaryInk).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SourceBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "heart.text.square")
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Space.l) {
            BLIcon(name: symbol, size: 20)
                .foregroundStyle(Palette.cobalt)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Palette.accentSoft))
                .overlay(Circle().strokeBorder(Palette.cobalt.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: Space.xs + 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(message).font(.subheadline).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.cobalt)
                        .padding(.top, Space.xs)
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

/// Sample data is always labelled, compactly.
struct SampleDataBanner: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Palette.amber).frame(width: 5, height: 5)
            Text("SAMPLE DATA").font(Typo.eyebrow).tracking(1.2)
        }
        .foregroundStyle(Palette.amber)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.amber.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Palette.amber.opacity(0.3), lineWidth: 1))
        .accessibilityLabel("Showing sample data, not your health records")
    }
}

struct SyncStatusLine: View {
    let history: HealthHistory
    var isSyncing: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            if isSyncing {
                ProgressView().controlSize(.mini)
                Text("Updating…")
            } else if let last = history.sync.lastSync {
                Image(systemName: history.sync.status == .failed ? "exclamationmark.circle" : "checkmark.circle")
                Text("\(history.origin.providerKind.displayName) · updated \(last.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.tertiaryInk)
        .frame(maxWidth: .infinity)
    }
}

/// Top-right profile entry point.
struct AvatarButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let first = name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(first).uppercased()).font(.system(size: 17, weight: .bold).width(.condensed))
                } else {
                    Image(systemName: "person.fill").font(.subheadline)
                }
            }
            .foregroundStyle(Palette.ink)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Palette.raised))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [Palette.cobalt, Palette.cyan], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }
}

/// D / W / M / 6M / Y / All.
struct PeriodPicker: View {
    @Binding var selection: WalkPeriod
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WalkPeriod.allCases) { p in
                Button {
                    withAnimation(Motion.respecting(reduceMotion, Motion.snappy)) { selection = p }
                } label: {
                    Text(p.shortTitle.uppercased())
                        .font(.system(size: 12, weight: selection == p ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(selection == p ? Palette.ink : Palette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if selection == p {
                                Capsule().fill(Palette.raised)
                                    .overlay(Capsule().strokeBorder(Palette.cobalt.opacity(0.6), lineWidth: 1))
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(selection == p ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Palette.surface))
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// The week as seven cells. Filled = at or near the person's usual; nothing is "broken".
struct ConsistencyDots: View {
    let week: WeekConsistency
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(week.days) { day in
                VStack(spacing: 6) {
                    cell(day.state)
                    Text(String(Fmt.weekdayShort[day.date.weekday - 1].prefix(1)))
                        .font(Typo.eyebrow)
                        .foregroundStyle(day.state == .inProgress ? Palette.ink : Palette.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(day))
            }
        }
    }

    @ViewBuilder
    func cell(_ state: WeekConsistency.DayState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        switch state {
        case .met: shape.fill(tint.gradient).frame(height: 26)
        case .inProgress: shape.strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(height: 26)
        case .notMet: shape.fill(tint.opacity(0.18)).frame(height: 26)
        case .noData, .future: shape.strokeBorder(Palette.hairline, lineWidth: 1).frame(height: 26)
        }
    }

    func label(_ day: WeekConsistency.Day) -> String {
        let name = Fmt.weekday(day.date)
        switch day.state {
        case .met: return "\(name): near your usual, \(Fmt.int(day.value ?? 0)) steps"
        case .notMet: return "\(name): \(Fmt.int(day.value ?? 0)) steps"
        case .inProgress: return "\(name): today, in progress"
        case .noData: return "\(name): no data"
        case .future: return "\(name): upcoming"
        }
    }
}

// MARK: - Insights

extension Insight {
    /// The colour family an insight belongs to.
    var tint: Color {
        switch kind {
        case .sleepMovement, .sleepTiming: Palette.sleep
        case .weightTrend, .weightActivity: Palette.weight
        case .noteContext: Palette.note
        default: Palette.cobalt
        }
    }

    var label: String {
        switch kind {
        case .baselineChange, .momentum, .longTermChange: "Trend"
        case .consistency: "Consistency"
        case .dayOfWeek, .weekdayDecline: "Weekly rhythm"
        case .timing: "Timing"
        case .personalBest: "Personal best"
        case .pace: "Pace"
        case .weightTrend, .weightActivity: "Weight"
        case .rebound: "Rebound"
        case .sleepMovement, .sleepTiming: "Sleep"
        case .noteContext: "Body note"
        }
    }

    var icon: String {
        switch kind {
        case .baselineChange, .momentum, .longTermChange: "bl.trend"
        case .consistency: "bl.streak"
        case .dayOfWeek, .weekdayDecline: "bl.calendar"
        case .timing: "bl.steptrail"
        case .personalBest: "bl.medal"
        case .pace: "bl.steps"
        case .weightTrend, .weightActivity: "bl.weight"
        case .rebound: "bl.progress"
        case .sleepMovement, .sleepTiming: "bl.sleep"
        case .noteContext: "bl.bodynote"
        }
    }
}

/// Small bar chart of the numbers behind an insight. The highlighted bar is the claim.
struct EvidenceChart: View {
    let points: [EvidencePoint]
    var tint: Color
    var height: CGFloat = 92

    var body: some View {
        Chart(points) { p in
            BarMark(x: .value("Label", p.label), y: .value("Value", p.value), width: .ratio(0.58))
                .foregroundStyle(p.highlighted ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Palette.baseline.opacity(0.45)))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 3) {
                    Text(short(p.value)).font(.system(size: 11, weight: .semibold).width(.condensed)).monospacedDigit()
                        .foregroundStyle(p.highlighted ? tint : Palette.secondaryInk)
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondaryInk) }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evidence")
        .accessibilityValue(points.map { "\($0.label): \(short($0.value))" }.joined(separator: ", "))
    }

    func short(_ v: Double) -> String {
        if v >= 10_000 { return Fmt.decimal(v / 1000, digits: 1) + "k" }
        if v >= 100 { return Fmt.int(v) }
        return Fmt.decimal(v, digits: v < 10 ? 1 : 0)
    }
}

struct WhyButton: View {
    var tint: Color = Palette.accent
    var title = "Why you're seeing this"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                BLIcon(name: "bl.evidence", size: 14)
                Text(title).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An insight as an accent-barred card: the claim, its evidence and where to go next.
struct InsightCard: View {
    let insight: Insight
    var featured = false
    var onWhy: () -> Void
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Eyebrow(text: featured ? "Worth knowing" : insight.label, icon: insight.icon, color: insight.tint)
                Spacer()
                Text("confidence \(insight.confidence.label.lowercased())")
                    .font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
            }
            Text(insight.headline)
                .font(featured ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let emphasis = insight.emphasis {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(emphasis).font(Typo.score(featured ? 44 : 32)).monospacedDigit().foregroundStyle(insight.tint)
                    if let c = insight.emphasisCaption {
                        Text(c).font(.footnote).foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            if featured, insight.points.count >= 2 {
                EvidenceChart(points: insight.points, tint: insight.tint)
            }
            Text(insight.explanation)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let caveat = insight.caveat {
                Label(caveat, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            HStack {
                WhyButton(tint: insight.tint, action: onWhy)
                Spacer()
                if let onOpen {
                    Button(action: onOpen) {
                        HStack(spacing: 4) {
                            Text("INSPECT").font(Typo.eyebrow).tracking(1.1)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(insight.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 6)
        .card(padding: featured ? Space.xl : Space.l, tone: featured ? .tinted(insight.tint) : .plain)
        .overlay(alignment: .leading) {
            Capsule().fill(insight.tint).frame(width: 3).padding(.vertical, 18).padding(.leading, 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The evidence trail behind an insight.
struct InsightExplanationSheet: View {
    let insight: Insight
    var updated: Date?
    var onAsk: ((String) -> Void)?
    var onOpen: ((DeepLink) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow(text: "Why you're seeing this", icon: "bl.evidence", color: insight.tint)
                        Text(insight.headline).font(Typo.title).foregroundStyle(Palette.ink)
                        Text(insight.explanation).foregroundStyle(Palette.secondaryInk)
                    }
                    if insight.points.count >= 2 {
                        EvidenceChart(points: insight.points, tint: insight.tint, height: 130).card()
                    }
                    KeyValueCard(title: "Measured", rows: insight.evidence.map { ($0.label, $0.value) })
                    KeyValueCard(title: "Reliability", rows: [("Observations", "\(insight.sampleCount)"),
                                                              ("Confidence", insight.confidence.label),
                                                              ("Data", insight.source)]
                        + (updated.map { [("Updated", $0.formatted(date: .abbreviated, time: .shortened))] } ?? []))
                    if let caveat = insight.caveat {
                        Label(caveat, systemImage: "exclamationmark.bubble")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Text("Compared against your own history, not population averages. Not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(Palette.tertiaryInk)

                    HStack(spacing: Space.m) {
                        if let onAsk {
                            Button {
                                dismiss()
                                onAsk("Tell me more about this: \(insight.headline)")
                            } label: {
                                Label("Ask about this", systemImage: "sparkles").frame(maxWidth: .infinity)
                            }
                            .glassButton(prominent: true)
                        }
                        if let onOpen, insight.link != .insight(insight.id) {
                            Button {
                                dismiss()
                                onOpen(insight.link)
                            } label: {
                                Label("See the records", systemImage: "chart.bar").frame(maxWidth: .infinity)
                            }
                            .glassButton()
                        }
                    }
                    .controlSize(.large)
                }
                .padding(Space.page)
            }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Label / value rows in a card, with a mono title.
struct KeyValueCard: View {
    var title: String?
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { Eyebrow(text: title).padding(.bottom, Space.xs) }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Space.m)
                    Text(row.1).fontWeight(.semibold).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing).monospacedDigit()
                }
                .font(.subheadline)
                .padding(.vertical, Space.m)
                if index < rows.count - 1 { Rectangle().fill(Palette.separator).frame(height: 1) }
            }
        }
        .card(padding: Space.l)
    }
}

// MARK: - Streaks and milestones

/// A thin progress ring with content in the middle.
struct StreakRing<Center: View>: View {
    let progress: Double
    var tint: Color = Palette.accent
    var lineWidth: CGFloat = 7
    @ViewBuilder var center: () -> Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [tint.opacity(0.5), tint, Palette.cyan], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.5), radius: 6)
            center()
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.reveal) { shown = min(1, max(0.02, progress)) }
        }
        .onChange(of: progress) { _, p in shown = min(1, max(0.02, p)) }
    }
}

extension Achievement {
    var icon: String {
        switch family {
        case .walking: "bl.steps"
        case .consistency: "bl.streak"
        case .history: "bl.calendar"
        case .sleep: "bl.sleep"
        case .body: "bl.bodynote"
        case .ask: "bl.sparkle"
        case .checkIn: "bl.target"
        }
    }

    var tint: Color {
        switch family {
        case .sleep: Palette.sleep
        case .body: Palette.note
        case .ask: Palette.cyan
        case .checkIn: Palette.mint
        default: Palette.cobalt
        }
    }
}

/// Hexagonal medallion for a milestone. Locked badges show progress, never a penalty.
struct AchievementBadge: View {
    let achievement: Achievement
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                if achievement.isUnlocked {
                    Hexagon().fill(LinearGradient(colors: [achievement.tint.opacity(0.9), achievement.tint.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                    Hexagon().stroke(achievement.tint, lineWidth: 1.5).padding(3)
                    BLIcon(name: achievement.icon, size: size * 0.38).foregroundStyle(Palette.canvas)
                } else {
                    Hexagon().fill(Palette.raised)
                    Hexagon().trim(from: 0, to: achievement.progress)
                        .stroke(achievement.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    BLIcon(name: achievement.icon, size: size * 0.36).foregroundStyle(Palette.baseline)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: achievement.isUnlocked ? achievement.tint.opacity(0.45) : .clear, radius: 10)
            Text(achievement.title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).lineLimit(2).frame(width: size + 24)
            Text((achievement.unlockedOn.map { Fmt.shortDate($0) } ?? achievement.progressText).uppercased())
                .font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(achievement.title). \(achievement.isUnlocked ? "Earned \(achievement.unlockedOn.map { Fmt.shortDate($0) } ?? "")" : achievement.progressText). \(achievement.detail)")
    }
}

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a = Double(i) * .pi / 3 - .pi / 2
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
