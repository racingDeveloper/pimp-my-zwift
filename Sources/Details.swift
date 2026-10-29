import Foundation

/// How certain it is that a setting has an effect in Zwift.
enum Effectiveness {
    /// Zwift's own graphics profiles use it: the game reads it at every launch.
    case verified
    /// Registered as a tweakable in the game, but Zwift's profiles never set it: the effect wasn't observed.
    case registered
    /// Values beyond what Zwift itself uses: unpredictable result.
    case experimental

    var label: String {
        switch self {
        case .verified: return L("Used by Zwift's own profiles")
        case .registered: return L("Present in the game, effect not verified")
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
    /// The graphics profile can change them at launch; the game falls back to these values otherwise.
    static let gameDefaults: [String: String] = [
        "gFXAA": "1", "gForceBikeShadows": "0", "g_BikeMaxShadowCascade": "1", "gLODBias": "0", "gFoliagePercent": "1.00",
        "gSSAO": "0", "gSSR": "0", "gSimpleReflections": "0", "gSunRays": "1", "gBloom": "1", "gBloomStrength": "0.50",
        "gRadialBlur": "1", "gVignette": "1", "gAutoExposure": "1", "gHeadlight": "1", "gHeadlightIntensity": "0.50",
        "gShowFPS": "0", "g_bDrawHud": "1", "gUseSpringyCamera": "1", "g_ShouldHideMouseAfterTimeout": "1",
        "g_HideMouseAfterMS": "5000",
    ]

    static func info(for key: String) -> SettingInfo {
        if let info = infos[key] { return info }
        return SettingInfo(effect: .registered, detail: "")
    }

    private static let infos: [String: SettingInfo] = [
        "msaa": .init(effect: .experimental, detail: L("Multisample anti-aliasing smooths the edges of geometry (bikes, riders, barriers) better than FXAA, at a high GPU cost. Zwift's profiles turn it off. The resolution set in Zwift's menu is applied after the profile without an MSAA value: whether MSAA survives that is unverified. Check the log for \"Changed resolution\". If the game already renders at a higher resolution than the display, the gain is small.")),
        "gFXAA": .init(effect: .verified, detail: L("Fast anti-aliasing applied to the final image: smooths edges almost for free, but makes the image a little softer. On in every Zwift profile.")),
        "sres": .init(effect: .verified, detail: L("Size of the sun's shadow map. 4096 makes the shadows of trees, riders and buildings on the road noticeably sharper; 8192 is very heavy on GPU memory and goes beyond what Zwift itself uses.")),
        "gForceBikeShadows": .init(effect: .registered, detail: L("Draws shadows for every bike, not only the closest ones. Noticeable in big groups and events; the cost grows with the number of riders on screen.")),
        "g_BikeMaxShadowCascade": .init(effect: .experimental, detail: L("How many shadow cascades bikes are drawn into (game default 1). Higher values could keep bike shadows at greater distances; the effect wasn't observed.")),

        "gLODBias": .init(effect: .verified, detail: L("When objects switch to simpler models. Zwift's basic and medium profiles use 1; ultra leaves 0. -1 is beyond what Zwift uses: it might keep full detail further away, or have no effect.")),
        "gFoliagePercent": .init(effect: .verified, detail: L("How many trees, bushes and plants are drawn. Zwift's basic and medium profiles use 0.5; the game default is 1. Values above 1 are beyond what Zwift uses.")),

        "gSSAO": .init(effect: .verified, detail: L("Soft shading in corners and where objects touch the ground: gives depth to scenery and riders. Off by default, on in Zwift's high and ultra profiles. Moderate GPU cost.")),
        "gSSR": .init(effect: .registered, detail: L("Reflections computed from what's on screen: water, wet roads after the rain, shiny surfaces. Off by default and never turned on by Zwift's profiles.")),
        "gSimpleReflections": .init(effect: .verified, detail: L("A cheaper reflection model. Zwift's basic and medium profiles turn it on; leave it off for the best image.")),
        "gSunRays": .init(effect: .verified, detail: L("Light shafts when the sun shines through trees and buildings. On by default, off in Zwift's basic and medium profiles.")),
        "gBloom": .init(effect: .registered, detail: L("Glow around the sun and strong lights. Off gives a flatter, more neutral image.")),
        "gBloomStrength": .init(effect: .registered, detail: L("How strong the glow is (game default 0.5). Only used when bloom is on.")),
        "gRadialBlur": .init(effect: .registered, detail: L("Blur toward the screen edges, typically when going fast. Many prefer it off for a sharper image during long rides.")),
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
