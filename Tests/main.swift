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
let max = ConfigPlan(values: Catalog.validated(Preset.builtIn.first { $0.id == "max" }!.values), resolution: "3840x2160")
let composed = ProfileFile.compose(ultra, lines: max.lines)
check("original kept at the top", composed.hasPrefix(ultra))
check("shadow line before tweakables", max.lines.first == "sres 4096x4096")
check("tweakables written as set", max.lines.contains("set gSSR=1") && max.lines.contains("set gRadialBlur=0"))
check("ends with a newline", composed.hasSuffix("\n") && !composed.hasSuffix("\n\n"))
check("missing trailing newline handled", ProfileFile.compose("set gFXAA=1", lines: ["set gSSR=1"]) == "set gFXAA=1\nset gSSR=1\n")
// 3. The original is recovered from the backup only while the file still holds what the app wrote
check("our own file → backup", ProfileFile.original(current: composed, backup: ultra, lastWritten: composed) == ultra)
let updated = "res 1920x1080(0x)\nsres 2048x2048\nset gSSAO=1\n"
check("replaced by an update → file", ProfileFile.original(current: updated, backup: ultra, lastWritten: composed) == updated)
check("no backup → file", ProfileFile.original(current: ultra, backup: nil, lastWritten: nil) == ultra)
// 4. Re-applying never stacks lines
let again = ProfileFile.compose(ProfileFile.original(current: composed, backup: ultra, lastWritten: composed), lines: max.lines)
check("idempotent", again == composed)
// 5. MSAA needs the menu's resolution
check("msaa uses the menu resolution", ConfigPlan(values: ["msaa": "4"], resolution: "3840x2160").lines == ["res 3840x2160(4x)"])
let noRes = ConfigPlan(values: ["msaa": "4", "gSSR": "1"], resolution: nil)
check("msaa skipped without resolution", noRes.lines == ["set gSSR=1"] && noRes.skipped == ["msaa"])
// 6. Reading a profile back
let parsed = ProfileFile.values(in: ultra + "set gFoliagePercent=0.5\n")
check("profile values parsed", parsed == ["msaa": "0", "sres": "2048", "gSSAO": "1", "gFXAA": "1", "gFoliagePercent": "0.5"])
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
[17:48:56] Graphics Renderer: Apple M2 Max
""")
check("last profile wins", snapshot.profileName == "ultra")
check("gpu read", snapshot.gpu == "Apple M2 Max")
check("commands of the last launch only", snapshot.lastLaunchCommands == ["res 1920x1080(0x)", "set gSSAO=1", "set nAIBikes=24"])
check("unknown variables reported", snapshot.unknownVariables == ["nAIBikes"])
// 8. Validation rejects out-of-range and snaps sliders
check("invalid values dropped", Catalog.validated(["sres": "3000", "gSSAO": "2", "foo": "1"]).isEmpty)
check("slider snapped", Catalog.validated(["gFoliagePercent": "0.8", "gBloomStrength": "0.52"]) == ["gFoliagePercent": "0.75", "gBloomStrength": "0.50"])
check("slider out of range dropped", Catalog.validated(["gFoliagePercent": "4"]).isEmpty)
// 9. Every preset value is valid, and every tweakable has a game default
for p in Preset.builtIn { check("preset \(p.id) fully valid", Catalog.validated(p.values).count == p.values.count) }
for def in Catalog.all where def.command == .tweakable {
    check("\(def.key) default is a valid value", def.validated(Catalog.gameDefaults[def.key]) != nil)
}

exit(failures == 0 ? 0 : 1)
