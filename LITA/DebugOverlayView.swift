//
//  DebugOverlayView.swift
//  LITA
//

import SwiftUI

// MARK: - Observable debug state (shared between sub-views)

final class DebugState: ObservableObject {
    let controller: SnowGlobeSceneController

    // Environment
    @Published var envMapName = "artist_workshop_1k"
    @Published var envIntensity: Float = 1

    // Glass
    @Published var glassTransparency: Float = 0.1
    @Published var glassRoughness: Float = 0
    @Published var glassFresnel: Float = 2.682

    // Snow
    @Published var snowRoughness: Float = 0
    @Published var snowMetalness: Float = 0.95

    // Wood
    @Published var woodRoughness: Float = 0
    @Published var woodMetalness: Float = 0.465

    // Trees
    @Published var treeRoughness: Float = 0.1
    @Published var treeMetalness: Float = 0.85

    // Physics
    @Published var motionSensitivity: Float = 3.0
    @Published var shakeUpwardForce: Float = 0
    @Published var gravity: Float = -0.012
    @Published var dragCoeff: Float = 1.0
    @Published var wallSlideDownSpeed: Float = 0
    @Published var separationRadius: Float = 0.15
    @Published var separationStrength: Float = 0.7

    init(controller: SnowGlobeSceneController) {
        self.controller = controller
    }

    func loadFromStore() {
        let s = DebugSettingsStore.load()
        envMapName = s.envMapName
        envIntensity = s.envIntensity
        glassTransparency = s.glassTransparency
        glassRoughness = s.glassRoughness
        glassFresnel = s.glassFresnel
        snowRoughness = s.snowRoughness
        snowMetalness = s.snowMetalness
        woodRoughness = s.woodRoughness
        woodMetalness = s.woodMetalness
        treeRoughness = s.treeRoughness
        treeMetalness = s.treeMetalness
        motionSensitivity = s.motionSensitivity
        shakeUpwardForce = s.shakeUpwardForce
        gravity = s.gravity
        dragCoeff = s.dragCoeff
        wallSlideDownSpeed = s.wallSlideDownSpeed
        separationRadius = s.separationRadius
        separationStrength = s.separationStrength
    }

    func persist() {
        DebugSettingsStore.save(DebugSettingsStore.Values(
            envMapName: envMapName,
            envIntensity: envIntensity,
            glassTransparency: glassTransparency,
            glassRoughness: glassRoughness,
            glassFresnel: glassFresnel,
            snowRoughness: snowRoughness,
            snowMetalness: snowMetalness,
            woodRoughness: woodRoughness,
            woodMetalness: woodMetalness,
            treeRoughness: treeRoughness,
            treeMetalness: treeMetalness,
            motionSensitivity: motionSensitivity,
            shakeUpwardForce: shakeUpwardForce,
            gravity: gravity,
            dragCoeff: dragCoeff,
            wallSlideDownSpeed: wallSlideDownSpeed,
            separationRadius: separationRadius,
            separationStrength: separationStrength
        ))
    }

    func applyAll() {
        applyPhysics()
        applyEnv()
        applyGlass()
        applySnow()
        applyWood()
        applyTree()
    }

    func applyPhysics() {
        controller.setPhysics(
            motionSensitivity: motionSensitivity,
            shakeUpwardForce: shakeUpwardForce,
            gravity: gravity,
            dragCoeff: dragCoeff,
            wallSlideDownSpeed: wallSlideDownSpeed,
            separationRadius: separationRadius,
            separationStrength: separationStrength
        )
    }

    func applyEnv() {
        controller.setEnvironmentMap(name: envMapName, intensity: envIntensity)
    }

    func applyGlass() {
        controller.updateGlass(transparency: glassTransparency, roughness: glassRoughness, fresnel: glassFresnel)
    }

    func applySnow() {
        controller.updateSnow(roughness: snowRoughness, metalness: snowMetalness)
    }

    func applyWood() {
        controller.updateWood(roughness: woodRoughness, metalness: woodMetalness)
    }

    func applyTree() {
        controller.updateTree(roughness: treeRoughness, metalness: treeMetalness)
    }
}

// MARK: - Main Debug Overlay

struct DebugOverlayView: View {
    let controller: SnowGlobeSceneController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: DebugState

    init(controller: SnowGlobeSceneController) {
        self.controller = controller
        _state = StateObject(wrappedValue: DebugState(controller: controller))
    }

    var body: some View {
        NavigationStack {
            Form {
                PhysicsSection(state: state)
                EnvironmentSection(state: state)
                GlassSection(state: state)
                SnowSection(state: state)
                WoodSection(state: state)
                TreeSection(state: state)
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            state.loadFromStore()
            state.applyAll()
        }
    }
}

// MARK: - Section Sub-Views

private struct PhysicsSection: View {
    @ObservedObject var state: DebugState

