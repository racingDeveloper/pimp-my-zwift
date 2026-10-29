import SwiftUI

// No @State in this file: with only the Command Line Tools the SwiftUIMacros plugin is missing; state lives in AppState.

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if let notice = state.notice { NoticeBar(notice: notice) }
                detail
            }
        }
        .searchable(text: $state.search, placement: .sidebar, prompt: "Search settings")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Save") { state.applyOnly() }
                    .help("Writes the settings without launching the game")
                Button {
                    state.launch()
                } label: {
                    Label("Launch Zwift", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.busy)
                .help("Writes the settings and launches Zwift (⌘R)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refresh()
        }
    }

    @ViewBuilder private var detail: some View {
        if !state.search.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsPane()
        } else {
            switch state.pane ?? .overview {
            case .overview: OverviewPane()
            case .section(let section): SectionPane(section: section)
            case .preview: PreviewPane()
            }
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: $state.pane) {
            Label("Overview", systemImage: "gauge.with.dots.needle.67percent")
                .tag(Pane.overview)
            Section("Settings") {
                ForEach(SettingSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(state.forcedCount(in: section))
                        .tag(Pane.section(section))
                }
            }
            Section {
                Label("Profile preview", systemImage: "doc.text")
                    .tag(Pane.preview)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { status }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if state.accessProblem != nil {
                Label("Profiles not found", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Label("Profiles found", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            Label(state.gameRunning ? L("Zwift running") : L("Zwift closed"),
                  systemImage: state.gameRunning ? "circle.fill" : "circle")
                .foregroundStyle(state.gameRunning ? .green : .secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Overview

struct OverviewPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            if let problem = state.accessProblem { AccessSection(problem: problem) }

            Section {
                ForEach(Preset.builtIn) { preset in
                    PresetRow(preset: preset, selected: state.presetID == preset.id) {
                        state.apply(preset)
                    }
                }
                if state.presetID == Preset.customID {
                    PresetRow(preset: .custom, selected: true) {}
                }
            } header: {
                Text("Preset")
            } footer: {
                Text("A preset fills in every section; you can then fine-tune individual settings.")
                    .foregroundStyle(.secondary)
            }

            Section("What will be applied") {
                LabeledContent("Shadow resolution", value: state.values["sres"].map { "\($0)×\($0)" } ?? L("game decides"))
                LabeledContent("MSAA", value: msaaSummary)
                LabeledContent("Forced values", value: L("\(String(state.values.count)) of \(String(Catalog.all.count))"))
            }

            LastLaunchSection(snapshot: state.snapshot)

            Section {
                Toggle("Quit Pimp My Zwift after launching", isOn: $state.quitAfterLaunch)
            } header: {
                Text("Launch")
            } footer: {
                Text("The settings are appended to all of Zwift's graphics profiles, so they apply whichever one the game picks. A .pimpmyzwift.bak copy of each original profile is kept, and \"Game default\" restores it. A Zwift update can replace the profiles: launching from here writes them again.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Overview")
    }

    private var msaaSummary: String {
        guard let samples = state.values["msaa"] else { return L("game decides") }
        if samples == "0" { return L("Off") }
        guard let resolution = state.snapshot.resolution else { return L("not written: resolution unknown") }
        return L("\(samples)× at \(resolution)")
    }
}

private struct LastLaunchSection: View {
    let snapshot: GameSnapshot

    var body: some View {
        Section {
            LabeledContent("Zwift version", value: snapshot.version ?? L("unknown"))
            LabeledContent("GPU", value: snapshot.gpu ?? L("unknown"))
            LabeledContent("Profile in use", value: snapshot.profileName ?? L("unknown"))
            LabeledContent("Resolution (game menu)", value: snapshot.resolution ?? L("unknown"))
            if !snapshot.unknownVariables.isEmpty {
                Label {
                    Text("Zwift didn't recognize: \(snapshot.unknownVariables.joined(separator: ", "))")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            if !snapshot.lastLaunchCommands.isEmpty {
                DisclosureGroup("Commands applied at the last launch (\(String(snapshot.lastLaunchCommands.count)))") {
                    Text(snapshot.lastLaunchCommands.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } header: {
            Text("Your Zwift")
        } footer: {
            Text("Read from Zwift's log and prefs.xml. Launch the game once after saving to check that every line was applied.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PresetRow: View {
    let preset: Preset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).fontWeight(selected ? .semibold : .regular)
                    Text(preset.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AccessSection: View {
    let problem: ConfigError

    var body: some View {
        Section {
            Label {
                Text(problem.localizedDescription)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Sections

struct SectionPane: View {
    @EnvironmentObject private var state: AppState
    let section: SettingSection

    var body: some View {
        Form {
            if let note = section.note {
                Section {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(Catalog.all.filter { $0.section == section }) { def in
                    SettingRow(def: def)
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Force nothing in this section") { state.resetSection(section) }
                        .disabled(state.forcedCount(in: section) == 0)
                        .help("Let the game decide every setting in this section")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(section.title)
    }
}

struct SearchResultsPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            let results = state.searchResults
            if results.isEmpty {
                Text("No settings match “\(state.search)”.").foregroundStyle(.secondary)
            }
            ForEach(SettingSection.allCases) { section in
                let matches = results.filter { $0.section == section }
                if !matches.isEmpty {
                    Section(section.title) {
                        ForEach(matches) { SettingRow(def: $0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Search")
    }
}

struct SettingRow: View {
    @EnvironmentObject private var state: AppState
    let def: SettingDef

    private var value: Binding<String?> { state.binding(for: def) }
    private var info: SettingInfo { Catalog.info(for: def.key) }
    private var isForced: Bool { state.values[def.key] != nil }

    var body: some View {
        LabeledContent {
            control
        } label: {
            HStack(spacing: 6) {
                Text(def.title)
                if info.effect != .verified {
                    Image(systemName: info.effect.symbol)
                        .foregroundStyle(info.effect.color)
                        .help(info.effect.label)
                        .accessibilityLabel(info.effect.label)
                }
                infoButton
            }
            Text(state.gameValue(for: def))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Fixed-width control column, so pickers and sliders line up across rows.
    static let controlWidth: CGFloat = 290

    private var infoButton: some View {
        Button {
            state.infoKey = def.key
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("What it does")
        .accessibilityLabel("About \(def.title)")
        .popover(isPresented: Binding(
            get: { state.infoKey == def.key },
            set: { if !$0 && state.infoKey == def.key { state.infoKey = nil } }),
                 arrowEdge: .trailing) {
            InfoPopover(def: def, info: info, gameValue: state.gameValue(for: def))
        }
    }

    @ViewBuilder private var control: some View {
        switch def.control {
        case .choice(let options):
            Picker(def.title, selection: value) {
                Text("Don't force").tag(String?.none)
                Divider()
                ForEach(options, id: \.value) { Text($0.label).tag(Optional($0.value)) }
            }
            .labelsHidden()
            .fixedSize()
            .frame(width: Self.controlWidth, alignment: .trailing)
        case .slider(let min, let max, let step, let decimals, let unit):
            HStack(spacing: 10) {
                Toggle("Force", isOn: Binding(
                    get: { isForced },
                    set: { value.wrappedValue = $0 ? SettingDef.format(neutral(min, max), decimals: decimals) : nil }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(isForced ? L("Back to the game's value") : L("Force a value"))
                Slider(value: Binding(
                    get: { value.wrappedValue.flatMap(Double.init) ?? neutral(min, max) },
                    set: { value.wrappedValue = SettingDef.format($0, decimals: decimals) }),
                       in: min...max, step: step)
                    .frame(width: 150)
                    .disabled(!isForced)
                Text(value.wrappedValue.map { "\($0)\(unit)" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(isForced ? .primary : .secondary)
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(width: Self.controlWidth, alignment: .trailing)
        }
    }

    /// Starting point when a slider is enabled: the game's own default when within range.
    private func neutral(_ min: Double, _ max: Double) -> Double {
        let n = Catalog.gameDefaults[def.key].flatMap(Double.init) ?? 1
        return Swift.min(Swift.max(n, min), max)
    }
}

private struct InfoPopover: View {
    let def: SettingDef
    let info: SettingInfo
    let gameValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(def.title).font(.headline)
            Label(info.effect.label, systemImage: info.effect.symbol)
                .font(.caption)
                .foregroundStyle(info.effect.color)
            if !info.detail.isEmpty {
                Text(info.detail).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Not forced").foregroundStyle(.secondary)
                    Text(gameValue)
                }
                GridRow {
                    Text("Key").foregroundStyle(.secondary)
                    Text(def.key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            .font(.caption)
            Text(def.help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: - Preview and notices

struct PreviewPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            Text(state.plan.preview)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("Profile preview")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.plan.preview, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

struct NoticeBar: View {
    @EnvironmentObject private var state: AppState
    let notice: AppState.Notice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? .orange : .green)
            Text(notice.text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                state.notice = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss notice")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension Effectiveness {
    var color: Color {
        switch self {
        case .verified: return .green
        case .registered: return .orange
        case .experimental: return .purple
        }
    }
}
