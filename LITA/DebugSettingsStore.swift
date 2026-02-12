//
//  DebugSettingsStore.swift
//  LITA
//

import Foundation

enum DebugSettingsStore {
    private static let suite = UserDefaults.standard
    private enum Keys {
        static let envMapName = "lita_debug_envMapName"
        static let envIntensity = "lita_debug_envIntensity"
        static let glassTransparency = "lita_debug_glassTransparency"
        static let glassRoughness = "lita_debug_glassRoughness"
        static let glassFresnel = "lita_debug_glassFresnel"
        static let snowRoughness = "lita_debug_snowRoughness"
        static let snowMetalness = "lita_debug_snowMetalness"
        static let woodRoughness = "lita_debug_woodRoughness"
        static let woodMetalness = "lita_debug_woodMetalness"
        static let treeRoughness = "lita_debug_treeRoughness"
        static let treeMetalness = "lita_debug_treeMetalness"
        // Physics
        static let motionSensitivity = "lita_debug_motionSensitivity"
        static let shakeUpwardForce = "lita_debug_shakeUpwardForce"
        static let gravity = "lita_debug_gravity"
        static let dragCoeff = "lita_debug_dragCoeff"
        static let wallSlideDownSpeed = "lita_debug_wallSlideDownSpeed"
        static let separationRadius = "lita_debug_separationRadius"
        static let separationStrength = "lita_debug_separationStrength"
    }

    struct Values {
        var envMapName: String = "artist_workshop_1k"
        var envIntensity: Float = 1
        var glassTransparency: Float = 0.1
        var glassRoughness: Float = 0
        var glassFresnel: Float = 2.682
        var snowRoughness: Float = 0
        var snowMetalness: Float = 0.95
        var woodRoughness: Float = 0
        var woodMetalness: Float = 0.465
        var treeRoughness: Float = 0.1
        var treeMetalness: Float = 0.85
        // Physics
        var motionSensitivity: Float = 3.0
        var shakeUpwardForce: Float = 0
        var gravity: Float = -0.012       // net downward (gravity - buoyancy); flakes slightly denser than water
        var dragCoeff: Float = 1.0
        var wallSlideDownSpeed: Float = 0  // 0 = let gravity handle it naturally
        var separationRadius: Float = 0.15
        var separationStrength: Float = 0.7
    }

    static func load() -> Values {
        Values(
            envMapName: suite.string(forKey: Keys.envMapName) ?? "artist_workshop_1k",
            envIntensity: f(suite.object(forKey: Keys.envIntensity), 1),
            glassTransparency: f(suite.object(forKey: Keys.glassTransparency), 0.1),
            glassRoughness: f(suite.object(forKey: Keys.glassRoughness), 0),
            glassFresnel: f(suite.object(forKey: Keys.glassFresnel), 2.682),
            snowRoughness: f(suite.object(forKey: Keys.snowRoughness), 0),
            snowMetalness: f(suite.object(forKey: Keys.snowMetalness), 0.95),
            woodRoughness: f(suite.object(forKey: Keys.woodRoughness), 0),
            woodMetalness: f(suite.object(forKey: Keys.woodMetalness), 0.465),
            treeRoughness: f(suite.object(forKey: Keys.treeRoughness), 0.1),
            treeMetalness: f(suite.object(forKey: Keys.treeMetalness), 0.85),
            motionSensitivity: f(suite.object(forKey: Keys.motionSensitivity), 3.0),
            shakeUpwardForce: f(suite.object(forKey: Keys.shakeUpwardForce), 0),
            gravity: f(suite.object(forKey: Keys.gravity), -0.012),
            dragCoeff: f(suite.object(forKey: Keys.dragCoeff), 1.0),
            wallSlideDownSpeed: f(suite.object(forKey: Keys.wallSlideDownSpeed), 0),
            separationRadius: f(suite.object(forKey: Keys.separationRadius), 0.15),
            separationStrength: f(suite.object(forKey: Keys.separationStrength), 0.7)
        )
    }

    private static func f(_ obj: Any?, _ `default`: Float) -> Float {
        obj.flatMap { $0 as? NSNumber }.map { $0.floatValue } ?? `default`
    }

    static func save(_ v: Values) {
        suite.set(v.envMapName, forKey: Keys.envMapName)
        suite.set(v.envIntensity, forKey: Keys.envIntensity)
        suite.set(v.glassTransparency, forKey: Keys.glassTransparency)
        suite.set(v.glassRoughness, forKey: Keys.glassRoughness)
        suite.set(v.glassFresnel, forKey: Keys.glassFresnel)
        suite.set(v.snowRoughness, forKey: Keys.snowRoughness)
        suite.set(v.snowMetalness, forKey: Keys.snowMetalness)
        suite.set(v.woodRoughness, forKey: Keys.woodRoughness)
        suite.set(v.woodMetalness, forKey: Keys.woodMetalness)
        suite.set(v.treeRoughness, forKey: Keys.treeRoughness)
        suite.set(v.treeMetalness, forKey: Keys.treeMetalness)
        suite.set(v.motionSensitivity, forKey: Keys.motionSensitivity)
        suite.set(v.shakeUpwardForce, forKey: Keys.shakeUpwardForce)
        suite.set(v.gravity, forKey: Keys.gravity)
        suite.set(v.dragCoeff, forKey: Keys.dragCoeff)
        suite.set(v.wallSlideDownSpeed, forKey: Keys.wallSlideDownSpeed)
        suite.set(v.separationRadius, forKey: Keys.separationRadius)
        suite.set(v.separationStrength, forKey: Keys.separationStrength)
    }
}
