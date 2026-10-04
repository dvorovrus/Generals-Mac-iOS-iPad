import SwiftUI
import AppKit
import Foundation

private let yesValues: Set<String> = ["yes", "true", "1", "on"]

private func trim(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func readKeyValues(_ url: URL) -> [String: String] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    for raw in text.components(separatedBy: .newlines) {
        let line = trim(raw)
        if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
        guard let eq = line.firstIndex(of: "=") else { continue }
        let key = trim(String(line[..<eq]))
        let value = trim(String(line[line.index(after: eq)...]))
        if !key.isEmpty { result[key] = value }
    }
    return result
}

private func boolValue(_ values: [String: String], _ key: String, _ fallback: Bool) -> Bool {
    guard let raw = values[key]?.lowercased() else { return fallback }
    return yesValues.contains(trim(raw))
}

private func doubleValue(_ values: [String: String], _ key: String, _ fallback: Double) -> Double {
    guard let raw = values[key], let value = Double(trim(raw)) else { return fallback }
    return value
}

private func writeKeyValues(_ values: [String: String], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let output = values.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        .map { "\($0) = \(values[$0] ?? "")" }
        .joined(separator: "\n") + "\n"
    try output.write(to: url, atomically: true, encoding: .utf8)
}

final class EnhancedLauncherModel: ObservableObject {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private lazy var supportDir = home
        .appendingPathComponent("Library/Application Support/GeneralsX/GeneralsZH", isDirectory: true)
    private lazy var optionsURL = supportDir.appendingPathComponent("Options.ini")
    private lazy var sagePatchURL = supportDir.appendingPathComponent("SagePatch.ini")
    private lazy var settingsURL = supportDir.appendingPathComponent("EnhancedSettings.ini")
    private lazy var sourceRoot = home.appendingPathComponent("GeneralsX/Enhanced", isDirectory: true)
    private lazy var runtimeRoot = home.appendingPathComponent("GeneralsX/EnhancedRuntime", isDirectory: true)
    private lazy var logURL = home.appendingPathComponent("Library/Logs/GeneralsXZH/enhanced-dev.log")

    let resolutions = ["2560 x 1600", "1920 x 1200", "1680 x 1050", "1440 x 900", "1280 x 800"]
    let engineTextureQualities = ["High", "Medium", "Low"]
    let textureResolutions = ["Vanilla", "High"]
    let uiQualities = ["HD", "FHD", "QHD"]
    let infantryIconScales = ["100%", "75%", "50%"]
    let cameoQualities = ["SD", "HD"]
    let aiModes = ["Default", "Restrained", "Skynet"]

    @Published var resolution = "1920 x 1200"
    @Published var fullscreen = true
    @Published var shadows3D = false
    @Published var engineTextureQuality = "High"

    @Published var textureResolution = "High"
    @Published var uiQuality = "FHD"
    @Published var infantryIconScale = "100%"
    @Published var cameos = "HD"
    @Published var aiScripts = "Default"

    @Published var maxCameraHeight = 550.0
    @Published var minCameraHeight = 70.0
    @Published var cameraPitch = 37.0
    @Published var fpsLimit = true
    @Published var fps = 60.0

    @Published var status = ""
    @Published var diagnostics = "Loading diagnostics…"

    init() {
        load()
        refreshDiagnostics()
    }

    func load() {
        let options = readKeyValues(optionsURL)
        if let raw = options["Resolution"] {
            let parts = raw.split(whereSeparator: { $0 == " " || $0 == "x" || $0 == "X" })
            if parts.count >= 2 {
                resolution = "\(parts[0]) x \(parts[1])"
            }
        }
        fullscreen = !boolValue(options, "Windowed", false)
        shadows3D = boolValue(options, "UseShadowVolumes", false)
        let reduction = Int(options["TextureReduction"] ?? "0") ?? 0
        engineTextureQuality = reduction <= 0 ? "High" : (reduction == 1 ? "Medium" : "Low")

        let settings = readKeyValues(settingsURL)
        textureResolution = settings["TextureResolution"] ?? "High"
        uiQuality = settings["UIQuality"] ?? "FHD"
        infantryIconScale = (settings["InfantryIconScale"] ?? "100") + "%"
        cameos = settings["Cameos"] ?? "HD"
        aiScripts = settings["AIScripts"] ?? "Default"

        let sage = readKeyValues(sagePatchURL)
        maxCameraHeight = doubleValue(sage, "MaxCameraHeight", 550.0)
        minCameraHeight = doubleValue(sage, "MinCameraHeight", 70.0)
        cameraPitch = doubleValue(sage, "CameraPitch", 37.0)
        fpsLimit = boolValue(sage, "UseFPSLimit", true)
        fps = doubleValue(sage, "FramesPerSecondLimit", 60.0)
    }

