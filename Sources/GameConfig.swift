import AppKit
import Foundation

enum GamePaths {
    static let launcherBundleID = "com.zwift.ZwiftLauncher"
    static let gameBundleID = "com.zwift.zwiftgame"

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    /// Where the launcher installs the game, its assets and the graphics profiles.
    static let installDir = home.appendingPathComponent("Library/Application Support/Zwift", isDirectory: true)
    static let configsDir = installDir.appendingPathComponent("data/configs", isDirectory: true)
    /// The game's preferences and logs.
    static let documentsDir = home.appendingPathComponent("Documents/Zwift", isDirectory: true)
    static let prefs = documentsDir.appendingPathComponent("prefs.xml")
    static let gameLog = documentsDir.appendingPathComponent("Logs/Log.txt")
    /// Downloaded video routes (Mochi): raw video segments, previews and route data, one file per hash.
    static let videoCache = home.appendingPathComponent("Library/Caches/Zwift/mochi", isDirectory: true)
    static let log = home.appendingPathComponent("Library/Logs/PimpMyZwift.log")

    static func profile(_ name: String) -> URL {
        configsDir.appendingPathComponent("\(name).txt")
    }

    static func backup(_ name: String) -> URL {
        profile(name).appendingPathExtension("pimpmyzwift.bak")
    }

    static var gameApp: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: launcherBundleID)
            ?? existing(URL(fileURLWithPath: "/Applications/Zwift.app"))
    }

    private static func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// Zwift's graphics profiles: plain text files of console commands (`res`, `sres`, `set NAME=VALUE`), one per line.
enum ProfileFile {
    /// The profiles Zwift picks from based on the GPU. The app writes all of them, so the result doesn't depend on which one is chosen.
    static let names = ["basic", "medium", "high", "ultra"]

    /// The original profile followed by the app's lines: later lines win, so ours override the game's.
    static func compose(_ original: String, lines: [String]) -> String {
        guard !lines.isEmpty else { return original }
        // Zwift ships its profiles with Windows line endings: the app's lines use the same ones as the file.
        let newline = original.contains("\r\n") ? "\r\n" : "\n"
        var out = original
        // "\r\n" is a single Character in Swift, so this also drops Windows line endings.
        while out.last?.isNewline == true { out.removeLast() }
        if !out.isEmpty { out += newline }
        return out + lines.joined(separator: newline) + newline
    }

    /// The pristine profile: the backup if the file still holds what the app wrote last,
    /// otherwise the file itself (first run, or a game update replaced it).
    static func original(current: String, backup: String?, lastWritten: String?) -> String {
        if let backup, current == lastWritten { return backup }
        return current
    }

    /// Values a profile sets, keyed like the catalog (`sres` and tweakable names).
    static func values(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("set ") {
                let parts = line.dropFirst(4).split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { result[parts[0]] = parts[1] }
            } else if line.hasPrefix("sres ") {
                result["sres"] = line.dropFirst(5).split(separator: "x").first.map(String.init)
            }
        }
        return result
    }
}

/// Zwift's prefs.xml: only the elements the app manages are touched, the rest of the file is left as it is.
/// Paths start below the root element, e.g. ["CONFIG", "MOCHI", "RESOLUTION_PREF"].
enum PrefsFile {
    /// Stands for "the element doesn't exist" where a string is needed (original values, last written values).
    static let absent = "\u{1}absent"

    /// Text of the element at `path`, nil when it's missing.
    static func value(in text: String, at path: [String]) -> String? {
        guard let parent = parentRange(in: text, for: path), let element = elementRange(in: text, within: parent, name: path.last!) else { return nil }
        let raw = text[element]
        guard let open = raw.firstIndex(of: ">"), !raw[..<open].hasSuffix("/") else { return "" }
        let afterOpen = raw.index(after: open)
        guard let close = raw.range(of: "</", range: afterOpen..<raw.endIndex) else { return "" }
        return String(raw[afterOpen..<close.lowerBound])
    }

