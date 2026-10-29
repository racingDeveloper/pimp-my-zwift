import Foundation

/// Localized string; the English text is the key, translations live in <lang>.lproj/Localizable.strings.
func L(_ value: String.LocalizationValue) -> String {
    String(localized: value)
}

/// How a setting is written.
enum ProfileCommand: Equatable {
    /// `set NAME=VALUE` in the graphics profiles: one of the game's tweakable variables.
    case tweakable
    /// `sres WxH` in the graphics profiles: shadow map resolution.
    case shadowResolution
    /// An element of prefs.xml, by path below the root (e.g. ["CONFIG", "USER_RESOLUTION_PREF"]).
    /// The render resolution goes there: the game runs `res <value>` with it after the profile, so a profile line would be overridden.
    case prefs([String])
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

    /// The profile line for a value, e.g. `set gSSR=1` or `sres 4096x4096`; nil for settings written elsewhere.
    func line(for value: String) -> String? {
        switch command {
        case .tweakable:
            return "set \(key)=\(value)"
        case .shadowResolution:
            return "sres \(value)x\(value)"
        case .prefs:
            return nil
        }
    }

    /// Where the setting lives in prefs.xml, for settings written there.
    var prefsPath: [String]? {
        if case .prefs(let path) = command { return path }
        return nil
    }

    static func format(_ v: Double, decimals: Int) -> String {
        decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
    }
}

enum SettingSection: String, CaseIterable, Identifiable {
    case resolution, detail, effects, display, ride, video
    var id: String { rawValue }

    var title: String {
        switch self {
        case .resolution: return L("Resolution & shadows")
        case .detail: return L("Detail")
        case .effects: return L("Effects")
        case .display: return L("HUD & display")
        case .ride: return L("Ride & audio")
        case .video: return L("Video routes")
        }
    }

    var symbol: String {
        switch self {
        case .resolution: return "viewfinder"
        case .detail: return "mountain.2"
        case .effects: return "sparkles"
        case .display: return "macwindow"
        case .ride: return "figure.outdoor.cycle"
        case .video: return "film"
        }
    }