    func resetDefaults() {
        resolution = "1920 x 1200"
        fullscreen = true
        shadows3D = false
        engineTextureQuality = "High"
        textureResolution = "High"
        uiQuality = "FHD"
        infantryIconScale = "100%"
        cameos = "HD"
        aiScripts = "Default"
        maxCameraHeight = 550
        minCameraHeight = 70
        cameraPitch = 37
        fpsLimit = true
        fps = 60
        status = "Defaults restored. Press Save to apply."
    }

    func save() {
        do {
            var options = readKeyValues(optionsURL)
            let resolutionParts = resolution.components(separatedBy: " x ")
            let width = resolutionParts.first ?? "1920"
            let height = resolutionParts.count > 1 ? resolutionParts[1] : "1200"
            options["IdealStaticGameLOD"] = "High"
            options["StaticGameLOD"] = "Custom"
            options["Resolution"] = "\(width) \(height)"
            options["Windowed"] = fullscreen ? "No" : "Yes"
            options["UseShadowVolumes"] = shadows3D ? "Yes" : "No"
            options["TextureReduction"] = engineTextureQuality == "High" ? "0" :
                (engineTextureQuality == "Medium" ? "1" : "2")
            try writeKeyValues(options, to: optionsURL)

            let settings = [
                "TextureResolution": textureResolution,
                "UIQuality": uiQuality,
                "InfantryIconScale": infantryIconScale.replacingOccurrences(of: "%", with: ""),
                "Cameos": cameos,
                "AIScripts": aiScripts
            ]
            try writeKeyValues(settings, to: settingsURL)

            let sage = """
            GameData
              MaxCameraHeight = \(Int(maxCameraHeight.rounded()))
              MinCameraHeight = \(Int(minCameraHeight.rounded()))
              CameraPitch = \(Int(cameraPitch.rounded()))
              EnforceMaxCameraHeight = No
              KeyboardScrollSpeedFactor = 1.0
              TerrainDrawDistanceScale = 1.20
              UseFPSLimit = \(fpsLimit ? "Yes" : "No")
              FramesPerSecondLimit = \(Int(fps.rounded()))
            End
            """
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try (sage + "\n").write(to: sagePatchURL, atomically: true, encoding: .utf8)

            try prepareRuntime(settings: settings)
            status = "Saved. Enhanced settings will be used for the next launch."
            refreshDiagnostics()
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    private func link(_ source: URL, to target: URL, directory: Bool = false) throws {
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        if directory {
            try fm.createSymbolicLink(at: target, withDestinationURL: source)
        } else {
            try fm.createSymbolicLink(at: target, withDestinationURL: source)
        }
    }

    private func prepareRuntime(settings: [String: String]) throws {
        guard fm.fileExists(atPath: sourceRoot.path) else {
            throw NSError(domain: "EnhancedLauncher", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Enhanced data is not installed."])
        }

        if fm.fileExists(atPath: runtimeRoot.path) {
            try fm.removeItem(at: runtimeRoot)
        }
        try fm.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        let entries = try fm.contentsOfDirectory(at: sourceRoot,
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles])
        for source in entries {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            let lower = source.lastPathComponent.lowercased()

            if values.isDirectory == true {
                if lower == "optional" { continue }

                if lower == "data" {
                    let runtimeData = runtimeRoot.appendingPathComponent("Data", isDirectory: true)
                    try fm.createDirectory(at: runtimeData, withIntermediateDirectories: true)
                    let dataEntries = try fm.contentsOfDirectory(at: source,
                                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                                 options: [.skipsHiddenFiles])
                    for dataSource in dataEntries where dataSource.lastPathComponent.lowercased() != "scripts" {
                        try link(dataSource,
                                 to: runtimeData.appendingPathComponent(dataSource.lastPathComponent))
                    }

                    var scriptsSource = source.appendingPathComponent("Scripts", isDirectory: true)
                    if aiScripts.lowercased() == "restrained" {
                        scriptsSource = sourceRoot
                            .appendingPathComponent("Optional/AI/Restrained/Scripts", isDirectory: true)
                    } else if aiScripts.lowercased() == "skynet" {
                        scriptsSource = sourceRoot
                            .appendingPathComponent("Optional/AI/Skynet/Scripts", isDirectory: true)
                    }
                    if !fm.fileExists(atPath: scriptsSource.path) {
                        scriptsSource = source.appendingPathComponent("Scripts", isDirectory: true)
                    }
                    try link(scriptsSource, to: runtimeData.appendingPathComponent("Scripts"), directory: true)
                    continue
                }

                try link(source,
                         to: runtimeRoot.appendingPathComponent(source.lastPathComponent),
                         directory: true)
                continue
            }

            let ext = source.pathExtension.lowercased()
            var targetName = source.lastPathComponent
            if ext == "big" || ext == "zhe" {
                let base = source.deletingPathExtension().lastPathComponent
                let name = source.lastPathComponent.lowercased()
                let baseHD = name.hasPrefix("!zhe8texturesbasehd_")
                let cameoHD = name == "!zhe8cameohd_99.big" || name == "!zhe8cameohd_99.zhe"
                let cameoSD = name == "!zhe8cameosd_99.big" || name == "!zhe8cameosd_99.zhe"
                let uiFHD = name == "!zhe8uifhd_99.big" || name == "!zhe8uifhd_99.zhe"
                let uiHD = name == "!zhe8uihd_99.big" || name == "!zhe8uihd_99.zhe"
                let uiQHD = name == "!zhe8uiqhd_99.big" || name == "!zhe8uiqhd_99.zhe"
                let icons100 = name == "!zhe8iui_97.big" || name == "!zhe8iui_97.zhe"
                let icons75 = name == "!zhe8iui_98.big" || name == "!zhe8iui_98.zhe"
                let icons50 = name == "!zhe8iui_99.big" || name == "!zhe8iui_99.zhe"
                let defaultAI = name == "scriptszh.big" || name == "scriptszh.zhe"
                let restrainedAI = name == "!zhe8airestrained_99.big" || name == "!zhe8airestrained_99.zhe"
                let skynetAI = name == "!zhe8aiskynet_99.big" || name == "!zhe8aiskynet_99.zhe"

                var active = ext == "big"
                if baseHD {
                    active = textureResolution.lowercased() == "high"
                } else if icons100 || icons75 || icons50 {
                    active = (infantryIconScale == "100%" && icons100) ||
                             (infantryIconScale == "75%" && icons75) ||
                             (infantryIconScale == "50%" && icons50)
                } else if cameoHD || cameoSD {
                    active = (cameos.lowercased() == "hd" && cameoHD) ||
                             (cameos.lowercased() == "sd" && cameoSD)
                } else if uiFHD || uiHD || uiQHD {
                    active = (uiQuality.lowercased() == "fhd" && uiFHD) ||
                             (uiQuality.lowercased() == "hd" && uiHD) ||
                             (uiQuality.lowercased() == "qhd" && uiQHD)
                } else if defaultAI {
                    active = aiScripts.lowercased() != "restrained" && aiScripts.lowercased() != "skynet"
                } else if restrainedAI || skynetAI {
                    active = (aiScripts.lowercased() == "restrained" && restrainedAI) ||
                             (aiScripts.lowercased() == "skynet" && skynetAI)
                }

                targetName = base + (active ? ".big" : ".zhe")
                if active && baseHD {
                    targetName = "zzzz__Mac_Enhanced_FactionHD_\(base).big"
                } else if active && (icons100 || icons75 || icons50) {
                    targetName = "zzzz__Mac_Enhanced_InfantryIcons.big"
                } else if active && (cameoHD || cameoSD) {
                    targetName = "zzzz__Mac_Enhanced_Cameos.big"
                } else if active && (uiFHD || uiHD || uiQHD) {
                    targetName = "zzzz__Mac_Enhanced_UI.big"
                } else if active && (restrainedAI || skynetAI) {
                    targetName = "zzzz__Mac_Enhanced_AI.big"
                }
            }

            try link(source, to: runtimeRoot.appendingPathComponent(targetName))
        }
    }

    func refreshDiagnostics() {
        var lines = [
            "Enhanced settings: \(settingsURL.path)",
            "Options: \(optionsURL.path)",
            "Engine overrides: \(sagePatchURL.path)",
            "Enhanced source: \(sourceRoot.path)",
            "Enhanced runtime: \(runtimeRoot.path)",
            "Log: \(logURL.path)",
            "",
            "Texture resolution: \(textureResolution)",
            "UI quality: \(uiQuality)",
            "Infantry icons: \(infantryIconScale)",
            "Cameos: \(cameos)",
            "AI scripts: \(aiScripts)",
            ""
        ]
        if let text = try? String(contentsOf: logURL, encoding: .utf8) {
            lines.append(contentsOf: text.components(separatedBy: .newlines).suffix(120))
        } else {
            lines.append("No runtime log yet.")
        }
        diagnostics = lines.joined(separator: "\n")
    }

    func revealLog() {
        let target = fm.fileExists(atPath: logURL.path) ? logURL : logURL.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func play() {
        save()
        guard !status.hasPrefix("Save failed") else { return }
        if let actionPath = ProcessInfo.processInfo.environment["GX_MAC_LAUNCH_ACTION_FILE"] {
            try? "play\n".write(toFile: actionPath, atomically: true, encoding: .utf8)
        }
        NSApplication.shared.terminate(nil)
    }
}

struct EnhancedLauncherView: View {
    @StateObject private var model = EnhancedLauncherModel()

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("ENHANCED").font(.system(size: 30, weight: .bold))
                Text("v1.0 + 28/03/2024 patch · macOS").foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            TabView {
                Form {
                    Picker("Resolution", selection: $model.resolution) {
                        ForEach(model.resolutions, id: \.self) { Text($0) }
                    }
                    Toggle("Fullscreen", isOn: $model.fullscreen)
                    Picker("Engine texture quality", selection: $model.engineTextureQuality) {
                        ForEach(model.engineTextureQualities, id: \.self) { Text($0) }
                    }
                    Toggle("3D shadows", isOn: $model.shadows3D)
                }
                .padding(16)
                .tabItem { Label("Display", systemImage: "display") }

                Form {
                    Picker("Faction textures", selection: $model.textureResolution) {
                        ForEach(model.textureResolutions, id: \.self) { Text($0) }
                    }
                    Picker("UI quality", selection: $model.uiQuality) {
                        ForEach(model.uiQualities, id: \.self) { Text($0) }
                    }
                    Picker("Infantry icons", selection: $model.infantryIconScale) {
                        ForEach(model.infantryIconScales, id: \.self) { Text($0) }
                    }
                    Picker("Cameos", selection: $model.cameos) {
                        ForEach(model.cameoQualities, id: \.self) { Text($0) }
                    }
                    Picker("AI scripts", selection: $model.aiScripts) {
                        ForEach(model.aiModes, id: \.self) { Text($0) }
                    }
                    Text("These choices reproduce the portable parts of the original Enhanced launcher. ReShade/DXWrapper are Windows-only and are not enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .tabItem { Label("Enhanced", systemImage: "slider.horizontal.3") }

                Form {
                    HStack {
                        Text("Maximum camera height")
                        Slider(value: $model.maxCameraHeight, in: 200...800, step: 10)
                        Text("\(Int(model.maxCameraHeight))").monospacedDigit().frame(width: 52)
                    }
                    HStack {
                        Text("Minimum camera height")
                        Slider(value: $model.minCameraHeight, in: 30...200, step: 5)
                        Text("\(Int(model.minCameraHeight))").monospacedDigit().frame(width: 52)
                    }
                    HStack {
                        Text("Camera pitch")
                        Slider(value: $model.cameraPitch, in: 20...60, step: 1)
                        Text("\(Int(model.cameraPitch))°").monospacedDigit().frame(width: 52)
                    }
                    Toggle("FPS limit", isOn: $model.fpsLimit)
                    HStack {
                        Text("Frames per second")
                        Slider(value: $model.fps, in: 30...144, step: 5)
                            .disabled(!model.fpsLimit)
                        Text("\(Int(model.fps))").monospacedDigit().frame(width: 52)
                    }
                }
                .padding(16)
                .tabItem { Label("Camera", systemImage: "camera") }

                VStack(spacing: 10) {
                    ScrollView {
                        Text(model.diagnostics)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    HStack {
                        Button("Refresh") { model.refreshDiagnostics() }
                        Button("Reveal log in Finder") { model.revealLog() }
                    }
                }
                .padding(16)
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            }
            .frame(minHeight: 470)

            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption)
                    .foregroundColor(model.status.hasPrefix("Save failed")
                        ? Color.red
                        : Color(nsColor: .secondaryLabelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Reset defaults") { model.resetDefaults() }
                Spacer()
                Button("Save") { model.save() }
                Button("Play Enhanced") { model.play() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 760, height: 650)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct GeneralsXEnhancedLauncherApp: App {
    var body: some Scene {
        WindowGroup("Enhanced") {
            EnhancedLauncherView()
        }
        .windowResizability(.contentSize)
    }
}