    /// Sets the element at `path`, adding it at the end of its parent when missing; nil removes it.
    /// A missing parent leaves the file unchanged.
    static func setting(_ text: String, at path: [String], to value: String?) -> String {
        guard let parent = parentRange(in: text, for: path) else { return text }
        let name = path.last!
        var out = text
        if let element = elementRange(in: text, within: parent, name: name) {
            if let value {
                out.replaceSubrange(element, with: "<\(name)>\(value)</\(name)>")
            } else {
                // Remove the whole line, indentation and newline included.
                let lineStart = text[..<element.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? element.lowerBound
                let onlySpaces = text[lineStart..<element.lowerBound].allSatisfy { $0 == " " || $0 == "\t" }
                var end = element.upperBound
                if onlySpaces, end < text.endIndex, text[end] == "\n" { end = text.index(after: end) }
                out.removeSubrange((onlySpaces ? lineStart : element.lowerBound)..<end)
            }
        } else if let value {
            // Insert before the parent's closing tag, one indentation level deeper than it.
            let closing = parent.upperBound
            let lineStart = text[..<closing].lastIndex(of: "\n").map { text.index(after: $0) } ?? closing
            let indent = String(text[lineStart..<closing].prefix { $0 == " " || $0 == "\t" })
            let line = indent + "    <\(name)>\(value)</\(name)>\n"
            out.insert(contentsOf: lineStart == closing ? "\n" + line + indent : line, at: lineStart == closing ? closing : lineStart)
        }
        return out
    }

    /// Range of the parent element's content (between its tags), for the path's last component.
    private static func parentRange(in text: String, for path: [String]) -> Range<String.Index>? {
        var range = text.startIndex..<text.endIndex
        for name in path.dropLast() {
            guard let open = text.range(of: "<\(name)>", range: range),
                  let close = text.range(of: "</\(name)>", range: open.upperBound..<range.upperBound) else { return nil }
            range = open.upperBound..<close.lowerBound
        }
        return range
    }

    /// Range of a whole `<NAME>…</NAME>` or `<NAME/>` element inside `range`.
    private static func elementRange(in text: String, within range: Range<String.Index>, name: String) -> Range<String.Index>? {
        if let selfClosing = text.range(of: "<\(name)/>", range: range) { return selfClosing }
        guard let open = text.range(of: "<\(name)>", range: range),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<range.upperBound) else { return nil }
        return open.lowerBound..<close.upperBound
    }
}

struct ConfigPlan {
    var lines: [String] = []
    /// prefs.xml values forced by the app, keyed by setting; the settings left out get their original value back.
    var prefs: [String: String] = [:]

    init(values: [String: String]) {
        // Commands first, then tweakables, in catalog order: stable output, easy to compare.
        let ordered = Catalog.all.filter { $0.command != .tweakable } + Catalog.all.filter { $0.command == .tweakable }
        for def in ordered {
            guard let value = values[def.key] else { continue }
            if def.prefsPath != nil {
                prefs[def.key] = value
            } else if let line = def.line(for: value) {
                lines.append(line)
            }
        }
    }

