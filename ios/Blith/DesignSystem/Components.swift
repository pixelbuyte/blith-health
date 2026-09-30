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
            Text(text.uppercased()).font(Typo.eyebrow).tracking(0.9)
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
                Text(title).font(Typo.sectionTitle).foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Space.s)
            if let trailing, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(trailing).font(Typo.geist(13, .medium, relativeTo: .footnote))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Palette.signal)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
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
                .font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                .monospacedDigit()
            if let caption {
                Text(caption).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk).lineLimit(2)
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
            Text(title.uppercased()).font(Typo.eyebrow).tracking(0.8).foregroundStyle(Palette.tertiaryInk).lineLimit(1)
            Text(value).font(Typo.metric).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(Typo.geist(12, relativeTo: .caption)).foregroundStyle(Palette.secondaryInk).lineLimit(2)
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
            .font(Typo.geist(12, relativeTo: .caption))
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
            SignalGlyph(symbol: symbol, tint: Palette.signal, size: 44)
            VStack(alignment: .leading, spacing: Space.xs + 2) {
                Text(title).font(Typo.cardTitle).foregroundStyle(Palette.ink)
                Text(message).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(Typo.geist(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.signal)
                        .frame(minHeight: 44)
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
        HStack(spacing: 6) {
            Circle().fill(Palette.note).frame(width: 5, height: 5)
            Text("SAMPLE DATA").font(Typo.eyebrow).tracking(0.9)
        }
        .foregroundStyle(Palette.secondaryInk)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.raised))
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .accessibilityLabel("Showing sample data, not your health records")
    }
}

struct SyncStatusLine: View {
    let history: HealthHistory
    var isSyncing: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            if isSyncing {
                SignalPulse(size: 12)
                Text("Updating…")
            } else if let last = history.sync.lastSync {
                Image(systemName: history.sync.status == .failed ? "exclamationmark.circle" : "checkmark.circle")
                Text("\(history.origin.providerKind.displayName) · updated \(last.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(Typo.geist(12, relativeTo: .caption))
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
                    Text(String(first).uppercased()).font(Typo.geist(16, .semibold, relativeTo: .headline))
                } else {
                    Image(systemName: "person.fill").font(.subheadline)
                }
            }
            .foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44)
            .glassSurface(Circle(), interactive: true)
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
                        .font(Typo.mono(12, selection == p ? .medium : .regular))
                        .foregroundStyle(selection == p ? Palette.ink : Palette.tertiaryInk)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selection == p {
                                Capsule().fill(Palette.raised)
                                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                                    .overlay(alignment: .bottom) {
                                        Capsule().fill(Palette.signal).frame(width: 14, height: 2).padding(.bottom, 4)
                                    }
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
        .glassSurface(Capsule())
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
        case .met: shape.fill(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom)).frame(height: 30)
        case .inProgress: shape.strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(height: 30)
        case .notMet: shape.fill(Palette.sunken).frame(height: 30)
        case .noData, .future: shape.strokeBorder(Palette.hairline, lineWidth: 1).frame(height: 30)
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
                .foregroundStyle(p.highlighted ? AnyShapeStyle(tint) : AnyShapeStyle(Palette.quiet))
                .cornerRadius(5)
                .annotation(position: .top, spacing: 4) {
                    Text(short(p.value)).font(Typo.mono(11, p.highlighted ? .medium : .regular))
                        .foregroundStyle(p.highlighted ? Palette.ink : Palette.tertiaryInk)
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(Typo.mono(10)).foregroundStyle(Palette.tertiaryInk) }
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
                BLIcon(name: "bl.evidence", size: 15)
                Text(title).font(Typo.geist(14, .medium, relativeTo: .footnote))
            }
            .foregroundStyle(tint)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An insight: the claim in one sentence, the number that backs it, the evidence as a small
