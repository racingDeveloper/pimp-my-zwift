// Tests for the profile writer, the log reader and the settings catalog. Run with ./test.sh
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print(ok ? "PASS" : "FAIL", name)
    if !ok { failures += 1 }
}

let ultra = "res 1920x1080(0x)\nsres 2048x2048\nset gSSAO=1\nset gFXAA=1\n"
// 1. Game default: nothing forced → profile unchanged
check("game default leaves profile untouched", ProfileFile.compose(ultra, lines: []) == ultra)
// 2. Max preset: lines appended after the original, in a stable order
let max = ConfigPlan(values: Catalog.validated(Preset.builtIn.first { $0.id == "max" }!.values))
let composed = ProfileFile.compose(ultra, lines: max.lines)
check("original kept at the top", composed.hasPrefix(ultra))
check("shadow line before tweakables", max.lines.first == "sres 4096x4096")
check("tweakables written as set", max.lines.contains("set gSSR=1") && max.lines.contains("set g_BikeMaxShadowCascade=2"))
check("ends with a newline", composed.hasSuffix("\n") && !composed.hasSuffix("\n\n"))
check("missing trailing newline handled", ProfileFile.compose("set gFXAA=1", lines: ["set gSSR=1"]) == "set gFXAA=1\nset gSSR=1\n")
// Zwift's own profiles use Windows line endings, and basic.txt has no final one
check("windows line endings kept", ProfileFile.compose("sres 2048x2048\r\nset gFXAA=1\r\n", lines: ["set gSSR=1", "set gSunRays=1"])
      == "sres 2048x2048\r\nset gFXAA=1\r\nset gSSR=1\r\nset gSunRays=1\r\n")
check("windows file without final newline", ProfileFile.compose("sres 512x512\r\nset gLODBias=1", lines: ["set gSSR=1"])
      == "sres 512x512\r\nset gLODBias=1\r\nset gSSR=1\r\n")
check("windows profile parsed", ProfileFile.values(in: "res 1920x1080(0x)\r\nsres 2048x2048\r\nset gFXAA=1\r\n") == ["sres": "2048", "gFXAA": "1"])
// 3. The original is recovered from the backup only while the file still holds what the app wrote
check("our own file → backup", ProfileFile.original(current: composed, backup: ultra, lastWritten: composed) == ultra)
let updated = "res 1920x1080(0x)\nsres 2048x2048\nset gSSAO=1\n"
check("replaced by an update → file", ProfileFile.original(current: updated, backup: ultra, lastWritten: composed) == updated)
check("no backup → file", ProfileFile.original(current: ultra, backup: nil, lastWritten: nil) == ultra)
// 4. Re-applying never stacks lines
let again = ProfileFile.compose(ProfileFile.original(current: composed, backup: ultra, lastWritten: composed), lines: max.lines)
check("idempotent", again == composed)
// 5. The render resolution goes to prefs.xml, not to the profiles (the game applies prefs.xml after them)
check("resolution kept out of profiles", max.prefs["resolution"] == "5120x2880" && !max.lines.contains { $0.hasPrefix("res ") })
let prefs = "<ZWIFT>\n    <CONFIG>\n        <MOCHI>\n            <RESOLUTION_PREF>2160p</RESOLUTION_PREF>\n        </MOCHI>\n        <USER_RESOLUTION_PREF>5120x2880(2x)</USER_RESOLUTION_PREF>\n        <INPUT_DEVICE_CUSTOM_CONFIG_MAPPING/>\n        <FULLSCREEN>1</FULLSCREEN>\n    </CONFIG>\n</ZWIFT>\n"
let res = ["CONFIG", "USER_RESOLUTION_PREF"], mochi = ["CONFIG", "MOCHI", "RESOLUTION_PREF"], vol = ["CONFIG", "ANNOUNCER_VOL"]
check("prefs value read", PrefsFile.value(in: prefs, at: res) == "5120x2880(2x)")
check("nested prefs value read", PrefsFile.value(in: prefs, at: mochi) == "2160p")
check("self-closing element reads as empty", PrefsFile.value(in: prefs, at: ["CONFIG", "INPUT_DEVICE_CUSTOM_CONFIG_MAPPING"]) == "")
check("missing element reads as nil", PrefsFile.value(in: prefs, at: vol) == nil)
let newPrefs = PrefsFile.setting(prefs, at: res, to: "4480x2520")
check("prefs value replaced, rest kept", newPrefs == prefs.replacingOccurrences(of: "5120x2880(2x)", with: "4480x2520"))
let added = PrefsFile.setting(prefs, at: vol, to: "0.5")
check("missing element added at the end of its parent, indented",
      added == prefs.replacingOccurrences(of: "        <FULLSCREEN>1</FULLSCREEN>\n", with: "        <FULLSCREEN>1</FULLSCREEN>\n        <ANNOUNCER_VOL>0.5</ANNOUNCER_VOL>\n"))
