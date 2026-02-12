//
//  SnowGlobeSceneController.swift
//  LITA
//

import SceneKit
import UIKit

// MARK: - Shakable SCNView

class ShakableSCNView: SCNView {
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    func setup() {
        let doubleTap = UITapGestureRecognizer(
            target: self, action: #selector(handleDoubleTap)
        )
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        becomeFirstResponder()
    }

    override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { onShake?() }
        super.motionBegan(motion, with: event)
    }

    @objc private func handleDoubleTap() {
        onShake?()
    }
}

// MARK: - Snow Globe Scene Controller

class SnowGlobeSceneController: ObservableObject {
    let scnView: ShakableSCNView
    let scene: SCNScene
    private var photoNodes: [SCNNode] = []
    private var addedThumbnailCount = 0
    private var cameraNode: SCNNode!
    private var usingCustomModel = false

    // --- Globe parameters ---
    // The snowflake spawning sphere (inside the glass globe, above the ground/trees).
    // These are in world-space after the model transform.
    let snowflakeCenter = SCNVector3(0, 0.15, 0)
    let snowflakeRadius: Float = 0.7

    // Glass sphere world-space (for reference)
    let glassCenter = SCNVector3(0, 0, 0)
    let glassRadius: Float = 1.0

    init() {
        scene = SCNScene()
        scnView = ShakableSCNView(frame: .zero)

        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true

        scnView.setup()
        setupScene()

        scnView.onShake = { [weak self] in
            self?.shakeAnimation()
        }
    }

    // MARK: - Scene Setup

    private func setupScene() {
        scene.background.contents = UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0)

        // Camera — pulled back enough to see the full globe on a portrait iPhone
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 50
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        cameraNode.position = SCNVector3(0, 0.3, 5.0)
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor(white: 0.35, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        // Key light (warm golden)
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light!.type = .omni
        keyLight.light!.color = UIColor(red: 1.0, green: 0.92, blue: 0.82, alpha: 1.0)
        keyLight.light!.intensity = 900
        keyLight.position = SCNVector3(3, 4, 6)
        scene.rootNode.addChildNode(keyLight)

        // Fill light (cool blue)
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light!.type = .omni
        fillLight.light!.color = UIColor(red: 0.7, green: 0.8, blue: 1.0, alpha: 1.0)
        fillLight.light!.intensity = 400
        fillLight.position = SCNVector3(-4, 2, 4)
        scene.rootNode.addChildNode(fillLight)

        // Try to load the custom USDZ model
        if let modelURL = Bundle.main.url(forResource: "snow_globe", withExtension: "usdz"),
           let modelScene = try? SCNScene(url: modelURL)
        {
            loadCustomModel(modelScene)
            usingCustomModel = true
        } else {
            createProgrammaticGlobe()
        }

        addSparkleParticles()
    }

    // MARK: - Custom USDZ Model

    /// Loads the Sketchfab snow globe model and transforms it so:
    ///   - The glass sphere is centered at the world origin (0,0,0) with radius ≈ 1.0
    ///   - The base sits below
    ///
    /// Model analysis (in model-space units):
    ///   pSphere1 (glass)  — center (0, 9.06, 0), radius ≈ 7.985
    ///   pCylinder1 (base) — y 0.03 … 3.85, width ≈ 12
    ///   pCylinder5 (snow) — ground top ≈ y 4.29
    ///   Trees              — tops reach ≈ y 10
    private func loadCustomModel(_ modelScene: SCNScene) {
        // Wrap everything in a container node for scale + position
        let container = SCNNode()
        container.name = "modelContainer"

        // Scale: original sphere radius ≈ 7.985 → target radius 1.0
        let scaleFactor: Float = 0.125
        container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)

        // Offset: sphere center in model-space is y = 9.06
        //   After scale it's at y = 9.06 * 0.125 = 1.1325
        //   Move container down so sphere center lands at y = 0
        container.position = SCNVector3(0, -9.06 * scaleFactor, 0)

        for child in modelScene.rootNode.childNodes {
            container.addChildNode(child.clone())
        }
        scene.rootNode.addChildNode(container)

