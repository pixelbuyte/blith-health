import SwiftUI

/// What Bli is doing. Drive it from real app state and use it sparingly: onboarding, useful
/// empty states, one important insight, and the assistant.
enum MascotPose: String, CaseIterable, Identifiable {
    case idle, waving, walking, thinking, listening, sleeping, noticing, celebrating, pointing
    var id: String { rawValue }
}

/// Bli, Blith's companion: one silhouette and one face, drawn and animated on device from the
/// same geometry as `design/mascot/model-sheet.html` (120 × 140 design box). Poses only move
/// limbs, eyes and props, so the character never changes shape between screens.
///
/// Decorative: hidden from VoiceOver. The clock runs only while visible, the scene is active and
/// Reduce Motion is off; otherwise the pose's stable frame is shown.
struct BlithMascot: View {
    var pose: MascotPose = .idle
    var size: CGFloat = 96
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    private var running: Bool { animated && visible && !reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
            Canvas { context, canvasSize in
                let t = running ? timeline.date.timeIntervalSinceReferenceDate : 0
                MascotRenderer.draw(&context, size: canvasSize, pose: pose, t: t)
            }
        }
        .frame(width: size, height: size * 140 / 120)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }
}

enum MascotRenderer {
    static let top = Color(hex: 0x5B8CFF)
    static let bottom = Color(hex: 0x2447E8)
    static let limbColor = Color(hex: 0x2146DD)
    static let foot = Color(hex: 0x1A34B0)
    static let ink = Color(hex: 0x0B1230)
    static let cyan = Color(hex: 0x3FD0FF)
    static let coral = Color(hex: 0xFF8A7A)
    static let amber = Color(hex: 0xFFB23F)
    static let belly = Color(hex: 0x8FB8FF)

    enum Eyes { case open, up, side, closed, wide, happy, right }

    struct Rig {
        var leftArm: Double
        var rightArm: Double
        var leftLeg: Double = 0
        var rightLeg: Double = 0
        var eyes: Eyes = .open
        var tilt: Double = 0
        var squash: Double = 1
        var bob: Double = 0
    }

    static func rig(_ pose: MascotPose, t: Double) -> Rig {
        let s = { (period: Double) in sin(t * 2 * .pi / period) }
        var r: Rig
        switch pose {
        case .idle: r = Rig(leftArm: 18, rightArm: 18)
        case .waving: r = Rig(leftArm: 18, rightArm: 150 + 14 * s(0.7))
        case .walking:
            let w = s(0.9)
            r = Rig(leftArm: -4 - 20 * w, rightArm: 4 + 22 * w, leftLeg: 18 * w, rightLeg: -18 * w, bob: -2 * abs(w))
        case .thinking: r = Rig(leftArm: 14, rightArm: -150, eyes: .up)
        case .listening: r = Rig(leftArm: 14, rightArm: 14, eyes: .side, tilt: -8 + 2 * s(2.4))
        case .sleeping: r = Rig(leftArm: 6, rightArm: 6, eyes: .closed, squash: 0.96 + 0.012 * s(4))
        case .noticing: r = Rig(leftArm: 18, rightArm: 60 + 6 * s(1.6), eyes: .wide)
        case .celebrating: r = Rig(leftArm: 150 + 10 * s(0.5), rightArm: 150 - 10 * s(0.5), leftLeg: 8, rightLeg: 8, eyes: .happy, bob: -4 - 3 * abs(s(0.8)))
        case .pointing: r = Rig(leftArm: 16, rightArm: 92 + 4 * s(1.4), eyes: .right)
        }
        // Breathing everywhere; blink when the eyes are open.
        if pose != .sleeping { r.squash *= 1 + 0.012 * s(3.2) }
        if [Eyes.open, .right, .side].contains(r.eyes), t > 0, t.truncatingRemainder(dividingBy: 4.3) < 0.13 { r.eyes = .closed }
        return r
    }