    var note: String? {
        switch self {
        case .resolution:
            return L("Zwift picks a graphics profile (basic, medium, high or ultra) from its own list of GPUs, then applies the resolution chosen in its menu. The game accepts resolutions up to 5120×2880, beyond the menu's 4K: rendering more pixels than the display has and scaling them down gives a sharper image. MSAA isn't offered: on the Mac it was tested on (M2 Max) the game refused it, even at 2×.")
        case .detail:
            return L("Zwift's lower profiles halve the foliage and raise the level-of-detail bias; ultra leaves both at full detail, which is also the most the game allows.")
        case .ride:
            return L("Settings that don't change the image. None of them touches power, speed, drafting or results.")
        case .video:
            return L("Zwift's video routes stream real footage, recorded in 4K at about 120 frames per second and downloaded in segments of about 30 seconds (roughly 70 Mbit/s). If the download can't keep up, the game slows your rider down or stops it until the video is ready.")
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
        // Resolution & shadows
        SettingDef(key: "resolution", title: L("Render resolution"),
                   help: L("USER_RESOLUTION_PREF in ~/Documents/Zwift/prefs.xml, the value Zwift's menu saves. The game accepts 320×240 to 5120×2880."),
                   section: .resolution, control: .choice([
                       Option(value: "1920x1080", label: "1920×1080"), Option(value: "2560x1440", label: "2560×1440"),
                       Option(value: "3840x2160", label: L("3840×2160 (menu maximum)")),
                       Option(value: "4480x2520", label: "4480×2520"), Option(value: "5120x2880", label: L("5120×2880 (game maximum)")),
                   ]), command: .prefs(["CONFIG", "USER_RESOLUTION_PREF"])),
        tweak("gFXAA", "FXAA", .resolution),
        SettingDef(key: "sres", title: L("Shadow resolution"),
                   help: L("Written as \"sres SIZExSIZE\". Zwift's profiles use 512 (basic) to 2048 (ultra); the game accepts 256 to 4096."),
                   // The game rejects sides outside 256–4096 ("Error with resolution values").
                   section: .resolution, control: .choice(["1024", "2048", "4096"].map { Option(value: $0, label: "\($0)×\($0)") }),
                   command: .shadowResolution),
        tweak("gForceBikeShadows", L("Shadows on every bike"), .resolution),
        tweak("g_BikeMaxShadowCascade", L("Bike shadow cascades"), .resolution,
              .choice(["1", "2", "3", "4"].map { Option(value: $0, label: $0) })),

        // Detail
        tweak("gLODBias", L("Level-of-detail bias"), .detail, .choice([
            Option(value: "0", label: L("0 · Full detail")), Option(value: "1", label: L("1 · Less detail")),
            Option(value: "2", label: L("2 · Much less detail")),
        ])),
        // The game multiplies its foliage instance counts by this value: above 1 they would exceed what was loaded.
        tweak("gFoliagePercent", L("Foliage density"), .detail, .slider(min: 0.25, max: 1, step: 0.25, decimals: 2, unit: "×")),

        // Effects
        tweak("gSSR", L("Screen-space reflections"), .effects),
        tweak("gSimpleReflections", L("Simplified reflections"), .effects),
        tweak("gSunRays", L("Sun rays"), .effects),
        tweak("gBloom", L("Bloom"), .effects),
        tweak("gBloomStrength", L("Bloom strength"), .effects, .slider(min: 0, max: 1.5, step: 0.05, decimals: 2, unit: "")),
        tweak("gVignette", L("Vignette"), .effects),
        tweak("gAutoExposure", L("Auto exposure"), .effects),
        tweak("gHeadlight", L("Headlights"), .effects),
        tweak("gHeadlightIntensity", L("Headlight intensity"), .effects, .slider(min: 0, max: 1.5, step: 0.05, decimals: 2, unit: "")),
        tweak("g_FireworkNightShowAlwaysOn", L("Fireworks every night"), .effects),

        // HUD & display
        tweak("gShowFPS", L("FPS counter"), .display),
        tweak("g_bDrawHud", L("Show the HUD"), .display),
        tweak("g_elevationProfile_DrawDistanceCM", L("Elevation profile distance"), .display, .choice([
            Option(value: "100000", label: "1 km"), Option(value: "200000", label: "2 km"),
            Option(value: "300000", label: "3 km"), Option(value: "500000", label: "5 km"),
        ])),
        tweak("g_elevationProfile_Height", L("Elevation profile height"), .display, .slider(min: 60, max: 150, step: 1, decimals: 0, unit: "")),

        // Ride & audio
        tweak("g_minPowerPauseThreshold", L("Workout auto-pause below"), .ride,
              .choice(["10", "20", "30", "40", "50"].map { Option(value: $0, label: "\($0) W") })),
        tweak("g_workoutAutoPauseTime", L("Workout auto-pause after"), .ride,
              .choice(["1", "2", "3", "5", "10"].map { Option(value: $0, label: L("\($0) s")) })),
        SettingDef(key: "ANNOUNCER_VOL", title: L("Announcer volume"),
                   help: L("ANNOUNCER_VOL in prefs.xml: the other volumes are in Zwift's menu, this one isn't."),
                   section: .ride, control: .slider(min: 0, max: 1, step: 0.05, decimals: 2, unit: ""),
                   command: .prefs(["CONFIG", "ANNOUNCER_VOL"])),
        SettingDef(key: "IGNOREGODMESSAGES", title: L("Hide messages from Zwift HQ"),
                   help: L("IGNOREGODMESSAGES in prefs.xml."),
                   section: .ride, control: .choice(onOff), command: .prefs(["CONFIG", "IGNOREGODMESSAGES"])),
        tweak("g_enableEventHaptics", L("Event vibrations"), .ride),
        tweak("g_cameraLookBackTime", L("Look-back camera duration"), .ride,
              .choice(["2", "3", "5", "8", "10"].map { Option(value: $0, label: L("\($0) s")) })),
        tweak("g_BikeSoundDistCutoffCentemeters", L("Hear other bikes within"), .ride,
              .choice([("2500", "25 m"), ("5000", "50 m"), ("10000", "100 m"), ("20000", "200 m"), ("50000", "500 m")].map { Option(value: $0.0, label: $0.1) })),
        tweak("g_phoneRiderListUpdateTime", L("Companion rider list refresh"), .ride,
              .choice(["2000", "5000", "10000"].map { Option(value: $0, label: L("\(String(Int($0)! / 1000)) s")) })),

        // Video routes
        SettingDef(key: "MOCHI_RESOLUTION", title: L("Video resolution"),
                   help: L("MOCHI\\RESOLUTION_PREF in prefs.xml, also in Zwift's menu."),
                   section: .video, control: .choice(["1080p", "1440p", "2160p"].map { Option(value: $0, label: $0) }),
                   command: .prefs(["CONFIG", "MOCHI", "RESOLUTION_PREF"])),
        SettingDef(key: "MOCHI_DOWNLOAD_FULL", title: L("Download the whole route before starting"),
                   help: L("MOCHI\\DOWNLOAD_FULL in prefs.xml."),
                   section: .video, control: .choice(onOff), command: .prefs(["CONFIG", "MOCHI", "DOWNLOAD_FULL"])),
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
        Preset(id: "max", name: L("Max"), summary: L("Everything Zwift can do on a powerful Mac: rendering at 5120×2880, 4096 shadows, bike shadows further away, reflections and sun rays at full detail."),
               values: [
                   "resolution": "5120x2880", "sres": "4096", "gFXAA": "1", "gForceBikeShadows": "1", "g_BikeMaxShadowCascade": "2",
                   "gLODBias": "0", "gFoliagePercent": "1.00",
                   "gSSR": "1", "gSimpleReflections": "0", "gSunRays": "1", "gHeadlight": "1",
               ]),
        Preset(id: "balanced", name: L("Balanced"), summary: L("Zwift's ultra profile with screen-space reflections on."),
               values: [
                   "sres": "2048", "gFXAA": "1", "gSSR": "1", "gSunRays": "1",
               ]),
        Preset(id: "performance", name: L("Performance"), summary: L("Zwift's medium profile with smaller shadows, for less powerful Macs or steadier FPS."),
               values: [
                   "sres": "1024", "gFXAA": "1", "gSunRays": "0", "gHeadlight": "0",
                   "gFoliagePercent": "0.50", "gSimpleReflections": "1", "gLODBias": "1",
               ]),
        Preset(id: "original", name: L("Game default"), summary: L("No changes: Zwift's own profiles, as if this app weren't there."),
               values: [:]),
    ]
}