        // Fix the glass material so we can see the snowflakes inside
        fixGlassMaterial(in: container)
    }

    /// Finds all geometry nodes with a "glass" material and makes them translucent.
    private func fixGlassMaterial(in root: SCNNode) {
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials where material.name == "glass" {
                material.lightingModel = .physicallyBased
                material.diffuse.contents = UIColor(white: 1.0, alpha: 0.03)
                material.specular.contents = UIColor.white
                material.metalness.contents = 0.0
                material.roughness.contents = 0.05
                material.transparency = 0.12
                material.isDoubleSided = true
                material.blendMode = .add
                material.writesToDepthBuffer = false
                material.fresnelExponent = 5.0
            }
            // Make glass nodes render last (after photo snowflakes)
            if geometry.materials.contains(where: { $0.name == "glass" }) {
                node.renderingOrder = 100
            }
        }
    }

    // MARK: - Programmatic Fallback Globe

    private func createProgrammaticGlobe() {
        // Glass sphere
        let sphere = SCNSphere(radius: CGFloat(glassRadius))
        sphere.segmentCount = 96

        let glassMaterial = SCNMaterial()
        glassMaterial.lightingModel = .physicallyBased
        glassMaterial.diffuse.contents = UIColor(white: 1.0, alpha: 0.03)
        glassMaterial.specular.contents = UIColor.white
        glassMaterial.metalness.contents = 0.0
        glassMaterial.roughness.contents = 0.05
        glassMaterial.transparency = 0.1
        glassMaterial.isDoubleSided = true
        glassMaterial.blendMode = .add
        glassMaterial.writesToDepthBuffer = false
        glassMaterial.fresnelExponent = 5.0
        sphere.materials = [glassMaterial]

        let globeNode = SCNNode(geometry: sphere)
        globeNode.position = glassCenter
        globeNode.renderingOrder = 100
        scene.rootNode.addChildNode(globeNode)

        // Wooden base
        let base = SCNCylinder(radius: 0.5, height: 0.15)
        let baseMaterial = SCNMaterial()
        baseMaterial.lightingModel = .physicallyBased
        baseMaterial.diffuse.contents = UIColor(red: 0.45, green: 0.28, blue: 0.15, alpha: 1.0)
        baseMaterial.roughness.contents = 0.8
        base.materials = [baseMaterial]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, -glassRadius - 0.075, 0)
        scene.rootNode.addChildNode(baseNode)

        // Gold rim
        let rim = SCNTorus(ringRadius: 0.5, pipeRadius: 0.025)
        let rimMaterial = SCNMaterial()
        rimMaterial.lightingModel = .physicallyBased
        rimMaterial.diffuse.contents = UIColor(red: 0.85, green: 0.7, blue: 0.25, alpha: 1.0)
        rimMaterial.metalness.contents = 0.9
        rimMaterial.roughness.contents = 0.25
        rim.materials = [rimMaterial]
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, -glassRadius + 0.01, 0)
        scene.rootNode.addChildNode(rimNode)
    }

    // MARK: - Sparkle Particles

    private func addSparkleParticles() {
        let particles = SCNParticleSystem()
        particles.particleSize = 0.003
        particles.particleSizeVariation = 0.001
        particles.particleColor = UIColor(white: 1.0, alpha: 0.6)
        particles.particleLifeSpan = 5
        particles.particleLifeSpanVariation = 2
        particles.birthRate = 8
        particles.warmupDuration = 3
        particles.emitterShape = SCNSphere(radius: CGFloat(snowflakeRadius * 0.8))
        particles.spreadingAngle = 180
        particles.particleVelocity = 0.005
        particles.particleVelocityVariation = 0.003
        particles.acceleration = SCNVector3(0, -0.001, 0)
        particles.blendMode = .additive

        let particleNode = SCNNode()
        particleNode.position = snowflakeCenter
        particleNode.addParticleSystem(particles)
        scene.rootNode.addChildNode(particleNode)
    }

    // MARK: - Photo Node Management

    func updateThumbnails(_ thumbnails: [UIImage]) {
        while addedThumbnailCount < thumbnails.count {
            addPhotoNode(image: thumbnails[addedThumbnailCount])
            addedThumbnailCount += 1
        }
    }

    private func addPhotoNode(image: UIImage) {
        let size = CGFloat.random(in: 0.05...0.08)

        // Parent node for the two-sided snowflake
        let parentNode = SCNNode()
        parentNode.name = "photoNode"

        // Front face: photo
        let frontPlane = SCNPlane(width: size, height: size)
        frontPlane.cornerRadius = size * 0.1
        let frontMaterial = SCNMaterial()
        frontMaterial.diffuse.contents = image
        frontMaterial.lightingModel = .constant
        frontMaterial.isDoubleSided = false
        frontPlane.materials = [frontMaterial]
        let frontNode = SCNNode(geometry: frontPlane)
        parentNode.addChildNode(frontNode)

        // Back face: white (snow side)
        let backPlane = SCNPlane(width: size, height: size)
        backPlane.cornerRadius = size * 0.1
        let backMaterial = SCNMaterial()
        backMaterial.diffuse.contents = UIColor(white: 0.95, alpha: 1.0)
        backMaterial.lightingModel = .constant
        backMaterial.isDoubleSided = false
        backPlane.materials = [backMaterial]
        let backNode = SCNNode(geometry: backPlane)
        backNode.eulerAngles.y = .pi
        parentNode.addChildNode(backNode)

        // Start from bottom of snowflake zone (settling animation)
        let targetPos = randomPointInSphere()
        parentNode.position = SCNVector3(
            targetPos.x + Float.random(in: -0.05...0.05),
            snowflakeCenter.y - snowflakeRadius * 0.8,
            targetPos.z + Float.random(in: -0.05...0.05)
        )

        // Random initial rotation
        parentNode.eulerAngles = SCNVector3(
            Float.random(in: 0...Float.pi * 2),
            Float.random(in: 0...Float.pi * 2),
            Float.random(in: 0...Float.pi * 2)
        )

        // Settle upward into position
        let delay = SCNAction.wait(duration: TimeInterval.random(in: 0...2.0))
        let rise = SCNAction.move(to: targetPos, duration: TimeInterval.random(in: 2.0...4.0))
        rise.timingMode = .easeOut
        let spin = SCNAction.rotateBy(
            x: CGFloat(Float.random(in: -1...1)),
            y: CGFloat(Float.random(in: -1...1)),
            z: CGFloat(Float.random(in: -1...1)),
            duration: TimeInterval.random(in: 2.0...4.0)
        )
        parentNode.runAction(SCNAction.sequence([delay, SCNAction.group([rise, spin])])) {
            [weak self] in
            self?.addFloatingAnimation(to: parentNode)
        }

        scene.rootNode.addChildNode(parentNode)
        photoNodes.append(parentNode)
    }

    // MARK: - Sphere Math

    func randomPointInSphere() -> SCNVector3 {
        let theta = Float.random(in: 0...(2.0 * .pi))
        let phi = acos(Float.random(in: -1...1))
        let r = snowflakeRadius * cbrt(Float.random(in: 0...1)) * 0.92

        return SCNVector3(
            snowflakeCenter.x + r * sin(phi) * cos(theta),
            snowflakeCenter.y + r * sin(phi) * sin(theta),
            snowflakeCenter.z + r * cos(phi)
        )
    }

    private func clampToSphere(_ point: SCNVector3) -> SCNVector3 {
        let dx = point.x - snowflakeCenter.x
        let dy = point.y - snowflakeCenter.y
        let dz = point.z - snowflakeCenter.z
        let dist = sqrt(dx * dx + dy * dy + dz * dz)
        let maxR = snowflakeRadius * 0.92

        if dist <= maxR { return point }

        let s = maxR / dist
        return SCNVector3(
            snowflakeCenter.x + dx * s,
            snowflakeCenter.y + dy * s,
            snowflakeCenter.z + dz * s
        )
    }

    // MARK: - Animations

    private func addFloatingAnimation(to node: SCNNode) {
        let pos = node.position
        let duration = TimeInterval.random(in: 4...7)
        let drift: Float = 0.03

        let p1 = clampToSphere(SCNVector3(
            pos.x + Float.random(in: -drift...drift),
            pos.y + Float.random(in: 0.01...drift),
            pos.z + Float.random(in: -drift...drift)
        ))
        let p2 = clampToSphere(SCNVector3(
            pos.x + Float.random(in: -drift...drift),
            pos.y - Float.random(in: 0.01...drift),
            pos.z + Float.random(in: -drift...drift)
        ))

        let up = SCNAction.move(to: p1, duration: duration)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.move(to: p2, duration: duration)
        down.timingMode = .easeInEaseOut

        let rotate = SCNAction.rotateBy(
            x: CGFloat(Float.random(in: -0.3...0.3)),
            y: CGFloat(Float.random(in: -0.5...0.5)),
            z: CGFloat(Float.random(in: -0.3...0.3)),
            duration: duration * 2
        )

        let float = SCNAction.group([
            SCNAction.sequence([up, down]),
            rotate,
        ])

        node.runAction(SCNAction.repeatForever(float))
    }

    func shakeAnimation() {
        for node in photoNodes {
            node.removeAllActions()

            var actions: [SCNAction] = []

            // Stage 1: big scatter
            let pos1 = randomPointInSphere()
            let move1 = SCNAction.move(to: pos1, duration: 0.3)
            move1.timingMode = .easeOut
            let spin1 = SCNAction.rotateBy(
                x: CGFloat(Float.random(in: -8...8)),
                y: CGFloat(Float.random(in: -8...8)),
                z: CGFloat(Float.random(in: -8...8)),
                duration: 0.3
            )
            actions.append(SCNAction.group([move1, spin1]))

            // Stage 2: medium drift
            let pos2 = randomPointInSphere()
            let move2 = SCNAction.move(to: pos2, duration: 0.5)
            move2.timingMode = .easeOut
            let spin2 = SCNAction.rotateBy(
                x: CGFloat(Float.random(in: -3...3)),
                y: CGFloat(Float.random(in: -3...3)),
                z: CGFloat(Float.random(in: -3...3)),
                duration: 0.5
            )
            actions.append(SCNAction.group([move2, spin2]))

            // Stage 3: settle
            let pos3 = randomPointInSphere()
            let move3 = SCNAction.move(to: pos3, duration: 1.0)
            move3.timingMode = .easeOut
            let spin3 = SCNAction.rotateBy(
                x: CGFloat(Float.random(in: -1...1)),
                y: CGFloat(Float.random(in: -1...1)),
                z: CGFloat(Float.random(in: -1...1)),
                duration: 1.0
            )
            actions.append(SCNAction.group([move3, spin3]))

            node.runAction(SCNAction.sequence(actions)) { [weak self] in
                self?.addFloatingAnimation(to: node)
            }
        }
    }

    func flyOutAnimation(completion: @escaping () -> Void) {
        guard !photoNodes.isEmpty else {
            DispatchQueue.main.async { completion() }
            return
        }

        let chosenNode = photoNodes.randomElement()!
        chosenNode.removeAllActions()

        // Dim other nodes
        for node in photoNodes where node !== chosenNode {
            node.runAction(SCNAction.fadeOpacity(to: 0.3, duration: 0.5))
        }

        // Fly toward camera (camera is at z=5.0)
        let targetPos = SCNVector3(0, 0.3, 4.0)
        let move = SCNAction.move(to: targetPos, duration: 1.0)
        move.timingMode = .easeInEaseOut

        let scale = SCNAction.scale(to: 15.0, duration: 1.0)
        scale.timingMode = .easeInEaseOut

        let faceCamera = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.5)
        faceCamera.timingMode = .easeInEaseOut

        let flyOut = SCNAction.group([move, scale, faceCamera])
        let fadeOut = SCNAction.fadeOut(duration: 0.2)

        chosenNode.runAction(SCNAction.sequence([flyOut, fadeOut])) { [weak self] in
            guard let self = self else { return }

            // Reset chosen node
            chosenNode.position = self.randomPointInSphere()
            chosenNode.scale = SCNVector3(1, 1, 1)
            chosenNode.opacity = 1.0
            chosenNode.eulerAngles = SCNVector3(
                Float.random(in: 0...Float.pi * 2),
                Float.random(in: 0...Float.pi * 2),
                Float.random(in: 0...Float.pi * 2)
            )
            self.addFloatingAnimation(to: chosenNode)

            // Restore other nodes
            for node in self.photoNodes where node !== chosenNode {
                node.runAction(SCNAction.fadeOpacity(to: 1.0, duration: 0.5))
            }

            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
