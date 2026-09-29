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

/// Spaced mono label above a story ("TODAY · 3:30 PM").
struct Eyebrow: View {
    let text: String
    var icon: String?
    var color: Color = Palette.secondaryInk

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            if let icon { BLIcon(name: icon, size: 13) }
            Text(text.uppercased()).font(Typo.eyebrow).tracking(1.4)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.sectionTitle).foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Space.s)
            if let trailing, let action {
                Button(trailing, action: action).font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A change vs a baseline. Neutral by design: an arrow and a number, no red/green verdict.
struct DeltaBadge: View {
    let change: Double
    var caption: String?
    var tint: Color = Palette.accent

    var body: some View {
        let flat = Int((change * 100).rounded()) == 0
        HStack(spacing: Space.xs) {
            Image(systemName: flat ? "equal" : (change >= 0 ? "arrow.up.right" : "arrow.down.right"))
                .font(.caption.weight(.bold))
            Text(flat ? "About the same" : Fmt.signedPercent(change))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let caption {
                Text(caption).font(.subheadline).foregroundStyle(tint.opacity(0.75)).lineLimit(2)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.secondaryInk)
            Text(value).font(Typo.metric).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
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
    var mascot: MascotPose?

    var body: some View {
        HStack(alignment: .top, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.s) {
                if mascot == nil {
                    BLIcon(name: symbol, size: 22)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 44, height: 44)
                        .background(Palette.accentSoft, in: Circle())
                }
                Text(title).font(Typo.storySmall).foregroundStyle(Palette.ink)
                Text(message).font(.subheadline).foregroundStyle(Palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, Space.xs)
                }
            }
            if let mascot {
                Spacer(minLength: 0)
                BlithMascot(pose: mascot, size: 64)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

/// Sample data is always labelled, but compactly: an amber capsule, not a banner.
struct SampleDataBanner: View {
    var body: some View {
        Label {
            Text("Sample data").font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: "flask.fill").font(.caption2)
        }
        .foregroundStyle(Palette.review)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.reviewSoft, in: Capsule())
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
        .foregroundStyle(Palette.secondaryInk)
        .frame(maxWidth: .infinity)
    }
}

/// Top-right profile entry point. Glass circle with the user's initial.
struct AvatarButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let first = name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(first).uppercased()).font(.system(.headline, design: .serif, weight: .bold))
                } else {
                    Image(systemName: "person.fill").font(.headline)
                }
            }
            .foregroundStyle(Palette.accent)
            .frame(width: 44, height: 44)
            .glassSurface(Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
    }
}

/// D / W / M / 6M / Y / All. Liquid Glass capsule with a morphing selection.
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
                    Text(p.shortTitle)
                        .font(.subheadline.weight(selection == p ? .bold : .medium))
                        .foregroundStyle(selection == p ? Color.white : Palette.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selection == p {
                                Capsule().fill(Palette.cobalt).matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(selection == p ? .isSelected : [])
            }
        }
        .padding(4)
        .glassSurface(Capsule())
    }
}

/// Seven soft dots for the week. Filled = at or near the user's usual; nothing is "broken".
struct ConsistencyDots: View {
    let week: WeekConsistency
    var tint: Color = Palette.accent

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { day in
                VStack(spacing: Space.s) {
                    Text(String(Fmt.weekdayShort[day.date.weekday - 1].prefix(1)))
                        .font(Typo.eyebrow)
                        .foregroundStyle(Palette.secondaryInk)
                    dot(day.state)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(day))
            }
        }
    }

    @ViewBuilder
    func dot(_ state: WeekConsistency.DayState) -> some View {
        switch state {
        case .met:
            Circle().fill(tint).frame(width: 26, height: 26)
                .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white))
        case .inProgress:
            Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: 2.5, dash: [3, 3])).frame(width: 26, height: 26)
        case .notMet:
            Circle().fill(tint.opacity(0.16)).frame(width: 26, height: 26)
        case .noData, .future:
            Circle().strokeBorder(Palette.baseline.opacity(0.4), lineWidth: 1.5).frame(width: 26, height: 26)
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
    /// The color family an insight belongs to.
    var tint: Color {
        switch kind {
        case .sleepMovement, .sleepTiming: Palette.sleep
        case .weightTrend, .weightActivity: Palette.weight
        case .noteContext: Palette.note
        default: Palette.cobalt
        }
    }

    var icon: String {
        switch kind {
        case .baselineChange, .momentum, .longTermChange: "bl.progress"
        case .consistency: "bl.streak"
        case .dayOfWeek, .weekdayDecline: "bl.calendar"
        case .timing: "bl.steptrail"
        case .personalBest: "bl.medal"
        case .pace: "bl.walk"
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
            BarMark(x: .value("Label", p.label), y: .value("Value", p.value), width: .ratio(0.62))
                .foregroundStyle(p.highlighted ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Palette.baseline.opacity(0.35)))
                .cornerRadius(6)
                .annotation(position: .top, spacing: 3) {
                    Text(short(p.value)).font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(p.highlighted ? tint : Palette.secondaryInk)
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.caption2) }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                BLIcon(name: "bl.evidence", size: 15)
                Text("Why you're seeing this").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The main insight on Today: a story, its evidence, and where to go next.
