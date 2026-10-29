import Foundation

/// Localized string; the English text is the key, translations live in <lang>.lproj/Localizable.strings.
func L(_ value: String.LocalizationValue) -> String {
    String(localized: value)
}

/// How a setting is written into a graphics profile.
enum ProfileCommand {
    /// `set NAME=VALUE`: one of the game's tweakable variables.
    case tweakable
    /// `sres WxH`: shadow map resolution.
    case shadowResolution
    /// `res WxH(Nx)`: multisample anti-aliasing, written with the resolution chosen in the game's menu.
    case msaa
}

struct Option: Hashable {
    let value: String
    let label: String
}

enum Control {
    case choice([Option])
    case slider(min: Double, max: Double, step: Double, decimals: Int, unit: String)
}

struct SettingDef: Identifiable {
    let key: String
    let title: String
    let help: String
    let section: SettingSection
    let control: Control
    var command: ProfileCommand = .tweakable
    var id: String { key }

    /// Normalizes a value and accepts it only if it is one of the allowed values.
    func validated(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch control {
        case .choice(let options):
            return options.contains { $0.value == raw } ? raw : nil
        case .slider(let min, let max, let step, let decimals, _):
            guard let v = Double(raw), v >= min - 1e-9, v <= max + 1e-9 else { return nil }
            let snapped = (min + ((v - min) / step).rounded() * step)
            return SettingDef.format(snapped, decimals: decimals)
        }
    }

    /// Human-readable label for a value (the picker's label, when there is one).
    func label(for value: String) -> String {
        switch control {
        case .choice(let options):
            return options.first { $0.value == value }?.label ?? value
        case .slider(_, _, _, let decimals, let unit):
            let shown = Double(value).map { SettingDef.format($0, decimals: decimals) } ?? value
            return shown + unit
        }
    }

    /// The profile line for a value, e.g. `set gSSAO=1` or `sres 4096x4096`.
    func line(for value: String, resolution: String?) -> String? {
        switch command {
        case .tweakable:
            return "set \(key)=\(value)"
        case .shadowResolution:
            return "sres \(value)x\(value)"
        case .msaa:
            // Without the menu's resolution the line would change it: better not to write it at all.
            return resolution.map { "res \($0)(\(value)x)" }
        }
    }

    static func format(_ v: Double, decimals: Int) -> String {
        decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
    }
}

enum SettingSection: String, CaseIterable, Identifiable {
    case antiAliasing, detail, effects, display
    var id: String { rawValue }

    var title: String {
        switch self {
        case .antiAliasing: return L("Anti-aliasing & shadows")
        case .detail: return L("Detail")
        case .effects: return L("Effects")
        case .display: return L("HUD & display")
        }
    }

    var symbol: String {
        switch self {
        case .antiAliasing: return "viewfinder"
        case .detail: return "mountain.2"
        case .effects: return "sparkles"
        case .display: return "macwindow"
        }
    }

    var note: String? {
        switch self {
        case .antiAliasing:
            return L("Zwift picks a graphics profile (basic, medium, high or ultra) from its own list of GPUs, then applies the resolution chosen in its menu. The menu has no anti-aliasing or shadow settings.")
        case .detail:
            return L("Zwift's lower profiles halve the foliage and raise the level-of-detail bias; ultra leaves both at the game's defaults.")
        default:
            return nil
        }
    }
}

private let onOff = [Option(value: "0", label: L("Off")), Option(value: "1", label: L("On"))]

private func tweak(_ key: String, _ title: String, _ section: SettingSection, _ control: Control = .choice(onOff)) -> SettingDef {
    let help: String
    switch control {
    case .choice: help = L("Tweakable \(key), written as \"set \(key)=…\".")
    case .slider: help = L("Tweakable \(key) (decimal number), written as \"set \(key)=…\".")
    }
    return SettingDef(key: key, title: title, help: help, section: section, control: control)
}

