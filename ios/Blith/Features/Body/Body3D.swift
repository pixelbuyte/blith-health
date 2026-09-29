import BlithCore
import SceneKit
import SwiftUI
import UIKit

// MARK: - Model

/// The 3D figure: a male body generated from MakeHuman's CC0 base mesh by
/// `design/body3d/build_body.py`. Triangles are grouped by `BodyRegion`, so each region is its own
/// geometry element (and material) — tapping returns the region directly, and notes stay anchored
/// to regions, never to screen points.
final class Body3DModel {
    struct Region: Decodable {
        let id: String
        let anchor: [Float]
        let normal: [Float]
        let radius: Float
    }

    struct Muscle: Decodable {
        let id: String
        let name: String
        let anchor: [Float]
        let normal: [Float]
    }

    struct Meta: Decodable {
        let height: Float
        let regions: [Region]
        let muscles: [Muscle]
    }

    struct Group {
        let region: Int
        let firstTriangle: Int
        let count: Int
    }

    let meta: Meta
    let geometry: SCNGeometry
    let groups: [Group]
    let musclePerTriangle: [UInt8]

    static let shared: Body3DModel? = Body3DModel()

    private init?() {
        guard let binURL = Bundle.main.url(forResource: "body", withExtension: "bin"),
              let jsonURL = Bundle.main.url(forResource: "body3d", withExtension: "json"),
              let data = try? Data(contentsOf: binURL, options: .mappedIfSafe),
              let json = try? Data(contentsOf: jsonURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: json),
              data.count > 16, String(data: data.prefix(4), encoding: .ascii) == "BLB2" else { return nil }

        func u32(_ offset: Int) -> Int {
            Int(data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        }
        let v = u32(4), t = u32(8), g = u32(12)
        var offset = 16
        let posOffset = offset; offset += v * 12
        let nrmOffset = offset; offset += v * 12
        let uvOffset = offset; offset += v * 8
        var groups: [Group] = []
        for i in 0..<g {
            let o = offset + i * 12
            groups.append(Group(region: u32(o), firstTriangle: u32(o + 4), count: u32(o + 8)))
        }
        offset += g * 12
        let muscles = [UInt8](data.subdata(in: offset..<offset + t)); offset += t
        let indexOffset = offset
        guard data.count >= indexOffset + t * 12 else { return nil }

        let positions = SCNGeometrySource(data: data.subdata(in: posOffset..<posOffset + v * 12), semantic: .vertex, vectorCount: v,
                                          usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let normals = SCNGeometrySource(data: data.subdata(in: nrmOffset..<nrmOffset + v * 12), semantic: .normal, vectorCount: v,
                                        usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let uvs = SCNGeometrySource(data: data.subdata(in: uvOffset..<uvOffset + v * 8), semantic: .texcoord, vectorCount: v,
                                    usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let elements = groups.map { grp in
            let start = indexOffset + grp.firstTriangle * 12
            return SCNGeometryElement(data: data.subdata(in: start..<start + grp.count * 12), primitiveType: .triangles,
                                      primitiveCount: grp.count, bytesPerIndex: 4)
        }
        self.meta = meta
        self.groups = groups
        self.musclePerTriangle = muscles
        self.geometry = SCNGeometry(sources: [positions, normals, uvs], elements: elements)
    }

    func region(forElement index: Int) -> BodyRegion? {
        guard groups.indices.contains(index), meta.regions.indices.contains(groups[index].region) else { return nil }
        return BodyRegion(rawValue: meta.regions[groups[index].region].id)
    }

    func muscle(forElement index: Int, face: Int) -> Muscle? {
        guard groups.indices.contains(index) else { return nil }
        let tri = groups[index].firstTriangle + face
        guard musclePerTriangle.indices.contains(tri) else { return nil }
        let m = Int(musclePerTriangle[tri])
        return meta.muscles.indices.contains(m) ? meta.muscles[m] : nil
    }

    func info(for region: BodyRegion) -> Region? { meta.regions.first { $0.id == region.rawValue } }
}

extension Array where Element == Float {
    var vector: SCNVector3 { count >= 3 ? SCNVector3(self[0], self[1], self[2]) : SCNVector3Zero }
}

// MARK: - Scene

enum BodyLayer: String, CaseIterable, Identifiable {
    case skin, muscle
    var id: String { rawValue }
    var title: String { self == .skin ? "Figure" : "Muscles" }
}

/// Owns the SceneKit scene and all camera moves. Rotation is a turntable around the body's
/// vertical axis; zoom moves the camera toward a target point on the body.
@MainActor
final class BodySceneController: NSObject {
    let scene = SCNScene()
    let model: Body3DModel
    let turntable = SCNNode()
    let bodyNode: SCNNode
    let cameraNode = SCNNode()
    let rig = SCNNode()
    let keyLight = SCNNode()
    let markers = SCNNode()
    weak var view: SCNView?

    var layer: BodyLayer = .skin
    private(set) var yaw: Float = 0
    private(set) var distance: Float = 3.9
    private var target = SCNVector3(0, 0.93, 0)
    private var skinMaterials: [SCNMaterial] = []
    private var muscleMaterials: [SCNMaterial] = []
    private var highlighted: Int?
    var onSelect: ((BodyRegion, Body3DModel.Muscle?) -> Void)?
    var onMarker: ((String) -> Void)?

    static let fullDistance: Float = 3.9
    static let fullTarget = SCNVector3(0, 0.93, 0)

    init(model: Body3DModel) {
        self.model = model
        bodyNode = SCNNode(geometry: model.geometry.copy() as? SCNGeometry)
        super.init()
        build()
    }

    private func build() {
        scene.background.contents = UIColor.clear
        let detail = Bundle.main.path(forResource: "body_detail", ofType: "png").flatMap(UIImage.init(contentsOfFile:)).map(Self.tinted)
        let muscle = Bundle.main.path(forResource: "body_muscle", ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
        for _ in model.groups {
            skinMaterials.append(Self.skinMaterial(detail: detail))
            muscleMaterials.append(Self.muscleMaterial(albedo: muscle))
        }
        bodyNode.geometry?.materials = skinMaterials
        turntable.addChildNode(bodyNode)
        turntable.addChildNode(markers)
        scene.rootNode.addChildNode(turntable)
        scene.rootNode.addChildNode(floorNode())

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.05
        camera.zFar = 30
        camera.wantsHDR = true
        camera.bloomIntensity = 0.55
        camera.bloomThreshold = 0.6
        camera.bloomBlurRadius = 10
        cameraNode.camera = camera
        rig.addChildNode(cameraNode)
        scene.rootNode.addChildNode(rig)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        ambient.light?.color = UIColor(hex: 0x9FB4FF)
        scene.rootNode.addChildNode(ambient)

        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 900
        keyLight.light?.color = UIColor(hex: 0xDCE6FF)
        keyLight.eulerAngles = SCNVector3(-0.5, -0.6, 0)
        scene.rootNode.addChildNode(keyLight)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 500
        rim.light?.color = UIColor(hex: 0x3DDCFF)
        rim.eulerAngles = SCNVector3(-0.2, .pi * 0.85, 0)
        scene.rootNode.addChildNode(rim)
        applyCamera(animated: false)
    }

    static let fresnel = """
    float3 n = normalize(_surface.normal);
    float3 v = normalize(-_surface.position);
    float f = pow(1.0 - saturate(dot(n, v)), 2.4);
    """

    static func skinMaterial(detail: UIImage?) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = UIColor(hex: 0x0A2A9E)
        m.emission.contents = detail
        m.emission.intensity = 0.32
        m.setValue(Float(0), forKey: "highlight")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float highlight;
            #pragma body
            \(fresnel)
            _output.color.rgb += mix(float3(0.26, 0.52, 1.0), float3(0.75, 0.9, 1.0), f) * f * 1.25;
            _output.color.rgb += float3(0.24, 0.86, 1.0) * highlight * (0.28 + 0.9 * f);
            """,
        ]
        return m
    }

    /// The grayscale anatomy-line map tinted cyan once, so the material needs no surface shader.
    static func tinted(_ gray: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: gray.size, format: format).image { ctx in
            UIColor(hex: 0x6FE0FF).setFill()
            ctx.fill(CGRect(origin: .zero, size: gray.size))
            gray.draw(in: CGRect(origin: .zero, size: gray.size), blendMode: .multiply, alpha: 1)
        }
    }

    static func muscleMaterial(albedo: UIImage?) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = albedo ?? UIColor(hex: 0xA3201C)
        m.specular.contents = UIColor(white: 0.22, alpha: 1)
        m.shininess = 0.35
        m.setValue(Float(0), forKey: "highlight")
        m.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float highlight;
            #pragma body
            \(fresnel)
            _output.color.rgb += float3(1.0, 0.45, 0.35) * f * 0.35;
            _output.color.rgb += float3(0.24, 0.86, 1.0) * highlight * (0.22 + 0.7 * f);
            """,
        ]
        return m
    }

    func floorNode() -> SCNNode {
        let size = 256
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let colors = [UIColor(hex: 0x4C8DFF, alpha: 0.55).cgColor, UIColor(hex: 0x4C8DFF, alpha: 0.12).cgColor, UIColor.clear.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
            UIColor(hex: 0x3DDCFF, alpha: 0.5).setStroke()
            for r in [0.3, 0.42] {
                let rr = CGFloat(size) * r
                ctx.cgContext.setLineWidth(1.5)
                ctx.cgContext.strokeEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            }
        }
        let plane = SCNPlane(width: 1.5, height: 1.5)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .add
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position.y = 0.002
        return node
    }

    // MARK: Layer and highlight

    func setLayer(_ layer: BodyLayer) {
        self.layer = layer
        let mats = layer == .skin ? skinMaterials : muscleMaterials
        bodyNode.geometry?.materials = mats
        if let h = highlighted { mats[h].setValue(Float(1), forKey: "highlight") }
    }

    func highlight(_ region: BodyRegion?) {
        for m in skinMaterials + muscleMaterials { m.setValue(Float(0), forKey: "highlight") }
        highlighted = region.flatMap { r in model.groups.firstIndex { model.meta.regions[$0.region].id == r.rawValue } }
        if let h = highlighted {
            skinMaterials[h].setValue(Float(1), forKey: "highlight")
            muscleMaterials[h].setValue(Float(1), forKey: "highlight")
        }
    }

    // MARK: Camera

    func applyCamera(animated: Bool, duration: Double = 0.8) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        turntable.eulerAngles.y = yaw
        rig.position = target
        cameraNode.position = SCNVector3(0, 0.05 * distance / Self.fullDistance, distance)
        cameraNode.eulerAngles = SCNVector3(-0.012, 0, 0)
        SCNTransaction.commit()
    }

    func rotate(by delta: Float) {
        yaw += delta
        turntable.eulerAngles.y = yaw
    }

    func setYaw(_ value: Float, animated: Bool = true) {
        var d = (value - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        yaw += d
        applyCamera(animated: animated)
    }

    func zoom(by factor: Float, animated: Bool = false) {
        distance = max(0.7, min(Self.fullDistance, distance / factor))
        if distance > Self.fullDistance * 0.92 { target = Self.fullTarget }
        applyCamera(animated: animated, duration: 0.35)
    }

    func reset(animated: Bool = true) {
        distance = Self.fullDistance
        target = Self.fullTarget
        highlight(nil)
        applyCamera(animated: animated)
    }

    /// Turn the region toward the viewer and frame it.
    func focus(_ region: BodyRegion, animated: Bool = true) {
        guard let info = model.info(for: region) else { return }
        let n = info.normal.vector
        let facing = abs(n.x) + abs(n.z) > 0.2 ? -atan2(n.x, n.z) : yaw
        var d = (facing - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        yaw += d
        let a = info.anchor.vector
        let c = cos(yaw), s = sin(yaw)
        target = SCNVector3(a.x * c + a.z * s, a.y, -a.x * s + a.z * c)
        distance = max(0.8, min(2.4, info.radius * 7))
        highlight(region)
        applyCamera(animated: animated, duration: 0.9)
    }

    // MARK: Markers

    func setMarkers(_ notes: [HealthEvent], focused: String?, today: LocalDate) {
        markers.childNodes.forEach { $0.removeFromParentNode() }
        var perRegion: [BodyRegion: Int] = [:]
        for note in notes {
            guard let region = note.bodyRegion, let info = model.info(for: region) else { continue }
            let k = perRegion[region, default: 0]
            perRegion[region] = k + 1
            let n = info.normal.vector
            let base = info.anchor.vector
            let lift: Float = 0.018 + Float(k) * 0.03
            let node = SCNNode()
            node.name = note.id
            node.position = SCNVector3(base.x + n.x * lift, base.y + n.y * lift + Float(k) * 0.035, base.z + n.z * lift)

            let dot = SCNSphere(radius: 0.017)
            let dm = SCNMaterial()
            dm.lightingModel = .constant
            dm.diffuse.contents = UIColor(hex: 0xFF8A4C)
            dot.materials = [dm]
            let dotNode = SCNNode(geometry: dot)
            dotNode.name = note.id
            node.addChildNode(dotNode)

            let ring = SCNNode(geometry: SCNPlane(width: 0.09, height: 0.09))
            let rm = SCNMaterial()
            rm.lightingModel = .constant
            rm.diffuse.contents = Self.ringImage
            rm.blendMode = .add
            rm.writesToDepthBuffer = false
            ring.geometry?.materials = [rm]
            ring.constraints = [SCNBillboardConstraint()]
            node.addChildNode(ring)
            if !UIAccessibility.isReduceMotionEnabled {
                let pulse = CABasicAnimation(keyPath: "scale")
                pulse.fromValue = NSValue(scnVector3: SCNVector3(0.6, 0.6, 0.6))
                pulse.toValue = NSValue(scnVector3: SCNVector3(1.4, 1.4, 1.4))
                pulse.duration = 1.6
                pulse.repeatCount = .infinity
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                fade.duration = 1.6
                fade.repeatCount = .infinity
                ring.addAnimation(pulse, forKey: "pulse")
                ring.addAnimation(fade, forKey: "fade")
            }

            if note.id == focused {
                let label = Self.label("\(note.title.isEmpty ? note.kindLabel : note.title) · \(Fmt.shortDate(note.date))")
                let h: CGFloat = 0.05
                let plane = SCNPlane(width: h * label.size.width / label.size.height, height: h)
                let lm = SCNMaterial()
                lm.lightingModel = .constant
                lm.diffuse.contents = label
                lm.isDoubleSided = true
                plane.materials = [lm]
                let labelNode = SCNNode(geometry: plane)
                labelNode.position = SCNVector3(0, 0.07, 0)
                labelNode.constraints = [SCNBillboardConstraint()]
                labelNode.renderingOrder = 10
                node.addChildNode(labelNode)
            }
            markers.addChildNode(node)
        }
    }

    static let ringImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
        UIColor(hex: 0xFF8A4C).setStroke()
        ctx.cgContext.setLineWidth(4)
        ctx.cgContext.strokeEllipse(in: CGRect(x: 6, y: 6, width: 52, height: 52))
    }

    static func label(_ text: String) -> UIImage {
        let font = UIFont.systemFont(ofSize: 34, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 18
        let canvas = CGSize(width: size.width + pad * 2, height: size.height + pad)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            UIColor(hex: 0xFF8A4C).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: canvas.height / 2).fill()
            (text as NSString).draw(at: CGPoint(x: pad, y: pad / 2), withAttributes: attrs)
        }
    }

    // MARK: Ambient motion

    private var ambientOn: Bool?

    func setAmbientMotion(_ on: Bool) {
        guard ambientOn != on else { return }
        ambientOn = on
        keyLight.removeAllActions()
        guard on else { return }
        let sway = SCNAction.sequence([
            .rotateTo(x: -0.5, y: 0.6, z: 0, duration: 4.5, usesShortestUnitArc: true),
            .rotateTo(x: -0.5, y: -0.6, z: 0, duration: 4.5, usesShortestUnitArc: true),
        ])
        sway.timingMode = .easeInEaseOut
        keyLight.runAction(.repeatForever(sway))
    }

    // MARK: Input

    func handleTap(at point: CGPoint) {
        guard let view else { return }
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node, n !== scene.rootNode {
                if n.parent === markers, let id = n.name {
                    onMarker?(id)
                    return
                }
                node = n.parent
            }
        }
        guard let hit = hits.first(where: { $0.node === bodyNode }), let region = model.region(forElement: hit.geometryIndex) else { return }
        onSelect?(region, model.muscle(forElement: hit.geometryIndex, face: hit.faceIndex))
    }
}

// MARK: - SwiftUI wrapper

struct BodySceneView: UIViewRepresentable {
    let controller: BodySceneController
    var animate: Bool

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.scene = controller.scene
        v.pointOfView = controller.cameraNode
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        v.rendersContinuously = animate
        v.accessibilityLabel = "3D body. Drag sideways to turn, pinch to zoom, tap a region."
        controller.view = v

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        v.rendersContinuously = animate
        controller.setAmbientMotion(animate)
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let controller: BodySceneController
        init(controller: BodySceneController) { self.controller = controller }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let dx = Float(g.translation(in: g.view).x)
            g.setTranslation(.zero, in: g.view)
            controller.rotate(by: dx * 0.011)
            if g.state == .ended {
                let v = Float(g.velocity(in: g.view).x) * 0.0022
                controller.setYaw(controller.yaw + max(-2.5, min(2.5, v)))
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            controller.zoom(by: Float(g.scale))
            g.scale = 1
        }

        @objc func tap(_ g: UITapGestureRecognizer) {
            controller.handleTap(at: g.location(in: g.view))
        }

        /// Only horizontal drags turn the figure, so vertical drags keep scrolling the page.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }
}