    var body: some View {
        Section("Physics") {
            DebugSlider(label: "Motion sensitivity", value: $state.motionSensitivity, range: 0...10)
            DebugSlider(label: "Shake upward force", value: $state.shakeUpwardForce, range: 0...3)
            DebugSlider(label: "Gravity (net)", value: $state.gravity, range: -0.1...0)
            DebugSlider(label: "Drag", value: $state.dragCoeff, range: 0.1...5)
            DebugSlider(label: "Wall slide-down", value: $state.wallSlideDownSpeed, range: 0...0.3)
            DebugSlider(label: "Separation radius", value: $state.separationRadius, range: 0...0.3)
            DebugSlider(label: "Separation strength", value: $state.separationStrength, range: 0...2)
        }
        .onChange(of: state.motionSensitivity) { _, _ in state.applyPhysics(); state.persist() }
        .onChange(of: state.shakeUpwardForce) { _, _ in state.applyPhysics(); state.persist() }
        .onChange(of: state.gravity) { _, _ in state.applyPhysics(); state.persist() }
        .onChange(of: state.dragCoeff) { _, _ in state.applyPhysics(); state.persist() }
        .onChange(of: state.wallSlideDownSpeed) { _, _ in state.applyPhysics(); state.persist() }
        .onChange(of: state.separationRadius) { _, _ in state.applyPhysics(); state.persist() }
        .onChange(of: state.separationStrength) { _, _ in state.applyPhysics(); state.persist() }
    }
}

private struct EnvironmentSection: View {
    @ObservedObject var state: DebugState

    var body: some View {
        Section("Environment Map") {
            Picker("Map", selection: $state.envMapName) {
                Text("None").tag("")
                ForEach(state.controller.availableEnvMaps, id: \.self) { name in
                    Text(name.replacingOccurrences(of: "_", with: " ")).tag(name)
                }
            }
            DebugSlider(label: "Intensity", value: $state.envIntensity, range: 0...5)
        }
        .onChange(of: state.envMapName) { _, _ in state.applyEnv(); state.persist() }
        .onChange(of: state.envIntensity) { _, _ in state.applyEnv(); state.persist() }
    }
}

private struct GlassSection: View {
    @ObservedObject var state: DebugState

    var body: some View {
        Section("Glass Sphere") {
            DebugSlider(label: "Transparency", value: $state.glassTransparency, range: 0...1)
            DebugSlider(label: "Roughness", value: $state.glassRoughness, range: 0...1)
            DebugSlider(label: "Fresnel", value: $state.glassFresnel, range: 0...10)
        }
        .onChange(of: state.glassTransparency) { _, _ in state.applyGlass(); state.persist() }
        .onChange(of: state.glassRoughness) { _, _ in state.applyGlass(); state.persist() }
        .onChange(of: state.glassFresnel) { _, _ in state.applyGlass(); state.persist() }
    }
}

private struct SnowSection: View {
    @ObservedObject var state: DebugState

    var body: some View {
        Section("Snow") {
            DebugSlider(label: "Roughness", value: $state.snowRoughness, range: 0...1)
            DebugSlider(label: "Metalness", value: $state.snowMetalness, range: 0...1)
        }
        .onChange(of: state.snowRoughness) { _, _ in state.applySnow(); state.persist() }
        .onChange(of: state.snowMetalness) { _, _ in state.applySnow(); state.persist() }
    }
}

private struct WoodSection: View {
    @ObservedObject var state: DebugState

    var body: some View {
        Section("Wood / House") {
            DebugSlider(label: "Roughness", value: $state.woodRoughness, range: 0...1)
            DebugSlider(label: "Metalness", value: $state.woodMetalness, range: 0...1)
        }
        .onChange(of: state.woodRoughness) { _, _ in state.applyWood(); state.persist() }
        .onChange(of: state.woodMetalness) { _, _ in state.applyWood(); state.persist() }
    }
}

private struct TreeSection: View {
    @ObservedObject var state: DebugState

    var body: some View {
        Section("Trees") {
            DebugSlider(label: "Roughness", value: $state.treeRoughness, range: 0...1)
            DebugSlider(label: "Metalness", value: $state.treeMetalness, range: 0...1)
        }
        .onChange(of: state.treeRoughness) { _, _ in state.applyTree(); state.persist() }
        .onChange(of: state.treeMetalness) { _, _ in state.applyTree(); state.persist() }
    }
}

// MARK: - Reusable Slider

struct DebugSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.3f", value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