enum Catalog {
    static let all: [SettingDef] = [
        // Anti-aliasing & shadows
        SettingDef(key: "msaa", title: L("MSAA"),
                   help: L("Written as \"res WIDTHxHEIGHT(Nx)\", using the resolution chosen in Zwift's menu (USER_RESOLUTION_PREF in prefs.xml)."),
                   section: .antiAliasing, control: .choice([
                       Option(value: "0", label: L("Off")), Option(value: "4", label: "4×"),
                   ]), command: .msaa),
        tweak("gFXAA", "FXAA", .antiAliasing),
        SettingDef(key: "sres", title: L("Shadow resolution"),
                   help: L("Written as \"sres SIZExSIZE\". Zwift's profiles use 512 (basic) to 2048 (ultra)."),
                   section: .antiAliasing, control: .choice(["1024", "2048", "4096", "8192"].map { Option(value: $0, label: "\($0)×\($0)") }),
                   command: .shadowResolution),
        tweak("gForceBikeShadows", L("Shadows on every bike"), .antiAliasing),
        tweak("g_BikeMaxShadowCascade", L("Bike shadow cascades"), .antiAliasing,
              .choice(["1", "2", "3", "4"].map { Option(value: $0, label: $0) })),

        // Detail
        tweak("gLODBias", L("Level-of-detail bias"), .detail, .choice([
            Option(value: "-1", label: L("-1 · More detail")), Option(value: "0", label: L("0 · Normal")),
            Option(value: "1", label: L("1 · Less detail")), Option(value: "2", label: L("2 · Much less detail")),
        ])),
        tweak("gFoliagePercent", L("Foliage density"), .detail, .slider(min: 0.25, max: 1.5, step: 0.25, decimals: 2, unit: "×")),

        // Effects
        tweak("gSSAO", L("Ambient occlusion (SSAO)"), .effects),
        tweak("gSSR", L("Screen-space reflections"), .effects),
        tweak("gSimpleReflections", L("Simplified reflections"), .effects),
        tweak("gSunRays", L("Sun rays"), .effects),
        tweak("gBloom", L("Bloom"), .effects),
        tweak("gBloomStrength", L("Bloom strength"), .effects, .slider(min: 0, max: 1.5, step: 0.05, decimals: 2, unit: "")),
        tweak("gRadialBlur", L("Radial blur"), .effects),
        tweak("gVignette", L("Vignette"), .effects),
        tweak("gAutoExposure", L("Auto exposure"), .effects),
        tweak("gHeadlight", L("Headlights"), .effects),
        tweak("gHeadlightIntensity", L("Headlight intensity"), .effects, .slider(min: 0, max: 1.5, step: 0.05, decimals: 2, unit: "")),

        // HUD & display
        tweak("gShowFPS", L("FPS counter"), .display),
        tweak("g_bDrawHud", L("Show the HUD"), .display),
        tweak("gUseSpringyCamera", L("Springy camera"), .display),
        tweak("g_ShouldHideMouseAfterTimeout", L("Hide the mouse pointer"), .display),
        tweak("g_HideMouseAfterMS", L("Hide the pointer after"), .display,
              .choice(["1000", "2000", "5000", "10000"].map { Option(value: $0, label: L("\(String(Int($0)! / 1000)) s")) })),
    ]

    static let byKey: [String: SettingDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static func validated(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, pair in
            if let v = byKey[pair.key]?.validated(pair.value) { result[pair.key] = v }
        }
    }
}

struct Preset: Identifiable, Hashable {
    /// Stable identifier, stored in UserDefaults; never shown.
    let id: String
    let name: String
    let summary: String
    let values: [String: String]

    static let customID = "custom"
    static var custom: Preset {
        Preset(id: customID, name: L("Custom"), summary: L("Hand-tuned values, remembered for the next launches."), values: [:])
    }

    static let builtIn: [Preset] = [
        Preset(id: "max", name: L("Max"), summary: L("Everything Zwift can do on a powerful Mac: 4096 shadows, ambient occlusion, reflections and sun rays, no radial blur."),
               values: [
                   "sres": "4096", "gFXAA": "1", "gForceBikeShadows": "1",
                   "gLODBias": "0", "gFoliagePercent": "1.00",
                   "gSSAO": "1", "gSSR": "1", "gSimpleReflections": "0", "gSunRays": "1", "gHeadlight": "1",
                   "gRadialBlur": "0",
               ]),
        Preset(id: "balanced", name: L("Balanced"), summary: L("Like Zwift's ultra profile, with sun rays guaranteed and no radial blur."),
               values: [
                   "sres": "2048", "gFXAA": "1", "gSSAO": "1", "gSunRays": "1", "gRadialBlur": "0",
               ]),
        Preset(id: "performance", name: L("Performance"), summary: L("Zwift's medium profile with smaller shadows, for less powerful Macs or steadier FPS."),
               values: [
                   "sres": "1024", "gFXAA": "1", "gSSAO": "0", "gSunRays": "0", "gHeadlight": "0",
                   "gFoliagePercent": "0.50", "gSimpleReflections": "1", "gLODBias": "1",
               ]),
        Preset(id: "original", name: L("Game default"), summary: L("No changes: Zwift's own profiles, as if this app weren't there."),
               values: [:]),
    ]
}
