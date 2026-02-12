//
//  SnowGlobeSceneController.swift
//  LITA
//

import CoreMotion
import SceneKit
import simd
import UIKit

// MARK: - Shakable SCNView

class ShakableSCNView: SCNView {
    var onShake: (() -> Void)?
    var onPan: ((UIPanGestureRecognizer) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    func setup() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
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

    @objc private func handleDoubleTap() { onShake?() }
    @objc private func handlePan(_ g: UIPanGestureRecognizer) { onPan?(g) }
}

// MARK: - Snow Globe Scene Controller

class SnowGlobeSceneController: NSObject, ObservableObject, SCNSceneRendererDelegate {
    let scnView: ShakableSCNView
    let scene: SCNScene
    private var photoNodes: [SCNNode] = []
    private var addedThumbnailCount = 0
    private var cameraNode: SCNNode!
    private var usingCustomModel = false

    // --- Snowflake spawning sphere (world-space) ---
    let snowflakeCenter: simd_float3 = [0, 0.1, 0]
    let snowflakeRadius: Float = 0.85
    let glassCenter: simd_float3 = [0, 0, 0]
    let glassRadius: Float = 1.0

    // --- Physics state (parallel arrays) ---
    private var velocities: [simd_float3] = []
    private var rotSpeeds: [simd_float3] = []
    private var baseRotSpeeds: [simd_float3] = []
    private var turbPhases: [Float] = []
    private var turbOffsets: [simd_float3] = []
    private var lastTime: TimeInterval = 0
    private var flyingOutNode: SCNNode? = nil

    // --- Physics parameters (all adjustable via debug) ---
    private var netGravity: Float = -0.012        // net downward = gravity minus buoyancy
    private var dragCoeff: Float = 1.0
    private let turbStrength: Float = 0.02
    private let maxSpeed: Float = 0.8
    private let wallTangentRetention: Float = 0.85
    private var wallSlideDownSpeed: Float = 0     // extra slide-down (0 = let gravity handle it)
    private var shakeUpwardForce: Float = 0       // impulse on motionBegan (0 = rely on accelerometer)
    private var motionSensitivity: Float = 3.0
    private var separationRadius: Float = 0.15
    private var separationStrength: Float = 0.7

    // --- Device motion ---
    private let motionLock = NSLock()
    private var lastUserAccel = simd_float3(0, 0, 0)
    private var lastRotationRate = simd_float3(0, 0, 0)
    private var motionManager: CMMotionManager?

    // --- Camera orbit (Three.js OrbitControls) ---
    // Orbit target = bottom center of wooden base
    // Model: base bottom in model-space ≈ y 0.03; after scale 0.125 and offset -1.1325 → y ≈ -1.129
    // Orbit target = vertical center of entire model (sphere top ≈ 1.0, base bottom ≈ -1.13)
    private let orbitTarget = simd_float3(0, -0.06, 0)
    private let orbitDistance: Float = 5.5
    private var orbitAzimuth: Float = 0
    private var orbitPolar: Float = Float.pi / 2  // equator → camera at same height as target, model centered
    private let orbitSensitivity: Float = 0.004

    // --- Memory reveal ---
    @Published var isShowingMemory = false
    private var memoryNode: SCNNode? = nil

    // --- Material references ---
    private(set) var glassMaterials: [SCNMaterial] = []
    private(set) var snowMaterials: [SCNMaterial] = []
    private(set) var woodMaterials: [SCNMaterial] = []
    private(set) var treeMaterials: [SCNMaterial] = []

    let availableEnvMaps = [
        "artist_workshop_1k",
        "brown_photostudio_01_1k",
        "brown_photostudio_06_1k",
        "poly_haven_studio_1k",
    ]

    // MARK: - Init

