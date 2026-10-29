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
check("resolution kept out of profiles", max.resolution == "5120x2880" && !max.lines.contains { $0.hasPrefix("res ") })
let prefs = "<ZWIFT>\n    <CONFIG>\n        <USER_RESOLUTION_PREF>5120x2880(2x)</USER_RESOLUTION_PREF>\n        <FULLSCREEN>1</FULLSCREEN>\n    </CONFIG>\n</ZWIFT>\n"
check("prefs resolution read", PrefsFile.resolution(in: prefs) == "5120x2880(2x)")
let newPrefs = PrefsFile.settingResolution(prefs, to: "4480x2520")
check("prefs resolution replaced, rest kept", PrefsFile.resolution(in: newPrefs) == "4480x2520"
      && newPrefs == prefs.replacingOccurrences(of: "5120x2880(2x)", with: "4480x2520"))
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

exit(failures == 0 ? 0 : 1)