/// chart (highlighted bar = the claim), and where to look next. Resolves from dim to sharp.
struct InsightCard: View {
    let insight: Insight
    var featured = false
    var onWhy: () -> Void
    var onOpen: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var resolved = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                SignalGlyph(symbol: insight.icon, tint: insight.tint, size: 28)
                Text((featured ? "Worth knowing · " + insight.label : insight.label).uppercased())
                    .font(Typo.eyebrow).tracking(0.9).foregroundStyle(Palette.secondaryInk)
                Spacer()
                ConfidenceMeter(level: insight.confidence)
            }
            Text(insight.headline)
                .font(featured ? Typo.story : Typo.geist(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let emphasis = insight.emphasis {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(emphasis).font(Typo.score(featured ? 46 : 34)).foregroundStyle(insight.tint)
                    if let c = insight.emphasisCaption {
                        Text(c).font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            if featured, insight.points.count >= 2 {
                EvidenceChart(points: insight.points, tint: insight.tint)
            }
            Text(insight.explanation)
                .font(Typo.geist(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let caveat = insight.caveat {
                Label(caveat, systemImage: "info.circle")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiaryInk)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack {
                WhyButton(tint: insight.tint, action: onWhy)
                Spacer()
                if let onOpen {
                    Button(action: onOpen) {
                        HStack(spacing: 4) {
                            Text("See the days").font(Typo.geist(14, .medium, relativeTo: .footnote))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Palette.ink)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card(padding: featured ? Space.xl : Space.l, tone: featured ? .tinted(insight.tint) : .plain)
        .opacity(resolved ? 1 : 0.35)
        .blur(radius: resolved ? 0 : 3)
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.reveal) { resolved = true }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Three ticks that fill with confidence: shape, not colour, carries the level.
struct ConfidenceMeter: View {
    let level: InsightConfidence

    var body: some View {
        let filled = switch level { case .high: 3; case .moderate: 2; case .low: 1 }
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < filled ? Palette.ink : Palette.quiet).frame(width: 3, height: 6 + CGFloat(i) * 3)
                }
            }
            .frame(height: 12, alignment: .bottom)
            Text(level.label.uppercased()).font(Typo.eyebrow).tracking(0.8).foregroundStyle(Palette.tertiaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Confidence \(level.label)")
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
                        Text(insight.headline).font(Typo.story).foregroundStyle(Palette.ink)
                        Text(insight.explanation).font(Typo.body).foregroundStyle(Palette.secondaryInk)
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
                            .font(Typo.geist(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Text("Compared against your own history, not population averages. Not medical advice.")
                        .font(Typo.caption)
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
                    Text(row.0).font(Typo.geist(15, relativeTo: .subheadline)).foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Space.m)
                    Text(row.1).font(Typo.geist(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.trailing).monospacedDigit()
                }
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
            Circle().stroke(Palette.sunken, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
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
        case .checkIn: Palette.recovery
        default: Palette.signal
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
                    Hexagon().fill(LinearGradient(colors: [achievement.tint.opacity(0.28), achievement.tint.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    Hexagon().stroke(achievement.tint.opacity(0.9), lineWidth: 1.25)
                    Hexagon().stroke(achievement.tint.opacity(0.35), lineWidth: 0.75).padding(5)
                    BLIcon(name: achievement.icon, size: size * 0.36).foregroundStyle(achievement.tint)
                } else {
                    Hexagon().fill(Palette.raised)
                    Hexagon().stroke(Palette.hairline, lineWidth: 1)
                    Hexagon().trim(from: 0, to: achievement.progress)
                        .stroke(achievement.tint, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                    BLIcon(name: achievement.icon, size: size * 0.34).foregroundStyle(Palette.tertiaryInk)
                }
            }
            .frame(width: size, height: size)
            Text(achievement.title).font(Typo.geist(12, .semibold, relativeTo: .caption)).foregroundStyle(Palette.ink)
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
            let a: CGFloat = CGFloat(i) * .pi / 3 - .pi / 2
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - v4 primitives

/// A glyph in a soft tinted disc with a hairline ring: the one way Blith presents an icon.
struct SignalGlyph: View {
    let symbol: String
    var tint: Color = Palette.signal
    var size: CGFloat = 36

    var body: some View {
        BLIcon(name: symbol, size: size * 0.5)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.12)))
            .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// "Something is being understood": a soft signal that breathes instead of spinning.
struct SignalPulse: View {
    var size: CGFloat = 48
    var tint: Color = Palette.signal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.12)).scaleEffect(phase ? 1 : 0.55)
            Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1).scaleEffect(phase ? 0.8 : 0.5)
            Circle().fill(tint).frame(width: size * 0.18, height: size * 0.18)
        }
        .frame(width: size, height: size)
        .onAppear { if !reduceMotion { withAnimation(Motion.breathe) { phase = true } } else { phase = true } }
        .accessibilityLabel("Loading")
    }
}

/// A score band said three ways: glyph, word and luminance.
struct BandChip: View {
    let band: ScoreBand?
    var label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: Palette.bandSymbol(band)).font(.system(size: 10, weight: .bold))
            Text(label.uppercased()).font(Typo.eyebrow).tracking(0.9)
        }
        .foregroundStyle(Palette.band(band))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.band(band).opacity(0.12)))
        .overlay(Capsule().strokeBorder(Palette.band(band).opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Light / dark / system, chosen in Profile.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, dark, light
    static let key = "blith.appearance"
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "Match iPhone"; case .dark: "Dark"; case .light: "Light" }
    }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .dark: .dark; case .light: .light }
    }
    static var current: AppearancePreference {
        AppearancePreference(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }
}
