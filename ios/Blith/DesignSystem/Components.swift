import BlithCore
import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.sectionTitle)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.s)
            if let trailing, let action {
                Button(trailing, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A change vs a baseline. Deliberately neutral: an arrow and a number, no red/green verdict.
struct DeltaBadge: View {
    let change: Double
    var caption: String?

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption.weight(.bold))
            Text(Fmt.signedPercent(change))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let caption {
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Palette.accent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Fmt.percent(change)) \(change >= 0 ? "above" : "below") \(caption ?? "")")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(Typo.metric).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
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
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: 44)
                .background(Palette.accentSoft, in: Circle())
            Text(title).font(Typo.cardTitle)
            Text(message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, Space.xs)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

struct SampleDataBanner: View {
    var body: some View {
        Label("Sample data. Nothing here is from your health records.", systemImage: "flask")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.warm)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
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
        .foregroundStyle(.secondary)
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
                    Text(String(first).uppercased()).font(.system(.headline, design: .rounded, weight: .bold))
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

/// D / W / M / 6M / Y / All. Liquid Glass capsule with a morphing selection on iOS 26.
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
                        .foregroundStyle(selection == p ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selection == p {
                                Capsule().fill(Palette.accentSoft).matchedGeometryEffect(id: "sel", in: ns)
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { day in
                VStack(spacing: Space.s) {
                    Text(String(Fmt.weekdayShort[day.date.weekday - 1].prefix(1)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
            Circle().fill(Palette.accent).frame(width: 22, height: 22)
                .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
        case .inProgress:
            Circle().strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2.5, dash: [3, 3])).frame(width: 22, height: 22)
        case .notMet:
            Circle().fill(Palette.accentSoft).frame(width: 22, height: 22)
        case .noData, .future:
            Circle().strokeBorder(Palette.baseline.opacity(0.5), lineWidth: 1.5).frame(width: 22, height: 22)
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

struct InsightCard: View {
    let insight: Insight
    var onWhy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(insight.headline)
                    .font(Typo.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let emphasis = insight.emphasis {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(emphasis).font(Typo.number(30)).monospacedDigit()
                    if let c = insight.emphasisCaption {
                        Text(c).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Text(insight.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onWhy) {
                Label("Why am I seeing this?", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    var symbol: String {
        switch insight.kind {
        case .baselineChange, .momentum, .longTermChange: "chart.line.uptrend.xyaxis"
        case .consistency: "circle.dotted.circle"
        case .dayOfWeek, .weekdayDecline: "calendar"
        case .timing: "clock"
        case .personalBest: "star"
        case .pace: "speedometer"
        case .weightTrend, .weightActivity: "scalemass"
        case .rebound: "arrow.uturn.up"
        case .sleepMovement: "bed.double"
        }
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
                        Text(insight.headline).font(Typo.title)
                        Text(insight.explanation).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(insight.evidence.enumerated()), id: \.offset) { index, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.label).foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
                                Label("See data", systemImage: "chart.bar").frame(maxWidth: .infinity)
                            }
                            .glassButton()
                        }
                    }
                    .controlSize(.large)
                }
                .padding(Space.page)
            }
            .background(Palette.background)
            .navigationTitle("Why you're seeing this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: Space.m)
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, Space.m)
    }
}
