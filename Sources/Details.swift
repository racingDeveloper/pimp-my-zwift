import Foundation

/// How certain it is that a setting has an effect in Zwift.
enum Effectiveness {
    /// Zwift's own graphics profiles use it: the game reads it at every launch.
    case verified
    /// Zwift's profiles never set it, but the game's code reads it: the effect wasn't seen in game yet.
    case registered
    /// Values beyond what Zwift itself uses: unpredictable result.
    case experimental

    var label: String {
        switch self {
        case .verified: return L("Used by Zwift's own profiles")
        case .registered: return L("Read by the game's code, effect not seen in game yet")
        case .experimental: return L("Experimental")
        }
    }

    var symbol: String {
        switch self {
        case .verified: return "checkmark.circle.fill"
        case .registered: return "questionmark.circle.fill"
        case .experimental: return "flask.fill"
        }
    }
}

struct SettingInfo {
    let effect: Effectiveness
    let detail: String
}

extension Catalog {
    /// Defaults the tweakables are registered with in the Zwift 1.124.0 binary (ZwiftAppSilicon), read from their static initializers.
    /// gSSAO and gRadialBlur are left out: they are registered, but no code reads them.
    /// The graphics profile can change them at launch; the game falls back to these values otherwise.
    static let gameDefaults: [String: String] = [
        "gFXAA": "1", "gForceBikeShadows": "0", "g_BikeMaxShadowCascade": "1", "gLODBias": "0", "gFoliagePercent": "1.00",
        "gSSR": "0", "gSimpleReflections": "0", "gSunRays": "1", "gBloom": "1", "gBloomStrength": "0.50",
        "gVignette": "1", "gAutoExposure": "1", "gHeadlight": "1", "gHeadlightIntensity": "0.50",
        "gShowFPS": "0", "g_bDrawHud": "1", "gUseSpringyCamera": "1", "g_ShouldHideMouseAfterTimeout": "1",
        "g_HideMouseAfterMS": "5000",
    ]

    static func info(for key: String) -> SettingInfo {
        if let info = infos[key] { return info }
        return SettingInfo(effect: .registered, detail: "")
    }

    private static let infos: [String: SettingInfo] = [
        "resolution": .init(effect: .verified, detail: L("How many pixels the game renders. Zwift's menu stops at 3840×2160, but the game accepts up to 5120×2880 (checked: the log reports \"Changed resolution to 5120 x 2880\"). Rendering above the display's resolution and scaling down is supersampling: cleaner edges and finer detail, the biggest sharpness gain available. The GPU cost grows with the pixels: 5120×2880 is 1.8× the pixels of 4K. Pick a size with your display's aspect ratio. The game keeps the value in prefs.xml; choosing a resolution in Zwift's menu replaces it until the next launch from here.")),
        "gFXAA": .init(effect: .verified, detail: L("Fast anti-aliasing applied to the final image: smooths edges almost for free, but makes the image a little softer. On in every Zwift profile.")),
        "sres": .init(effect: .verified, detail: L("Size of the sun's shadow map. 4096 makes the shadows of trees, riders and buildings on the road noticeably sharper, and it's the most the game accepts: 8192 is rejected.")),
        "gForceBikeShadows": .init(effect: .registered, detail: L("Bikes cast shadows only when an internal hardware flag allows it; this forces them on regardless. On a Mac where Zwift already draws bike shadows it changes nothing.")),
        "g_BikeMaxShadowCascade": .init(effect: .registered, detail: L("Sun shadows are split into cascades, from the closest to the most distant. Bikes are drawn into cascades up to this index (game default 1): higher values keep the shadows of bikes further down the road, at a cost that grows with the number of riders.")),

        "gLODBias": .init(effect: .verified, detail: L("The most detailed model level the game may use: 0 allows full detail, 1 and 2 skip the best levels. Zwift's basic and medium profiles use 1. The game clamps it between 0 and 2, so there is no way to go beyond full detail (a negative value would even become 2).")),
        "gFoliagePercent": .init(effect: .verified, detail: L("Share of the trees, bushes and plants that are drawn: the game multiplies each foliage instance count by this value. Zwift's basic and medium profiles use 0.5; 1 (the game default) is the maximum, as more instances than the ones loaded can't be drawn.")),

        "gSSR": .init(effect: .registered, detail: L("Reflections computed from what's on screen: water, wet roads after the rain, shiny surfaces. Off by default and never turned on by Zwift's profiles; the renderer also checks an internal flag before using them, so on some scenes it may change nothing.")),
        "gSimpleReflections": .init(effect: .verified, detail: L("A cheaper reflection model. Zwift's basic and medium profiles turn it on; leave it off for the best image.")),
        "gSunRays": .init(effect: .verified, detail: L("Light shafts when the sun shines through trees and buildings. On by default, off in Zwift's basic and medium profiles.")),
        "gBloom": .init(effect: .registered, detail: L("Glow around the sun and strong lights. Off gives a flatter, more neutral image.")),
        "gBloomStrength": .init(effect: .registered, detail: L("How strong the glow is (game default 0.5). Only used when bloom is on.")),
        "gVignette": .init(effect: .registered, detail: L("Darkens the corners of the image, like a camera lens. Off gives a more even image.")),
        "gAutoExposure": .init(effect: .registered, detail: L("Adapts brightness when going from bright to dark areas (tunnels, forests), like an eye. Off keeps the exposure fixed.")),
        "gHeadlight": .init(effect: .verified, detail: L("The bikes' front lights at dusk and night. On by default, off in Zwift's basic and medium profiles.")),
        "gHeadlightIntensity": .init(effect: .registered, detail: L("Brightness of the headlights (game default 0.5).")),

        "gShowFPS": .init(effect: .registered, detail: L("Zwift's own frame rate counter on screen. Handy to see what each setting costs.")),
        "g_bDrawHud": .init(effect: .registered, detail: L("Off hides power, speed, the map and the other panels: useful for clean screenshots or videos, not for training.")),
        "gUseSpringyCamera": .init(effect: .registered, detail: L("The camera follows the rider with a little spring, smoothing turns and accelerations. Off keeps it rigidly locked.")),
        "g_ShouldHideMouseAfterTimeout": .init(effect: .registered, detail: L("Hides the mouse pointer when it doesn't move.")),
        "g_HideMouseAfterMS": .init(effect: .registered, detail: L("How long the pointer stays visible after the last movement (game default 5 seconds).")),
    ]
}