    override init() {
        scene = SCNScene()
        scnView = ShakableSCNView(frame: .zero)
        super.init()

        scnView.scene = scene
        scnView.delegate = self
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true

        scnView.setup()
        setupScene()
        applyPersistedDebugSettings()

        scnView.onShake = { [weak self] in self?.shakeSnowflakes() }
        scnView.onPan = { [weak self] g in self?.handleOrbitPan(g) }
    }

    // MARK: - Scene Setup

    private func setupScene() {
        scene.background.contents = UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0)

        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 50
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)
        updateCameraFromOrbit()

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor(white: 0.3, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light!.type = .omni
        keyLight.light!.color = UIColor(red: 1.0, green: 0.92, blue: 0.82, alpha: 1.0)
        keyLight.light!.intensity = 800
        keyLight.position = SCNVector3(3, 4, 6)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light!.type = .omni
        fillLight.light!.color = UIColor(red: 0.7, green: 0.8, blue: 1.0, alpha: 1.0)
        fillLight.light!.intensity = 300
        fillLight.position = SCNVector3(-4, 2, 4)
        scene.rootNode.addChildNode(fillLight)

        if let modelURL = Bundle.main.url(forResource: "snow_globe", withExtension: "usdz"),
           let modelScene = try? SCNScene(url: modelURL)
        {
            loadCustomModel(modelScene)
            usingCustomModel = true
        } else {
            createProgrammaticGlobe()
        }

        setEnvironmentMap(name: "artist_workshop_1k", intensity: 1.0)
        addSparkleParticles()
    }

    // MARK: - Camera Orbit