    var preview: String {
        guard !lines.isEmpty || !prefs.isEmpty else {
            return L("No changes: Zwift's profiles and preferences are restored, and the game decides.")
        }
        var parts: [String] = []
        let prefsLines = Catalog.all.compactMap { def in
            def.prefsPath.flatMap { path in prefs[def.key].map { "\(path.joined(separator: "\\")) = \($0)" } }
        }
        if !prefsLines.isEmpty {
            parts.append("# prefs.xml\n" + prefsLines.joined(separator: "\n"))
        }
        if !lines.isEmpty {
            let files = ProfileFile.names.map { "\($0).txt" }.joined(separator: ", ")
            parts.append("# " + L("Appended to \(files)") + "\n" + lines.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

/// What the game decided on its own, read from its files and its log (read-only).
struct GameSnapshot {
    var version: String?
    /// Profile Zwift picked at its last launch ("ultra", …), from Log.txt.
    var profileName: String?
    var gpu: String?
    /// prefs.xml values as the game left them (without this app's values), keyed by setting; missing elements are left out.
    var prefsValues: [String: String] = [:]
    /// Resolution chosen in the game's menu (e.g. "3840x2160").
    var menuResolution: String? { prefsValues["resolution"] }
    /// The last ride in Zwift's log: route, length, frame rate.
    var lastRide: RideReport?
    /// Values the chosen profile sets on its own, before this app's lines.
    var profileValues: [String: String] = [:]
    /// Console commands Zwift ran from the profile at its last launch.
    var lastLaunchCommands: [String] = []
    /// Profile lines the game refused at its last launch (unknown variables or commands, syntax errors).
    var rejected: [String] = []

    static func load() -> GameSnapshot {
        var snapshot = GameSnapshot()
        if let log = try? String(contentsOf: GamePaths.gameLog, encoding: .utf8) {
            snapshot.read(log: log)
        }
        for def in Catalog.all {
            if let path = def.prefsPath, let value = ConfigWriter.originalPrefsValue(at: path) { snapshot.prefsValues[def.key] = value }
        }
        if let pointer = try? String(contentsOf: GamePaths.installDir.appendingPathComponent("Zwift_ver_cur_filename.txt"), encoding: .utf8),
           let verCur = try? String(contentsOf: GamePaths.installDir.appendingPathComponent(pointer.trimmingCharacters(in: .whitespacesAndNewlines)), encoding: .utf8) {
            snapshot.version = verCur.firstMatch(of: #/sversion="([^"]+)"/#).map { String($0.1) }
        }
        let name = snapshot.profileName ?? "ultra"
        if let original = ConfigWriter.original(of: name) {
            snapshot.profileValues = ProfileFile.values(in: original)
        }
        return snapshot
    }

    /// Reads the last launch from Zwift's Log.txt: the profile it picked and what it applied.
    mutating func read(log: String) {
        let lines = log.split(whereSeparator: \.isNewline).map(String.init)
        guard let start = lines.lastIndex(where: { $0.contains("graphics profile") }) else { return }
        profileName = lines[start].firstMatch(of: #/Using (\w+) graphics profile/#).map { String($0.1) }
        gpu = lines.last { $0.contains("Graphics Renderer:") }?
            .components(separatedBy: "Graphics Renderer:").last?.trimmingCharacters(in: .whitespaces)
        lastLaunchCommands = []
        rejected = []
        // A line that isn't a known command is first tried as `set` (a syntax error), then reported as an unknown
        // command without being echoed: the syntax error belongs to that line, not to the previous `> …` one.
        var syntaxError = false
        func flushSyntaxError() {
            if syntaxError { rejected.append(L("a line with a syntax error")) }
            syntaxError = false
        }
        for line in lines[(start + 1)...].prefix(200) {
            if let command = line.firstMatch(of: #/\] > (.+)$/#) {
                flushSyntaxError()
                lastLaunchCommands.append(String(command.1))
            } else if let unknown = line.firstMatch(of: #/Unknown command "([^"]+)"/#) {
                syntaxError = false
                rejected.append(String(unknown.1))
            } else if let unknown = line.firstMatch(of: #/Variable "([^"]+)" not found/#) {
                rejected.append(String(unknown.1))
            } else if let failed = line.firstMatch(of: #/Error setting ([^.]+)\./#) {
                rejected.append(String(failed.1))
            } else if line.contains("Error with resolution values"), let last = lastLaunchCommands.last {
                rejected.append(last)
            } else if line.contains("Syntax Error") {
                syntaxError = true
            }
        }
        flushSyntaxError()
        lastRide = RideReport(log: lines[start...])
    }

    /// Describes the value the game uses when the app doesn't force `def`.
    func describe(_ def: SettingDef) -> String {
        if def.key == "resolution" {
            return menuResolution.map { L("game menu: \(def.label(for: $0))") } ?? L("game menu: not saved yet")
        }
        if def.prefsPath != nil, let value = prefsValues[def.key] {
            return L("game: \(def.label(for: value))")
        }
        if let value = profileValues[def.key] {
            return L("profile \(profileName ?? "ultra"): \(def.label(for: value))")
        }
        if let value = Catalog.gameDefaults[def.key] {
            return L("game default: \(def.label(for: value))")
        }
        return L("decided by the game")
    }
}

/// The last ride in Zwift's log. The game logs its frame rate about every 8 seconds.
struct RideReport {
    var route: String?
    var minutes: Int?
    /// Frame rate samples while riding (the first one after a world loads is skipped: it covers the loading).
    var fps: [Double] = []
    /// What the game actually applied, from its own messages.
    var resolution: String?
    var shadows: String?

    var fpsMin: Double? { fps.min() }
    var fpsMax: Double? { fps.max() }
    var fpsMedian: Double? {
        guard !fps.isEmpty else { return nil }
        let sorted = fps.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    init?<Lines: Sequence>(log lines: Lines) where Lines.Element == String {
        var riding = false, skipNext = false
        var rideStart: Int?, rideEnd: Int?
        func seconds(_ line: String) -> Int? {
            line.firstMatch(of: #/^\[(\d+):(\d+):(\d+)\]/#).map { Int($0.1)! * 3600 + Int($0.2)! * 60 + Int($0.3)! }
        }
        for line in lines {
            if let world = line.firstMatch(of: #/GAME_LoadLevel\(\)\s+worldID = (\d+)/#) {
                riding = Int(world.1)! > 0
                skipNext = true
                if riding, rideStart == nil { rideStart = seconds(line) }
            } else if line.contains("-> ZSF_DROPIN_SCREEN") {
                riding = false
            } else if let name = line.firstMatch(of: #/route=\s*(.+)$/#) {
                route = name.1.trimmingCharacters(in: .whitespaces)
            } else if let sample = line.firstMatch(of: #/\] FPS ([0-9.]+),/#), riding {
                if skipNext { skipNext = false; continue }
                fps.append(Double(sample.1)!)
                rideEnd = seconds(line)
            } else if let size = line.firstMatch(of: #/Changed resolution to (\d+) x (\d+)/#) {
                resolution = "\(size.1)x\(size.2)"
            } else if let size = line.firstMatch(of: #/Changed shadow resolution to (\d+) x/#) {
                shadows = String(size.1)
            }
        }
        guard rideStart != nil else { return nil }
        if let rideStart, let rideEnd {
            // Rides past midnight wrap the clock.
            minutes = ((rideEnd - rideStart + 86_400) % 86_400) / 60
        }
    }
}

enum ConfigError: LocalizedError {
    case gameNotInstalled
    case io(String)

    var errorDescription: String? {
        switch self {
        case .gameNotInstalled:
            return L("Zwift's graphics profiles weren't found in ~/Library/Application Support/Zwift: install Zwift and launch it at least once.")
        case .io(let message):
            return message
        }
    }
}

enum ConfigWriter {
    private static func lastWrittenKey(_ name: String) -> String { "lastWritten.\(name)" }
    /// prefs.xml values before the app changed them, and the ones it wrote last, keyed by path ("CONFIG\\VSYNC").
    private static let originalPrefsKey = "originalPrefs", lastWrittenPrefsKey = "lastWrittenPrefs"

    static func checkAccess() -> ConfigError? {
        let fm = FileManager.default
        let present = ProfileFile.names.filter { fm.fileExists(atPath: GamePaths.profile($0).path) }
        guard !present.isEmpty else { return .gameNotInstalled }
        for name in present {
            do { try FileHandle(forUpdating: GamePaths.profile(name)).close() } catch {
                return .io(L("Couldn't open \(name).txt for writing: \(error.localizedDescription)"))
            }
        }
        return nil
    }

    /// The profile as Zwift ships it, without this app's lines.
    static func original(of name: String) -> String? {
        guard let current = try? String(contentsOf: GamePaths.profile(name), encoding: .utf8) else { return nil }
        let backup = try? String(contentsOf: GamePaths.backup(name), encoding: .utf8)
        return ProfileFile.original(current: current, backup: backup,
                                    lastWritten: UserDefaults.standard.string(forKey: lastWrittenKey(name)))
    }

    static func apply(_ plan: ConfigPlan) throws {
        if let problem = checkAccess() { throw problem }
        for name in ProfileFile.names {
            guard let current = try? String(contentsOf: GamePaths.profile(name), encoding: .utf8),
                  let original = original(of: name) else { continue }
            do {
                if plan.lines.isEmpty {
                    if current != original { try write(original, to: GamePaths.profile(name)) }
                    try? FileManager.default.removeItem(at: GamePaths.backup(name))
                    UserDefaults.standard.removeObject(forKey: lastWrittenKey(name))
                } else {
                    let updated = ProfileFile.compose(original, lines: plan.lines)
                    try write(original, to: GamePaths.backup(name))
                    if updated != current { try write(updated, to: GamePaths.profile(name)) }
                    UserDefaults.standard.set(updated, forKey: lastWrittenKey(name))
                }
            } catch {
                throw ConfigError.io(L("Couldn't write \(name).txt: \(error.localizedDescription)"))
            }
        }
        try applyPrefs(plan.prefs)
        Log.write("Applied \(plan.lines.count) lines to \(ProfileFile.names.count) profiles and \(plan.prefs.count) preferences")
    }

    private static var originalPrefs: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: originalPrefsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: originalPrefsKey) }
    }

    private static var lastWrittenPrefs: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: lastWrittenPrefsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: lastWrittenPrefsKey) }
    }

    /// Version 0.1 only managed the resolution, with its own keys.
    private static func migrateResolutionKeys() {
        let defaults = UserDefaults.standard
        guard let original = defaults.string(forKey: "originalResolution") else { return }
        let id = "CONFIG\\USER_RESOLUTION_PREF"
        originalPrefs[id] = original
        if let last = defaults.string(forKey: "lastWritten.resolution") { lastWrittenPrefs[id] = last }
        defaults.removeObject(forKey: "originalResolution")
        defaults.removeObject(forKey: "lastWritten.resolution")
    }

    /// The value the game itself saved at `path` (nil when it saved none): the one from before this app changed it,
    /// unless the game has saved a new one since (for example a resolution picked in its menu).
    static func originalPrefsValue(at path: [String], in text: String? = nil) -> String? {
        migrateResolutionKeys()
        guard let text = text ?? (try? String(contentsOf: GamePaths.prefs, encoding: .utf8)) else { return nil }
        let id = path.joined(separator: "\\")
        let current = PrefsFile.value(in: text, at: path) ?? PrefsFile.absent
        let original = ProfileFile.original(current: current, backup: originalPrefs[id], lastWritten: lastWrittenPrefs[id])
        return original == PrefsFile.absent ? nil : original
    }

    private static func applyPrefs(_ forced: [String: String]) throws {
        migrateResolutionKeys()
        let managed = Catalog.all.compactMap { def in def.prefsPath.map { (def.key, $0) } }
        guard let text = try? String(contentsOf: GamePaths.prefs, encoding: .utf8) else {
            if !forced.isEmpty { throw ConfigError.io(L("Zwift's prefs.xml wasn't found: launch Zwift at least once.")) }
            return
        }
        var updated = text
        var originals = originalPrefs, lastWritten = lastWrittenPrefs
        for (key, path) in managed {
            let id = path.joined(separator: "\\")
            let original = originalPrefsValue(at: path, in: text)
            if let value = forced[key] {
                updated = PrefsFile.setting(updated, at: path, to: value)
                originals[id] = original ?? PrefsFile.absent
                lastWritten[id] = PrefsFile.value(in: updated, at: path) ?? PrefsFile.absent
            } else {
                // Only touch the element when it differs, so the game's own formatting (e.g. `<KEY/>`) is kept.
                if PrefsFile.value(in: updated, at: path) != original {
                    updated = PrefsFile.setting(updated, at: path, to: original)
                }
                originals[id] = nil
                lastWritten[id] = nil
            }
        }
        if updated != text {
            let backup = GamePaths.prefs.appendingPathExtension("pimpmyzwift.bak")
            do {
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.copyItem(at: GamePaths.prefs, to: backup)
                }
                try write(updated, to: GamePaths.prefs)
            } catch {
                throw ConfigError.io(L("Couldn't write prefs.xml: \(error.localizedDescription)"))
            }
        }
        originalPrefs = originals
        lastWrittenPrefs = lastWritten
    }

    private static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// The video routes' download cache. Zwift downloads what's missing again the next time a route is ridden.
enum VideoCache {
    /// Bytes on disk, nil when the folder doesn't exist.
    static func size() -> Int64? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: GamePaths.videoCache.path),
              let files = fm.enumerator(at: GamePaths.videoCache, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// Deletes the cache's contents, leaving the folder in place.
    static func clear() throws {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: GamePaths.videoCache, includingPropertiesForKeys: nil)) ?? [] {
            try fm.removeItem(at: item)
        }
        Log.write("Cleared the video cache")
    }
}

enum GameLauncher {
    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            [GamePaths.launcherBundleID, GamePaths.gameBundleID].contains(app.bundleIdentifier ?? "")
                || app.executableURL?.lastPathComponent.hasPrefix("ZwiftApp") == true
        }
    }

    static func launch() async throws {
        guard let app = GamePaths.gameApp else {
            throw ConfigError.io(L("Zwift isn't installed in /Applications."))
        }
        try await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        Log.write("Launched \(app.lastPathComponent)")
    }
}

enum Log {
    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: GamePaths.log) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: GamePaths.log)
        }
    }
}
