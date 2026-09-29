import BlithCore
import SwiftUI

/// Latest synced measurement; never labels a cached sample as a continuous live feed.
struct HeartRateCard: View {
    @Environment(AppModel.self) private var app
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monitor = HeartRateMonitor()
    @State private var visible = false
    @State private var permissionRevision = 0
    @State private var requesting = false

    private var enabled: Bool { visible && scenePhase == .active && router.tab == .today }
    private var connected: Bool { app.history?.requestedCategories.contains(.heart) == true }
    private var taskID: String {
        "\(app.mode?.storageValue ?? "none")-\(enabled)-\(connected)-\(permissionRevision)"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let reading = monitor.reading
            let recent = reading?.isRecent(at: timeline.date) == true
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(text: "Heart rate", color: Palette.heart)
                HStack(alignment: .center, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(reading.map { Fmt.int($0.bpm) } ?? "–")
                            .font(Typo.score(50)).foregroundStyle(Palette.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                        Text("BPM").font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(reading.map { "\(Fmt.int($0.bpm)) beats per minute" } ?? "No heart rate reading")
                    Spacer(minLength: 0)
                    HeartBeatGlyph(interval: reading?.beatInterval ?? 1,
                                   animating: enabled && !reduceMotion && (recent || app.isDemo))
                }
                if let reading {
                    Text(app.isDemo ? "Sample data" : (recent ? "Recent reading" : "Latest reading"))
                        .font(Typo.eyebrow).foregroundStyle(Palette.secondaryInk)
                    if !app.isDemo {
                        Text(reading.measuredAt, style: .relative) + Text(" ago")
                    }
                    if !app.isDemo { Text(reading.source.name).lineLimit(2) }
                    Text(app.isDemo ? "Example pulse · 72 BPM" : "Updates with Apple Health")
                } else {
                    Text(monitor.failed ? "Couldn't read heart rate" : "No reading available")
                    Button(monitor.needsPermission ? "Connect heart rate" : "Check access") {
                        Task {
                            requesting = true
                            await app.connectMore([.heart])
                            requesting = false
                            permissionRevision += 1
                        }
                    }
                    .disabled(requesting || app.isDemo || !app.healthKitAvailable)
                    .buttonStyle(.borderless)
                    .tint(Palette.heart)
                    Text("From a watch or heart-rate sensor")
                }
            }
            .font(Typo.geist(12, relativeTo: .caption))
            .foregroundStyle(Palette.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Space.l)
            .accessibilityElement(children: .contain)
        }
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .onDisappear { visible = false }
        .task(id: taskID) {
            await monitor.run(provider: app.healthKit, mode: app.mode, enabled: enabled, connected: connected)
        }
    }
}

private struct HeartBeatGlyph: View {
    let interval: TimeInterval
    let animating: Bool

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 27, weight: .medium))
            .foregroundStyle(Palette.heart)
            .keyframeAnimator(initialValue: 1.0, repeating: animating) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    CubicKeyframe(1.13, duration: interval * 0.12)
                    CubicKeyframe(1.0, duration: interval * 0.14)
                    CubicKeyframe(1.07, duration: interval * 0.10)
                    CubicKeyframe(1.0, duration: interval * 0.18)
                    LinearKeyframe(1.0, duration: interval * 0.46)
                }
            }
            .id("\(interval)-\(animating)")
            .frame(width: 38, height: 44)
            .accessibilityHidden(true)
    }
}