    private func updateCameraFromOrbit() {
        let x = orbitDistance * sin(orbitPolar) * sin(orbitAzimuth)
        let y = orbitDistance * cos(orbitPolar)
        let z = orbitDistance * sin(orbitPolar) * cos(orbitAzimuth)
        let camPos = orbitTarget + simd_float3(x, y, z)
        cameraNode.simdPosition = camPos

        let forward = simd_normalize(orbitTarget - camPos)
        let worldUp = simd_float3(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, worldUp))
        let up = simd_cross(right, forward)
        // Local-to-world rotation: each column is a local axis expressed in world coords.
        // SceneKit camera looks along local -Z, so local Z = -forward.
        var m = simd_float4x4(1)
        m.columns.0 = simd_float4(right.x, right.y, right.z, 0)
        m.columns.1 = simd_float4(up.x, up.y, up.z, 0)
        m.columns.2 = simd_float4(-forward.x, -forward.y, -forward.z, 0)
        m.columns.3 = simd_float4(0, 0, 0, 1)
        cameraNode.simdOrientation = simd_quatf(m)
    }

    private func handleOrbitPan(_ gesture: UIPanGestureRecognizer) {
        let t = gesture.translation(in: scnView)
        orbitAzimuth -= Float(t.x) * orbitSensitivity
        orbitPolar -= Float(t.y) * orbitSensitivity
        orbitPolar = max(0.3, min(Float.pi - 0.3, orbitPolar))
        updateCameraFromOrbit()
        gesture.setTranslation(.zero, in: scnView)
    }

    // MARK: - Custom USDZ Model

    private func loadCustomModel(_ modelScene: SCNScene) {
        let container = SCNNode()
        container.name = "modelContainer"
        let scaleFactor: Float = 0.125
        container.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        container.position = SCNVector3(0, -9.06 * scaleFactor, 0)

        for child in modelScene.rootNode.childNodes {
            container.addChildNode(child.clone())
        }
        scene.rootNode.addChildNode(container)

        container.enumerateChildNodes { [weak self] node, _ in
            guard let self, let geometry = node.geometry else { return }
            for material in geometry.materials {
                material.lightingModel = .physicallyBased
                switch material.name {
                case "glass":
                    if !glassMaterials.contains(where: { $0 === material }) { glassMaterials.append(material) }
                    material.diffuse.contents = UIColor(white: 1.0, alpha: 0.03)
                    material.specular.contents = UIColor.white
                    material.metalness.contents = 0.0
                    material.roughness.contents = 0.05
                    material.transparency = 0.12
                    material.isDoubleSided = true
                    material.blendMode = .add
                    material.writesToDepthBuffer = false
                    material.fresnelExponent = 5.0
                    node.renderingOrder = 100
                case "snow":
                    if !snowMaterials.contains(where: { $0 === material }) { snowMaterials.append(material) }
                case "drak_brown", "brown", "light_brown":
                    if !woodMaterials.contains(where: { $0 === material }) { woodMaterials.append(material) }
                case "tree", "dark_tree":
                    if !treeMaterials.contains(where: { $0 === material }) { treeMaterials.append(material) }
                default: break
                }
            }
        }
    }

    // MARK: - Programmatic Fallback

    private func createProgrammaticGlobe() {
        let sphere = SCNSphere(radius: CGFloat(glassRadius))
        sphere.segmentCount = 96
        let glassMat = SCNMaterial()
        glassMat.name = "glass"
        glassMat.lightingModel = .physicallyBased
        glassMat.diffuse.contents = UIColor(white: 1.0, alpha: 0.03)
        glassMat.specular.contents = UIColor.white
        glassMat.metalness.contents = 0.0
        glassMat.roughness.contents = 0.05
        glassMat.transparency = 0.1
        glassMat.isDoubleSided = true
        glassMat.blendMode = .add
        glassMat.writesToDepthBuffer = false
        glassMat.fresnelExponent = 5.0
        sphere.materials = [glassMat]
        glassMaterials.append(glassMat)
        let globeNode = SCNNode(geometry: sphere)
        globeNode.simdPosition = glassCenter
        globeNode.renderingOrder = 100
        scene.rootNode.addChildNode(globeNode)

        let base = SCNCylinder(radius: 0.5, height: 0.15)
        let baseMat = SCNMaterial()
        baseMat.name = "drak_brown"
        baseMat.lightingModel = .physicallyBased
        baseMat.diffuse.contents = UIColor(red: 0.45, green: 0.28, blue: 0.15, alpha: 1.0)
        baseMat.roughness.contents = 0.8
        base.materials = [baseMat]
        woodMaterials.append(baseMat)
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, -glassRadius - 0.075, 0)
        scene.rootNode.addChildNode(baseNode)

        let rim = SCNTorus(ringRadius: 0.5, pipeRadius: 0.025)
        let rimMat = SCNMaterial()
        rimMat.lightingModel = .physicallyBased
        rimMat.diffuse.contents = UIColor(red: 0.85, green: 0.7, blue: 0.25, alpha: 1.0)
        rimMat.metalness.contents = 0.9
        rimMat.roughness.contents = 0.25
        rim.materials = [rimMat]
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, -glassRadius + 0.01, 0)
        scene.rootNode.addChildNode(rimNode)
    }

    // MARK: - Persisted Debug Settings

    private func applyPersistedDebugSettings() {
        let v = DebugSettingsStore.load()
        setEnvironmentMap(name: v.envMapName, intensity: v.envIntensity)
        updateGlass(transparency: v.glassTransparency, roughness: v.glassRoughness, fresnel: v.glassFresnel)
        updateSnow(roughness: v.snowRoughness, metalness: v.snowMetalness)
        updateWood(roughness: v.woodRoughness, metalness: v.woodMetalness)
        updateTree(roughness: v.treeRoughness, metalness: v.treeMetalness)
        setPhysics(
            motionSensitivity: v.motionSensitivity,
            shakeUpwardForce: v.shakeUpwardForce,
            gravity: v.gravity,
            dragCoeff: v.dragCoeff,
            wallSlideDownSpeed: v.wallSlideDownSpeed,
            separationRadius: v.separationRadius,
            separationStrength: v.separationStrength
        )
    }

    func setPhysics(
        motionSensitivity: Float,
        shakeUpwardForce: Float,
        gravity: Float,
        dragCoeff: Float,
        wallSlideDownSpeed: Float,
        separationRadius: Float,
        separationStrength: Float
    ) {
        self.motionSensitivity = motionSensitivity
        self.shakeUpwardForce = shakeUpwardForce
        self.netGravity = gravity
        self.dragCoeff = dragCoeff
        self.wallSlideDownSpeed = wallSlideDownSpeed
        self.separationRadius = separationRadius
        self.separationStrength = separationStrength
    }

    // MARK: - Environment Map

    func setEnvironmentMap(name: String, intensity: Float) {
        if name.isEmpty {
            scene.lightingEnvironment.contents = nil
        } else if let url = Bundle.main.url(forResource: name, withExtension: "hdr") {
            scene.lightingEnvironment.contents = url
            scene.lightingEnvironment.intensity = CGFloat(intensity)
        }
    }

    // MARK: - Debug Material Setters

    func updateGlass(transparency: Float, roughness: Float, fresnel: Float) {
        for mat in glassMaterials {
            mat.transparency = CGFloat(transparency)
            mat.roughness.contents = roughness
            mat.fresnelExponent = CGFloat(fresnel)
        }
    }

    func updateSnow(roughness: Float, metalness: Float) {
        for mat in snowMaterials { mat.roughness.contents = roughness; mat.metalness.contents = metalness }
    }

    func updateWood(roughness: Float, metalness: Float) {
        for mat in woodMaterials { mat.roughness.contents = roughness; mat.metalness.contents = metalness }
    }

    func updateTree(roughness: Float, metalness: Float) {
        for mat in treeMaterials { mat.roughness.contents = roughness; mat.metalness.contents = metalness }
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
        particleNode.simdPosition = snowflakeCenter
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
        let size = CGFloat.random(in: 0.025...0.04)
        let parentNode = SCNNode()
        parentNode.name = "photoNode"

        let frontPlane = SCNPlane(width: size, height: size)
        frontPlane.cornerRadius = size * 0.1
        let frontMat = SCNMaterial()
        frontMat.diffuse.contents = image
        frontMat.lightingModel = .constant
        frontMat.isDoubleSided = false
        frontPlane.materials = [frontMat]
        parentNode.addChildNode(SCNNode(geometry: frontPlane))

        let backPlane = SCNPlane(width: size, height: size)
        backPlane.cornerRadius = size * 0.1
        let backMat = SCNMaterial()
        backMat.diffuse.contents = UIColor(white: 0.95, alpha: 1.0)
        backMat.lightingModel = .constant
        backMat.isDoubleSided = false
        backPlane.materials = [backMat]
        let backNode = SCNNode(geometry: backPlane)
        backNode.eulerAngles.y = .pi
        parentNode.addChildNode(backNode)

        parentNode.simdPosition = randomPointInSphere()
        parentNode.simdEulerAngles = simd_float3(
            Float.random(in: 0...Float.pi * 2),
            Float.random(in: 0...Float.pi * 2),
            Float.random(in: 0...Float.pi * 2)
        )

        scene.rootNode.addChildNode(parentNode)
        photoNodes.append(parentNode)

        velocities.append(simd_float3(0, 0, 0))
        let brs = simd_float3(
            Float.random(in: -0.25...0.25),
            Float.random(in: -0.3...0.3),
            Float.random(in: -0.25...0.25)
        )
        baseRotSpeeds.append(brs)
        rotSpeeds.append(brs)
        turbPhases.append(Float.random(in: 0...100))
        turbOffsets.append(simd_float3(Float.random(in: 0...10), Float.random(in: 0...10), Float.random(in: 0...10)))
    }

    func randomPointInSphere() -> simd_float3 {
        let theta = Float.random(in: 0...(2.0 * .pi))
        let phi = acos(Float.random(in: -1...1))
        let r = snowflakeRadius * cbrt(Float.random(in: 0...1)) * 0.95
        return snowflakeCenter + simd_float3(r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi))
    }

    // MARK: - Physics Loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard lastTime > 0 else { lastTime = time; return }
        let dt = Float(min(time - lastTime, 1.0 / 30.0))
        lastTime = time
        updatePhysics(dt: dt, time: Float(time))
    }

    private func updatePhysics(dt: Float, time: Float) {
        motionLock.lock()
        let accel = lastUserAccel
        let rotRate = lastRotationRate
        motionLock.unlock()

        let count = min(photoNodes.count, velocities.count)
        guard count > 0 else { return }

        // Snapshot positions for separation (avoids O(n) node.simdPosition reads per neighbor check)
        var positions = [simd_float3](repeating: .zero, count: count)
        for i in 0..<count { positions[i] = photoNodes[i].simdPosition }

        let sepR = separationRadius
        let sepS = separationStrength
        let sepR2 = sepR * sepR
        let sens = motionSensitivity

        for i in 0..<count {
            let node = photoNodes[i]
            if node === flyingOutNode { continue }

            var vel = velocities[i]
            let pos_i = positions[i]

            // Gravity (net = gravity - buoyancy; negative = sink)
            let gravForce = simd_float3(0, netGravity, 0)
            let dragForce = -vel * dragCoeff

            // Accelerometer
            let accelForce = accel * sens

            // Gyro swirl
            let toCenter = pos_i - snowflakeCenter
            let swirlForce = simd_cross(rotRate, toCenter) * sens * 0.2

            // Turbulence
            let t = time * 0.3 + turbPhases[i]
            let o = turbOffsets[i]
            let turbForce = simd_float3(
                sin(t * 1.3 + o.x * 3.7) * turbStrength,
                cos(t * 0.9 + o.y * 2.1) * turbStrength * 0.7,
                sin(t * 1.1 + o.z * 4.3) * turbStrength
            )

            // Separation (boid repulsion): push away from neighbors within radius
            var sepForce = simd_float3(0, 0, 0)
            if sepS > 0 && sepR > 0 {
                for j in 0..<count where j != i {
                    let diff = pos_i - positions[j]
                    let dist2 = simd_length_squared(diff)
                    if dist2 < sepR2 && dist2 > 0.0001 {
                        let dist = sqrtf(dist2)
                        // Linear ramp: full strength at dist=0, zero at dist=sepR
                        let magnitude = (sepR - dist) / sepR * sepS
                        sepForce += (diff / dist) * magnitude
                    }
                }
            }

            let totalForce = gravForce + dragForce + turbForce + accelForce + swirlForce + sepForce
            vel += totalForce * dt

            let speed = simd_length(vel)
            if speed > maxSpeed { vel *= maxSpeed / speed }

            var pos = pos_i + vel * dt

            // Sphere boundary
            let offset = pos - snowflakeCenter
            let dist = simd_length(offset)
            if dist > snowflakeRadius {
                let normal = offset / dist
                pos = snowflakeCenter + normal * snowflakeRadius
                let vDotN = simd_dot(vel, normal)
                if vDotN > 0 { vel -= vDotN * normal }
                vel *= wallTangentRetention
                // Optional extra slide-down (defaults to 0; gravity naturally creates this effect)
                if wallSlideDownSpeed > 0 {
                    let down = simd_float3(0, -1, 0)
                    let gTan = down - simd_dot(down, normal) * normal
                    let gLen = simd_length(gTan)
                    if gLen > 0.01 { vel += (gTan / gLen) * wallSlideDownSpeed }
                }
            }

            node.simdPosition = pos
            velocities[i] = vel

            rotSpeeds[i] += (baseRotSpeeds[i] - rotSpeeds[i]) * min(1.0, 2.0 * dt)
            node.simdEulerAngles += rotSpeeds[i] * dt
        }
    }

    // MARK: - Shake

    func shakeSnowflakes() {
        let strength = shakeUpwardForce
        guard strength > 0 else { return }  // 0 = disabled, rely on accelerometer
        for i in 0..<photoNodes.count {
            guard i < velocities.count else { continue }
            velocities[i] = simd_float3(
                Float.random(in: -0.5...0.5) * strength,
                Float.random(in: 0.85...1.25) * strength,
                Float.random(in: -0.5...0.5) * strength
            )
            if i < rotSpeeds.count {
                rotSpeeds[i] = simd_float3(Float.random(in: -3...3), Float.random(in: -3...3), Float.random(in: -3...3))
            }
        }
    }

    // MARK: - Device Motion

    func startDeviceMotion() {
        guard motionManager == nil else { return }
        let manager = CMMotionManager()
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let a = m.userAcceleration
            let sceneAccel = simd_float3(Float(a.x), Float(a.y), Float(-a.z))
            let r = m.rotationRate
            let sceneRot = simd_float3(Float(r.x), Float(r.y), Float(-r.z))
            self.motionLock.lock()
            self.lastUserAccel = sceneAccel
            self.lastRotationRate = sceneRot
            self.motionLock.unlock()
        }
        motionManager = manager
    }

    func stopDeviceMotion() {
        motionManager?.stopDeviceMotionUpdates()
        motionManager = nil
        motionLock.lock()
        lastUserAccel = .zero
        lastRotationRate = .zero
        motionLock.unlock()
    }

    // MARK: - Memory Reveal

    func showMemory(image: UIImage) {
        guard memoryNode == nil else { return }

        let aspect = image.size.width / image.size.height
        let planeHeight: CGFloat = 0.04
        let planeWidth = planeHeight * aspect
        let plane = SCNPlane(width: planeWidth, height: planeHeight)
        plane.cornerRadius = planeHeight * 0.03
        let mat = SCNMaterial()
        mat.diffuse.contents = image
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.name = "memoryNode"
        node.simdPosition = randomPointInSphere()
        node.simdEulerAngles = simd_float3(
            Float.random(in: 0...Float.pi * 2),
            Float.random(in: 0...Float.pi * 2),
            Float.random(in: 0...Float.pi * 2)
        )
        scene.rootNode.addChildNode(node)
        memoryNode = node

        for pn in photoNodes { pn.runAction(SCNAction.fadeOpacity(to: 0.25, duration: 0.5)) }

        // Target = exact center of camera view
        let camForward = cameraNode.simdWorldFront
        let targetPos = cameraNode.simdPosition + camForward * 1.5
        // Plane +Z = front face; camera +Z = toward viewer. Match orientations directly.
        let targetOrientation = cameraNode.simdOrientation

        let move = SCNAction.move(to: SCNVector3(targetPos), duration: 1.2)
        move.timingMode = .easeInEaseOut
        let scaleUp = SCNAction.scale(to: 22.0, duration: 1.2)
        scaleUp.timingMode = .easeInEaseOut
        let orient = SCNAction.customAction(duration: 0.8) { n, elapsed in
            let frac = Float(elapsed / 0.8)
            let s = frac * frac * (3 - 2 * frac)
            n.simdOrientation = simd_slerp(n.simdOrientation, targetOrientation, s)
        }
        let flyOut = SCNAction.group([move, scaleUp, orient])

        node.runAction(flyOut) { [weak self] in
            DispatchQueue.main.async { self?.isShowingMemory = true }
        }
    }

    func dismissMemory() {
        guard let node = memoryNode else { return }
        let group = SCNAction.group([SCNAction.fadeOut(duration: 0.3), SCNAction.scale(to: 0.01, duration: 0.3)])
        node.runAction(group) { [weak self] in
            node.removeFromParentNode()
            self?.memoryNode = nil
            DispatchQueue.main.async {
                guard let self else { return }
                for pn in self.photoNodes { pn.runAction(SCNAction.fadeOpacity(to: 1.0, duration: 0.4)) }
                self.isShowingMemory = false
            }
        }
    }
}