struct InsightCard: View {
    let insight: Insight
    var featured = false
    var onWhy: () -> Void
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top) {
                Eyebrow(text: featured ? "Worth knowing" : insight.confidence.label, icon: insight.icon, color: insight.tint)
                Spacer()
                if featured { BlithMascot(pose: .noticing, size: 46).offset(y: -6) }
            }
            Text(insight.headline)
                .font(featured ? Typo.story : Typo.storySmall)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let emphasis = insight.emphasis {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(emphasis).font(Typo.number(featured ? 34 : 26)).monospacedDigit().foregroundStyle(insight.tint)
                    if let c = insight.emphasisCaption {
                        Text(c).font(.subheadline).foregroundStyle(Palette.secondaryInk)
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
                            Text("Inspect").font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(insight.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card(padding: featured ? Space.xl : Space.l, tone: featured ? .tinted(insight.tint) : .plain)
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
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: "Measured").padding(.bottom, Space.s)
                        ForEach(Array(insight.evidence.enumerated()), id: \.offset) { index, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.label).foregroundStyle(Palette.secondaryInk)
                                Spacer(minLength: Space.m)
                                Text(row.value).fontWeight(.semibold).multilineTextAlignment(.trailing).monospacedDigit()
                            }
                            .font(.subheadline)
                            .padding(.vertical, Space.m)
                            if index < insight.evidence.count - 1 { Divider() }
                        }
                    }
                    .card(padding: Space.l)

                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: "Reliability").padding(.bottom, Space.s)
                        row("Observations", "\(insight.sampleCount)")
                        Divider()
                        row("Reliability", insight.confidence.label)
                        Divider()
                        row("Data", insight.source)
                        if let updated {
                            Divider()
                            row("Updated", updated.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .card(padding: Space.l)

                    if let caveat = insight.caveat {
                        Label(caveat, systemImage: "exclamationmark.bubble")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    Text("Compared against your own history, not population averages. Not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)

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
            .background(Palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Space.m)
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, Space.m)
    }
}

// MARK: - Streaks and milestones

/// A soft progress ring with content in the middle.
struct StreakRing<Center: View>: View {
    let progress: Double
    var tint: Color = Palette.accent
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: () -> Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [tint.opacity(0.6), tint, Palette.cyan], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = min(1, max(0.02, progress)) }
        }
        .onChange(of: progress) { _, p in shown = min(1, max(0.02, p)) }
    }
}

extension Achievement {
    var icon: String {
        switch family {
        case .walking: "bl.walk"
        case .consistency: "bl.streak"
        case .history: "bl.calendar"
        case .sleep: "bl.sleep"
        case .body: "bl.bodynote"
        case .ask: "bl.sparkle"
        case .checkIn: "bl.today"
        }
    }

    var tint: Color {
        switch family {
        case .sleep: Palette.sleep
        case .body: Palette.note
        case .ask: Palette.cyan
        default: Palette.cobalt
        }
    }
}

/// Medallion for a milestone. Locked badges show progress, never a penalty.
struct AchievementBadge: View {
    let achievement: Achievement
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                if achievement.isUnlocked {
                    Circle().fill(LinearGradient(colors: [achievement.tint, achievement.tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(.white.opacity(0.45), lineWidth: 2).padding(4)
                    BLIcon(name: achievement.icon, size: size * 0.4).foregroundStyle(.white)
                } else {
                    Circle().fill(Palette.cardRaised)
                    Circle().trim(from: 0, to: achievement.progress)
                        .stroke(achievement.tint.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(2)
                    BLIcon(name: achievement.icon, size: size * 0.38).foregroundStyle(Palette.baseline)
                }
            }
            .frame(width: size, height: size)
            Text(achievement.title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center).lineLimit(2).frame(width: size + 24)
            Text(achievement.unlockedOn.map { Fmt.shortDate($0) } ?? achievement.progressText)
                .font(.caption2).foregroundStyle(Palette.secondaryInk).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(achievement.title). \(achievement.isUnlocked ? "Earned \(achievement.unlockedOn.map { Fmt.shortDate($0) } ?? "")" : achievement.progressText). \(achievement.detail)")
    }
}