check("added element removed again, file unchanged", PrefsFile.setting(added, at: vol, to: nil) == prefs)
check("nested element replaced", PrefsFile.value(in: PrefsFile.setting(prefs, at: mochi, to: "1440p"), at: mochi) == "1440p")
check("missing parent leaves the file unchanged", PrefsFile.setting(prefs, at: ["NOPE", "X"], to: "1") == prefs)
check("original absent while ours is in place", ProfileFile.original(current: "0.5", backup: PrefsFile.absent, lastWritten: "0.5") == PrefsFile.absent)
check("menu resolution recovered while ours is in place", ProfileFile.original(current: "5120x2880", backup: "3840x2160", lastWritten: "5120x2880") == "3840x2160")
check("menu resolution changed in game wins", ProfileFile.original(current: "2560x1440", backup: "3840x2160", lastWritten: "5120x2880") == "2560x1440")
check("resolution limited to what the game accepts", Catalog.validated(["resolution": "7680x4320"]).isEmpty && Catalog.validated(["resolution": "5120x2880"]).count == 1)
// 6. Reading a profile back
let parsed = ProfileFile.values(in: ultra + "set gFoliagePercent=0.5\n")
check("profile values parsed", parsed == ["sres": "2048", "gSSAO": "1", "gFXAA": "1", "gFoliagePercent": "0.5"])
// 7. Reading Zwift's log
var snapshot = GameSnapshot()
snapshot.read(log: """
[17:30:56] Using medium graphics profile
[17:30:56] > res 1280x720(0x)
[17:48:56] GFX: Found a vendor/model match for APPLE M2 MAX
[17:48:56] Using ultra graphics profile
[17:48:56] > res 1920x1080(0x)
[17:48:56] Changed resolution to 1920 x 1080  ( NO MSAA )
[17:48:56] > set gSSAO=1
[17:48:56] > set nAIBikes=24
[17:48:56] Error: Variable "nAIBikes" not found!
[17:48:56] > set gShowFPS=1
[17:48:56] Syntax Error.  USAGE: set VARNAME=VALUE
[17:48:56] Type 'listvars' for list of tweakable variables
[17:48:56] Unknown command "listvars"
[17:48:56] > set gBloom=x
[17:48:56] Syntax Error.  USAGE: set VARNAME=VALUE
[17:48:56] > sres 8192x8192
[17:48:56] Error with resolution values (8192 x 8192)
[17:48:56] > res 3840x2160
[17:48:56] Graphics Renderer: Apple M2 Max
""")
check("last profile wins", snapshot.profileName == "ultra")
check("gpu read", snapshot.gpu == "Apple M2 Max")
check("commands of the last launch only", snapshot.lastLaunchCommands == ["res 1920x1080(0x)", "set gSSAO=1", "set nAIBikes=24", "set gShowFPS=1", "set gBloom=x", "sres 8192x8192", "res 3840x2160"])
check("rejected lines reported, syntax error of an unknown command not blamed on the previous line",
      snapshot.rejected == ["nAIBikes", "listvars", "a line with a syntax error", "sres 8192x8192"])
check("shadow resolution capped at 4096 like the game", Catalog.validated(["sres": "8192"]).isEmpty && Catalog.validated(["sres": "4096"]).count == 1)
// 8. Validation rejects out-of-range and snaps sliders
check("invalid values dropped", Catalog.validated(["sres": "3000", "gSSR": "2", "gSSAO": "1", "foo": "1"]).isEmpty)
check("negative LOD bias rejected (the game turns it into 2)", Catalog.validated(["gLODBias": "-1"]).isEmpty)
check("foliage capped at 1", Catalog.validated(["gFoliagePercent": "1.25"]).isEmpty)
check("slider snapped", Catalog.validated(["gFoliagePercent": "0.8", "gBloomStrength": "0.52"]) == ["gFoliagePercent": "0.75", "gBloomStrength": "0.50"])
check("slider out of range dropped", Catalog.validated(["gFoliagePercent": "4"]).isEmpty)
// 9. Every preset value is valid, and every tweakable has a game default
for p in Preset.builtIn { check("preset \(p.id) fully valid", Catalog.validated(p.values).count == p.values.count) }
for def in Catalog.all where def.command == .tweakable {
    check("\(def.key) default is a valid value", def.validated(Catalog.gameDefaults[def.key]) != nil)
}

// 10. Last ride report from the log
let ride = RideReport(log: """
[22:08:17] GAME_LoadLevel()  worldID = 0
[22:08:27] FPS 55.76, 12481, 13518, -489
[22:08:33] INFO LEVEL: [Route] RouteComputer route-set routeHash=3395698268 worldId=1 route=  Flat Route
[22:08:33] GAME_LoadLevel()  worldID = 1
[22:08:40] FPS 87.72, -372284, 48932, 19
[22:08:48] FPS 77.12, 100025,  9533, -24
[22:08:56] FPS 60.00, 99798,  9513, -246
[22:09:04] FPS 70.00, 103499,  9462, -14
[22:09:09] Changed resolution to 5120 x 2880
[22:09:10] Changed shadow resolution to 4096 x 4096
[22:09:45] INFO LEVEL: [GameState] ZSF_RIDE -> ZSF_DROPIN_SCREEN
[22:09:57] FPS 62.11, -372284, 48932, 19
""".split(separator: "\n").map(String.init))
check("ride found", ride != nil)
check("ride route", ride?.route == "Flat Route")
check("ride samples skip loading and menus", ride?.fps == [77.12, 60.00, 70.00])
check("ride fps stats", ride?.fpsMin == 60 && ride?.fpsMax == 77.12 && ride?.fpsMedian == 70)
check("ride applied sizes", ride?.resolution == "5120x2880" && ride?.shadows == "4096")
check("ride minutes", ride?.minutes == 0)
check("no ride without a world", RideReport(log: ["[22:08:17] GAME_LoadLevel()  worldID = 0"]) == nil)

exit(failures == 0 ? 0 : 1)
