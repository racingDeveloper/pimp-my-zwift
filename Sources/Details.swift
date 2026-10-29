import Foundation

/// How certain it is that a setting has an effect in Zwift.
enum Effectiveness {
    /// Zwift's own graphics profiles use it, or it was checked in game (log and screen).
    case verified
    /// Zwift's profiles never set it, but the game's code reads it: the effect wasn't seen in game yet.
    case registered
    /// Values beyond what Zwift itself uses: unpredictable result.
    case experimental

    var label: String {
        switch self {
        case .verified: return L("Verified: used by Zwift's profiles or checked in game")
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
        "g_HideMouseAfterMS": "5000", "g_elevationProfile_DrawDistanceCM": "100000", "g_elevationProfile_Height": "76",
        "g_FireworkNightShowAlwaysOn": "0", "g_minPowerPauseThreshold": "20", "g_workoutAutoPauseTime": "3",
        "g_enableEventHaptics": "1", "g_cameraLookBackTime": "5", "g_BikeSoundDistCutoffCentemeters": "10000",
        "g_phoneRiderListUpdateTime": "5000", "ANNOUNCER_VOL": "1.00", "IGNOREGODMESSAGES": "0", "MOCHI_DOWNLOAD_FULL": "0",
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
        "g_elevationProfile_DrawDistanceCM": .init(effect: .verified, detail: L("How much road ahead the small elevation profile in the HUD shows (game default 1 km). Checked in game: at 3 km the profile shows the climbs coming up well in advance.")),
        "g_elevationProfile_Height": .init(effect: .verified, detail: L("Height of the small elevation profile in the HUD (game default 76). Checked in game: a taller profile is easier to read from the bike.")),
        "g_minPowerPauseThreshold": .init(effect: .registered, detail: L("During a workout, the game pauses it when your power stays below this value (game default 20 W). Raise it if the workout keeps running while you're soft-pedalling to grab a bottle.")),
        "g_workoutAutoPauseTime": .init(effect: .registered, detail: L("How long the power has to stay below the threshold before the workout pauses (game default 3 seconds).")),
        "ANNOUNCER_VOL": .init(effect: .registered, detail: L("Volume of the announcer's voice in events and races (game default 1, full volume). Zwift's menu has sliders for the other sounds, not for this one.")),
        "IGNOREGODMESSAGES": .init(effect: .registered, detail: L("Hides the broadcast messages Zwift sends to everyone riding (the ones from Zwift HQ).")),
        "g_enableEventHaptics": .init(effect: .registered, detail: L("Vibrations on Zwift Play and Zwift Ride for game events (power-ups, segments, …). Off keeps the other vibrations, which follow the setting in Zwift's menu.")),
        "g_cameraLookBackTime": .init(effect: .registered, detail: L("How long the camera keeps looking behind before returning to the normal view (game default 5 seconds).")),
        "g_BikeSoundDistCutoffCentemeters": .init(effect: .registered, detail: L("Beyond this distance the other riders' bikes make no sound (game default 100 m). Lower for a quieter ride in big groups.")),
        "g_phoneRiderListUpdateTime": .init(effect: .registered, detail: L("How often the list of nearby riders in the Zwift Companion app is refreshed (game default 5 seconds).")),
        "MOCHI_RESOLUTION": .init(effect: .verified, detail: L("Resolution of the video routes. Checked on the cached files: 2160p is 3840×2160 at about 120 frames per second, roughly 70 Mbit/s. A lower resolution downloads much less, which helps if the video makes your rider slow down while it buffers.")),
        "MOCHI_DOWNLOAD_FULL": .init(effect: .registered, detail: L("Downloads the whole route before the ride starts, instead of while riding: a longer wait at the start, but no slow-downs for buffering. Zwift's menu only offers it in some cases.")),
        "g_FireworkNightShowAlwaysOn": .init(effect: .registered, detail: L("Fireworks in the sky every night, not only during special events. Night follows the world's clock, which comes from Zwift's servers and can't be changed: the fireworks only show when you ride while it's night in that world.")),
    ]
}