    static var bodyPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 60, y: 36))
        p.addCurve(to: CGPoint(x: 100, y: 84), control1: CGPoint(x: 86, y: 36), control2: CGPoint(x: 100, y: 58))
        p.addCurve(to: CGPoint(x: 60, y: 124), control1: CGPoint(x: 100, y: 108), control2: CGPoint(x: 84, y: 124))
        p.addCurve(to: CGPoint(x: 20, y: 84), control1: CGPoint(x: 36, y: 124), control2: CGPoint(x: 20, y: 108))
        p.addCurve(to: CGPoint(x: 60, y: 36), control1: CGPoint(x: 20, y: 58), control2: CGPoint(x: 34, y: 36))
        p.closeSubpath()
        return p
    }

    static var curlPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 60, y: 38))
        p.addCurve(to: CGPoint(x: 76, y: 14), control1: CGPoint(x: 57, y: 27), control2: CGPoint(x: 63, y: 17))
        p.addCurve(to: CGPoint(x: 60, y: 38), control1: CGPoint(x: 74, y: 23), control2: CGPoint(x: 69, y: 32))
        p.closeSubpath()
        return p
    }

    static func limb(_ ctx: inout GraphicsContext, pivot: CGPoint, angle: Double, right: Bool, length: CGFloat,
                     width: CGFloat, color: Color) {
        let a = angle * .pi / 180
        let end = CGPoint(x: pivot.x + CGFloat(sin(a)) * length * (right ? 1 : -1), y: pivot.y + CGFloat(cos(a)) * length)
        var p = Path()
        p.move(to: pivot)
        p.addLine(to: end)
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    static func draw(_ context: inout GraphicsContext, size: CGSize, pose: MascotPose, t: Double) {
        let scale = min(size.width / 120, size.height / 140)
        context.translateBy(x: (size.width - 120 * scale) / 2, y: (size.height - 140 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let r = rig(pose, t: t)

        var body = context
        body.translateBy(x: 60, y: 124 + r.bob)
        body.rotate(by: .degrees(r.tilt))
        body.scaleBy(x: 1, y: r.squash)
        body.translateBy(x: -60, y: -124)

        limb(&body, pivot: CGPoint(x: 47, y: 118), angle: r.leftLeg, right: false, length: 13, width: 12, color: foot)
        limb(&body, pivot: CGPoint(x: 73, y: 118), angle: r.rightLeg, right: true, length: 13, width: 12, color: foot)
        if r.leftArm >= 0 { limb(&body, pivot: CGPoint(x: 24, y: 90), angle: r.leftArm, right: false, length: 22, width: 10, color: limbColor) }
        if r.rightArm >= 0 { limb(&body, pivot: CGPoint(x: 96, y: 90), angle: r.rightArm, right: true, length: 22, width: 10, color: limbColor) }

        body.fill(bodyPath, with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: 60, y: 36), endPoint: CGPoint(x: 60, y: 124)))
        body.fill(ellipse(60, 100, 22, 17), with: .color(belly.opacity(0.28)))
        var shine = body
        shine.translateBy(x: 42, y: 54)
        shine.rotate(by: .degrees(-32))
        shine.fill(ellipse(0, 0, 10, 5.5), with: .color(.white.opacity(0.35)))
        body.fill(curlPath, with: .color(cyan))
        body.fill(ellipse(37, 89, 5, 3), with: .color(coral.opacity(0.5)))
        body.fill(ellipse(83, 89, 5, 3), with: .color(coral.opacity(0.5)))

        for x in [CGFloat(47), 73] {
            switch r.eyes {
            case .closed:
                var p = Path()
                p.move(to: CGPoint(x: x - 5, y: 77))
                p.addQuadCurve(to: CGPoint(x: x + 5, y: 77), control: CGPoint(x: x, y: 81))
                body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            case .happy:
                var p = Path()
                p.move(to: CGPoint(x: x - 5, y: 79))
                p.addQuadCurve(to: CGPoint(x: x + 5, y: 79), control: CGPoint(x: x, y: 72))
                body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            default:
                let ry: CGFloat = r.eyes == .wide ? 8.5 : 7
                body.fill(ellipse(x, 76, 5.5, ry), with: .color(ink))
                let glint: CGPoint
                switch r.eyes {
                case .up: glint = CGPoint(x: 0.8, y: -4.2)
                case .side: glint = CGPoint(x: -1.6, y: -2.4)
                case .right: glint = CGPoint(x: 2.6, y: -2.2)
                default: glint = CGPoint(x: 1.6, y: -2.6)
                }
                body.fill(ellipse(x + glint.x, 76 + glint.y, 1.9, 1.9), with: .color(.white))
            }
        }
        if pose == .sleeping {
            body.fill(ellipse(60, 93, 2.4, 1.6), with: .color(ink))
        } else {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 54, y: 91))
            mouth.addQuadCurve(to: CGPoint(x: 66, y: 91), control: CGPoint(x: 60, y: 97))
            body.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        if r.leftArm < 0 { limb(&body, pivot: CGPoint(x: 24, y: 90), angle: r.leftArm, right: false, length: 22, width: 10, color: limbColor) }
        if r.rightArm < 0 { limb(&body, pivot: CGPoint(x: 96, y: 90), angle: r.rightArm, right: true, length: 22, width: 10, color: limbColor) }

        drawProps(&context, pose: pose, t: t)
    }

    static func drawProps(_ ctx: inout GraphicsContext, pose: MascotPose, t: Double) {
        let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 1.4)
        switch pose {
        case .thinking:
            for (i, dot) in [(98.0, 40.0, 2.5), (106.0, 30.0, 3.2), (112.0, 18.0, 4.0)].enumerated() {
                let phase = t == 0 ? 1 : 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 3 - Double(i) * 0.9))
                ctx.fill(ellipse(dot.0, dot.1, dot.2, dot.2), with: .color(cyan.opacity(phase)))
            }
        case .listening:
            for (i, w) in [(104.0, 70.0, 86.0, 110.0), (110.0, 64.0, 92.0, 119.0)].enumerated() {
                var p = Path()
                p.move(to: CGPoint(x: w.0, y: w.1))
                p.addQuadCurve(to: CGPoint(x: w.0, y: w.2), control: CGPoint(x: w.3, y: (w.1 + w.2) / 2))
                let o = t == 0 ? (i == 0 ? 1 : 0.6) : (i == 0 ? 0.5 + 0.5 * pulse : 0.3 + 0.5 * (1 - pulse))
                ctx.stroke(p, with: .color(cyan.opacity(o)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        case .sleeping:
            let drift = t == 0 ? 0 : (t.truncatingRemainder(dividingBy: 3) / 3)
            ctx.draw(Text("z").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(cyan),
                     at: CGPoint(x: 100, y: 40 - 8 * drift))
            ctx.draw(Text("z").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(cyan.opacity(0.7)),
                     at: CGPoint(x: 110, y: 26 - 8 * drift))
        case .noticing:
            var star = Path()
            let s = t == 0 ? 1 : 0.85 + 0.25 * pulse
            let c = CGPoint(x: 100, y: 41)
            for (i, pt) in [(0.0, -11.0), (3.0, -3.0), (11.0, 0.0), (3.0, 3.0), (0.0, 11.0), (-3.0, 3.0), (-11.0, 0.0), (-3.0, -3.0)].enumerated() {
                let p = CGPoint(x: c.x + pt.0 * s, y: c.y + pt.1 * s)
                if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(amber))
        case .celebrating:
            let colors = [cyan, coral, amber, cyan, amber, top]
            for (i, pt) in [(18.0, 34.0), (104.0, 30.0), (12.0, 60.0), (110.0, 58.0), (30.0, 22.0), (90.0, 18.0)].enumerated() {
                let fall = t == 0 ? 0 : 4 * sin(t * 2 + Double(i))
                let rect = Path(roundedRect: CGRect(x: -2.5, y: -2.5, width: 5, height: 5), cornerRadius: 1.5)
                    .applying(CGAffineTransform(rotationAngle: CGFloat(0.4 + Double(i) + t)))
                    .applying(CGAffineTransform(translationX: pt.0, y: pt.1 + fall))
                ctx.fill(rect, with: .color(colors[i]))
            }
        default:
            break
        }
    }
}
