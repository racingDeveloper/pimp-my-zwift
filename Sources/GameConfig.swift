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
        var out = original
        while out.hasSuffix("\n") { out.removeLast() }
        if !out.isEmpty { out += "\n" }
        return out + lines.joined(separator: "\n") + "\n"
    }

    /// The pristine profile: the backup if the file still holds what the app wrote last,
    /// otherwise the file itself (first run, or a game update replaced it).
    static func original(current: String, backup: String?, lastWritten: String?) -> String {
        if let backup, current == lastWritten { return backup }
        return current
    }

    /// Values a profile sets, keyed like the catalog (`sres`, `msaa` and tweakable names).
    static func values(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("set ") {
                let parts = line.dropFirst(4).split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { result[parts[0]] = parts[1] }
            } else if line.hasPrefix("sres ") {
                result["sres"] = line.dropFirst(5).split(separator: "x").first.map(String.init)
            } else if line.hasPrefix("res "), let open = line.firstIndex(of: "("), let close = line.firstIndex(of: "x", after: open) {
                result["msaa"] = String(line[line.index(after: open)..<close])
            }
        }
        return result
    }
}

private extension String {
    func firstIndex(of character: Character, after index: Index) -> Index? {
        self[self.index(after: index)...].firstIndex(of: character)
    }
}

struct ConfigPlan {
    var lines: [String] = []
    /// Settings that couldn't be written (MSAA without a known resolution).
    var skipped: [String] = []

    init(values: [String: String], resolution: String?) {
        // Commands first, then tweakables, in catalog order: stable output, easy to compare.
        let ordered = Catalog.all.filter { $0.command != .tweakable } + Catalog.all.filter { $0.command == .tweakable }
        for def in ordered {
            guard let value = values[def.key] else { continue }
            if let line = def.line(for: value, resolution: resolution) {
                lines.append(line)
            } else {
                skipped.append(def.key)
            }
        }
    }

    var preview: String {
        guard !lines.isEmpty else { return L("No changes: Zwift's profiles are restored and the game decides.") }
        let files = ProfileFile.names.map { "\($0).txt" }.joined(separator: ", ")
        return "# " + L("Appended to \(files)") + "\n" + lines.joined(separator: "\n")
    }
}

/// What the game decided on its own, read from its files and its log (read-only).
struct GameSnapshot {
    var version: String?
    /// Profile Zwift picked at its last launch ("ultra", …), from Log.txt.
    var profileName: String?
    var gpu: String?
    /// Resolution chosen in the game's menu, from prefs.xml (e.g. "3840x2160").
    var resolution: String?
    /// Values the chosen profile sets on its own, before this app's lines.
    var profileValues: [String: String] = [:]
    /// Console commands Zwift ran from the profile at its last launch.
    var lastLaunchCommands: [String] = []
    /// Variables the game reported as unknown at its last launch.
    var unknownVariables: [String] = []

    static func load() -> GameSnapshot {
        var snapshot = GameSnapshot()
        if let log = try? String(contentsOf: GamePaths.gameLog, encoding: .utf8) {
            snapshot.read(log: log)
        }
        if let prefs = try? String(contentsOf: GamePaths.prefs, encoding: .utf8) {
            snapshot.resolution = prefs.firstMatch(of: #/<USER_RESOLUTION_PREF>(\d+x\d+)</#).map { String($0.1) }
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
        unknownVariables = []
        for line in lines[(start + 1)...].prefix(200) {
            if let command = line.firstMatch(of: #/\] > (.+)$/#) {
                lastLaunchCommands.append(String(command.1))
            } else if let unknown = line.firstMatch(of: #/Variable "([^"]+)" not found/#) {
                unknownVariables.append(String(unknown.1))
            }
        }
    }

    /// Describes the value the game uses when the app doesn't force `def`.
    func describe(_ def: SettingDef) -> String {
        if let value = profileValues[def.key] {
            return L("profile \(profileName ?? "ultra"): \(def.label(for: value))")
        }
        if let value = Catalog.gameDefaults[def.key] {
            return L("game default: \(def.label(for: value))")
        }
        return L("decided by the game")
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
        Log.write("Applied \(plan.lines.count) lines to \(ProfileFile.names.count) profiles")
    }

    private static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
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
