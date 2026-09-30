import BlithCore
import SwiftUI

/// The acquisition lifecycle belongs to Today; scrolling only pauses the artwork.
struct HeartRateCard: View {
    let monitor: HeartRateMonitor
    let isDemo: Bool
    let active: Bool
    let canConnect: Bool
    let requesting: Bool
    let onConnect: () -> Void
    var expanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        // Stable container: swapping the clock subtree must not trigger our own disappearance.
        VStack(spacing: 0) {
            if active && visible {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    card(at: timeline.date)
                }
            } else {
                card(at: Date())
            }
        }
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .onDisappear { visible = false }
    }

    private func card(at now: Date) -> some View {
        let reading = monitor.reading
        let recent = reading?.isRecent(at: now) == true
        let animating = reading != nil && active && visible && !reduceMotion && (recent || isDemo)
        return VStack(spacing: Space.m) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    title
                    Spacer(minLength: Space.s)
                    status(recent: recent)
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    title
                    status(recent: recent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HeartRateArtwork(bpm: reading?.bpm, interval: reading?.beatInterval ?? 1,
                             animating: animating, expanded: expanded)

            if let reading {
                VStack(spacing: Space.xs) {
                    if isDemo {
                        Text("Example reading · \(Fmt.int(reading.bpm)) BPM")
                    } else {
                        Text(reading.source.name)
                        Text("Measured \(reading.measuredAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(Typo.caption).foregroundStyle(Palette.tertiaryInk)
                    }
                    if expanded {
                        Text(isDemo ? "This pulse uses sample data."
                             : "Updates when Apple Health receives a measurement. The pulse follows this reading’s rate.")
                            .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                            .padding(.top, Space.s)
                    }
                }
                .font(Typo.cardTitle).foregroundStyle(Palette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Space.s) {
                    Text(monitor.failed ? "Heart rate is unavailable right now" : "Waiting for your first reading")
                        .font(Typo.cardTitle).foregroundStyle(Palette.ink)
                    Text("Share heart-rate readings from your watch or sensor through Apple Health.")
                        .font(Typo.caption).foregroundStyle(Palette.secondaryInk)
                    Button(action: onConnect) {
                        Text(requesting ? "Connecting…" : (monitor.needsPermission ? "Connect heart rate" : "Check Health access"))
                            .font(Typo.cardTitle).padding(.horizontal, Space.l).padding(.vertical, Space.m)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.heart)
                    .background(Palette.heart.opacity(0.10), in: Capsule())
                    .disabled(requesting || !canConnect || isDemo)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: Space.xl, tone: .tinted(Palette.heart))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Heart rate")
    }

    private var title: some View {
        Text("Heart rate").font(Typo.sectionTitle).foregroundStyle(Palette.ink)
    }

    private func status(recent: Bool) -> some View {
        Label(isDemo ? "Sample data" : (monitor.reading == nil ? "No reading" : (recent ? "Recent reading" : "Latest reading")),
              systemImage: isDemo ? "flask" : (recent ? "waveform.path" : "clock"))
            .font(Typo.eyebrow)
            .foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
            .background(Palette.raised, in: Capsule())
    }
}

/// Native SF heart; the BPM stays stationary while the silhouette gives a subtle double-thump.
private struct HeartRateArtwork: View {
    let bpm: Double?
    let interval: TimeInterval
    let animating: Bool
    let expanded: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, min(geometry.size.width - 24, expanded ? 270.0 : 230.0))
            ZStack {
                if animating {
                    silhouette(width: width)
                        .keyframeAnimator(initialValue: 1.0, repeating: true) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            KeyframeTrack(\.self) {
                                CubicKeyframe(1.035, duration: interval * 0.12)
                                CubicKeyframe(1.0, duration: interval * 0.14)
                                CubicKeyframe(1.018, duration: interval * 0.10)
                                CubicKeyframe(1.0, duration: interval * 0.18)
                                LinearKeyframe(1.0, duration: interval * 0.46)
                            }
                        }
                        .id(interval)
                } else {
                    silhouette(width: width)
                }
                VStack(spacing: 0) {
                    Text(bpm.map { Fmt.int($0) } ?? "–")
                        .font(Typo.score(expanded ? 78 : 68, weight: .regular))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("BPM").font(Typo.mono(12, .medium))
                }
                .foregroundStyle(bpm == nil ? Palette.ink : .white)
                .frame(width: width * 0.58)
                .offset(y: -width * 0.045)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: expanded ? 255 : 215)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bpm.map { "\(Fmt.int($0)) beats per minute" } ?? "No heart-rate measurement")
    }

    private func silhouette(width: CGFloat) -> some View {
        Image(systemName: "heart.fill")
            .resizable().scaledToFit()
            .foregroundStyle(LinearGradient(stops: [
                .init(color: Palette.heartHighlight, location: 0),
                .init(color: Palette.heartBody, location: 0.42),
                .init(color: Palette.heartDepth, location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: width, height: width * 0.88)
            .shadow(color: Palette.heartBody.opacity(bpm == nil ? 0.08 : 0.22), radius: 18, y: 10)
            .opacity(bpm == nil ? 0.35 : 1)
            .accessibilityHidden(true)
    }
}
