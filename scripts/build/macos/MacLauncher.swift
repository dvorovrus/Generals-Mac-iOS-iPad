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

private func floatValue(_ values: [String: String], _ key: String, _ fallback: Double) -> Double {
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

final class MacLauncherModel: ObservableObject {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private lazy var supportDir = home
        .appendingPathComponent("Library/Application Support/GeneralsX/GeneralsZH", isDirectory: true)
    private lazy var optionsURL = supportDir.appendingPathComponent("Options.ini")
    private lazy var sagePatchURL = supportDir.appendingPathComponent("SagePatch.ini")
    private lazy var contraSettingsURL = supportDir.appendingPathComponent("ContraSettings.ini")
    private lazy var contraRoot = home.appendingPathComponent("GeneralsX/ContraX", isDirectory: true)
    private lazy var contraRuntime = home.appendingPathComponent("GeneralsX/ContraRuntime", isDirectory: true)
    private lazy var logURL = home.appendingPathComponent("Library/Logs/GeneralsXZH/contra-dev.log")

    let resolutions = ["2560 x 1600", "1920 x 1200", "1680 x 1050", "1440 x 900", "1280 x 800"]
    let textureQualities = ["High", "Medium", "Low"]
    let particleQualities = ["Low", "Medium", "High"]
    let textureFilters = ["Bilinear", "Trilinear", "Anisotropic"]

    let controlBars = ["Contra", "Pro", "Standard"]
    let cameos = ["Standard", "HD"]
    let musicModes = ["Standard", "Enhanced", "The Score"]
    let voiceModes = ["English", "Native"]
    let hotkeyModes = ["Original", "Leikeze"]
    let hotkeyLanguages = ["English", "Russian"]
    let portraitModes = ["Standard", "Funny"]

    @Published var resolution = "1920 x 1200"
    @Published var fullscreen = true

    @Published var shadows3D = false
    @Published var shadows2D = true
    @Published var cloudShadows = false
    @Published var groundLighting = true
    @Published var softWater = true
    @Published var buildingOcclusion = true
    @Published var showTrees = true
    @Published var extraAnimations = true
    @Published var dynamicLOD = false
    @Published var heatEffects = false
    @Published var textureQuality = "High"
    @Published var particleQuality = "Medium"
    @Published var textureFilter = "Anisotropic"

    @Published var maxCameraHeight = 550.0
    @Published var minCameraHeight = 70.0
    @Published var cameraPitch = 37.0
    @Published var enforceMaxCameraHeight = false
    @Published var scrollSpeed = 1.0
    @Published var drawDistance = 1.20
    @Published var fpsLimit = true
    @Published var fps = 60.0

    @Published var controlBar = "Contra"
    @Published var cameosMode = "Standard"
    @Published var musicMode = "Standard"
    @Published var voiceMode = "English"
    @Published var hotkeyMode = "Original"
    @Published var hotkeyLanguage = "English"
    @Published var portraitMode = "Standard"
    @Published var fogEffects = false
    @Published var waterEffects = true
    @Published var extraBuildingProps = true

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
        shadows2D = boolValue(options, "UseShadowDecals", true)
        cloudShadows = boolValue(options, "UseCloudMap", false)
        groundLighting = boolValue(options, "UseLightMap", true)
        softWater = boolValue(options, "ShowSoftWaterEdge", true)
        buildingOcclusion = boolValue(options, "BuildingOcclusion", true)
        showTrees = boolValue(options, "ShowTrees", true)
        extraAnimations = boolValue(options, "ExtraAnimations", true)
        dynamicLOD = boolValue(options, "DynamicLOD", false)
        heatEffects = boolValue(options, "HeatEffects", false)

        let reduction = Int(options["TextureReduction"] ?? "0") ?? 0
        textureQuality = reduction <= 0 ? "High" : (reduction == 1 ? "Medium" : "Low")
        let particles = Int(options["MaxParticleCount"] ?? "2500") ?? 2500
        particleQuality = particles <= 1200 ? "Low" : (particles >= 4000 ? "High" : "Medium")
        if let filter = options["TextureFilter"], textureFilters.contains(filter) {
            textureFilter = filter
        }

        let sage = readKeyValues(sagePatchURL)
        maxCameraHeight = floatValue(sage, "MaxCameraHeight", 550.0)
        minCameraHeight = floatValue(sage, "MinCameraHeight", 70.0)
        cameraPitch = floatValue(sage, "CameraPitch", 37.0)
        enforceMaxCameraHeight = boolValue(sage, "EnforceMaxCameraHeight", false)
        scrollSpeed = floatValue(sage, "KeyboardScrollSpeedFactor", 1.0)
        drawDistance = floatValue(sage, "TerrainDrawDistanceScale", 1.20)
        fpsLimit = boolValue(sage, "UseFPSLimit", true)
        fps = floatValue(sage, "FramesPerSecondLimit", 60.0)

        let contra = readKeyValues(contraSettingsURL)
        controlBar = contra["ControlBar"] ?? "Contra"
        cameosMode = contra["Cameos"] ?? "Standard"
        musicMode = contra["Music"] ?? "Standard"
        voiceMode = contra["UnitVoices"] ?? "English"
        hotkeyMode = contra["Hotkeys"] ?? "Original"
        hotkeyLanguage = contra["HotkeyLanguage"] ?? "English"
        portraitMode = contra["Portraits"] ?? "Standard"
        fogEffects = boolValue(contra, "FogEffects", false)
        waterEffects = boolValue(contra, "WaterEffects", true)
        extraBuildingProps = boolValue(contra, "ExtraBuildingProps", true)
    }

    func resetDefaults() {
        resolution = "1920 x 1200"
        fullscreen = true
        shadows3D = false
        shadows2D = true
        cloudShadows = false
        groundLighting = true
        softWater = true
        buildingOcclusion = true
        showTrees = true
        extraAnimations = true
        dynamicLOD = false
        heatEffects = false
        textureQuality = "High"
        particleQuality = "Medium"
        textureFilter = "Anisotropic"

        maxCameraHeight = 550
        minCameraHeight = 70
        cameraPitch = 37
        enforceMaxCameraHeight = false
        scrollSpeed = 1.0
        drawDistance = 1.20
        fpsLimit = true
        fps = 60

        controlBar = "Contra"
        cameosMode = "Standard"
        musicMode = "Standard"
        voiceMode = "English"
        hotkeyMode = "Original"
        hotkeyLanguage = "English"
        portraitMode = "Standard"
        fogEffects = false
        waterEffects = true
        extraBuildingProps = true
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
            options["UseShadowDecals"] = shadows2D ? "Yes" : "No"
            options["UseCloudMap"] = cloudShadows ? "Yes" : "No"
            options["UseLightMap"] = groundLighting ? "Yes" : "No"
            options["ShowSoftWaterEdge"] = softWater ? "Yes" : "No"
            options["BuildingOcclusion"] = buildingOcclusion ? "Yes" : "No"
            options["ShowTrees"] = showTrees ? "Yes" : "No"
            options["ExtraAnimations"] = extraAnimations ? "Yes" : "No"
            options["DynamicLOD"] = dynamicLOD ? "Yes" : "No"
            options["HeatEffects"] = heatEffects ? "Yes" : "No"
            options["TextureReduction"] = textureQuality == "High" ? "0" : (textureQuality == "Medium" ? "1" : "2")
            options["MaxParticleCount"] = particleQuality == "Low" ? "1000" : (particleQuality == "High" ? "5000" : "2500")
            options["TextureFilter"] = textureFilter
            options["AnisotropyLevel"] = textureFilter == "Anisotropic" ? "8" : "2"
            try writeKeyValues(options, to: optionsURL)

            let sage = """
            GameData
              MaxCameraHeight = \(Int(maxCameraHeight.rounded()))
              MinCameraHeight = \(Int(minCameraHeight.rounded()))
              CameraPitch = \(Int(cameraPitch.rounded()))
              EnforceMaxCameraHeight = \(enforceMaxCameraHeight ? "Yes" : "No")
              KeyboardScrollSpeedFactor = \(String(format: "%.1f", scrollSpeed))
              TerrainDrawDistanceScale = \(String(format: "%.2f", drawDistance))
              UseFPSLimit = \(fpsLimit ? "Yes" : "No")
              FramesPerSecondLimit = \(Int(fps.rounded()))
            End
            """
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try (sage + "\n").write(to: sagePatchURL, atomically: true, encoding: .utf8)

            let contra: [String: String] = [
                "ControlBar": controlBar,
                "Cameos": cameosMode,
                "Music": musicMode,
                "UnitVoices": voiceMode,
                "Hotkeys": hotkeyMode,
                "HotkeyLanguage": hotkeyLanguage,
                "Portraits": portraitMode,
                "FogEffects": fogEffects ? "Yes" : "No",
                "WaterEffects": waterEffects ? "Yes" : "No",
                "ExtraBuildingProps": extraBuildingProps ? "Yes" : "No"
            ]
            try writeKeyValues(contra, to: contraSettingsURL)
            try prepareContraRuntime(settings: contra)
            status = "Saved. Settings will be used for the next launch."
            refreshDiagnostics()
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    private func prepareContraRuntime(settings: [String: String]) throws {
        guard fm.fileExists(atPath: contraRoot.path) else { return }
        if fm.fileExists(atPath: contraRuntime.path) {
            try fm.removeItem(at: contraRuntime)
        }
        try fm.createDirectory(at: contraRuntime, withIntermediateDirectories: true)

        let entries = try fm.contentsOfDirectory(at: contraRoot,
                                                includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles])
        for source in entries {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let target = contraRuntime.appendingPathComponent(source.lastPathComponent, isDirectory: true)
                try fm.createSymbolicLink(at: target, withDestinationURL: source)
                continue
            }

            let ext = source.pathExtension.lowercased()
            var targetName = source.lastPathComponent
            if ext == "big" || ext == "ctr" {
                var logical = source.deletingPathExtension().lastPathComponent.lowercased() + ".ctr"
                let active = archiveShouldBeActive(logical, distributedActive: ext == "big", settings: settings)
                targetName = source.deletingPathExtension().lastPathComponent + (active ? ".big" : ".ctr")

                if active && (logical.hasSuffix("_controlbarpro.ctr") ||
                              logical.hasSuffix("_controlbarstandard.ctr")) {
                    targetName = "zzzz__Mac_Selected_ControlBar.big"
                }
            }

            let target = contraRuntime.appendingPathComponent(targetName)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.createSymbolicLink(at: target, withDestinationURL: source)
        }
    }

    private func archiveShouldBeActive(_ logical: String,
                                       distributedActive: Bool,
                                       settings: [String: String]) -> Bool {
        let required = [
            "_ini.ctr", "_maps.ctr", "_ai.ctr", "_terrain.ctr", "_textures.ctr",
            "_w3d.ctr", "_window.ctr", "_audio.ctr", "_gamedata.ctr", "_patch1.ctr"
        ]
        if required.contains(where: { logical.hasSuffix($0) }) { return true }

        let voices = (settings["UnitVoices"] ?? "English").lowercased()
        if logical.hasSuffix("_unitvoicesenglish.ctr") { return voices != "native" }
        if logical.hasSuffix("_unitvoicesnative.ctr") { return voices == "native" }

        let hotkeys = (settings["Hotkeys"] ?? "Original").lowercased()
        let language = (settings["HotkeyLanguage"] ?? "English").lowercased()
        if logical.hasSuffix("_hotkeysoriginal_english.ctr") { return hotkeys == "original" && language == "english" }
        if logical.hasSuffix("_hotkeysoriginal_russian.ctr") { return hotkeys == "original" && language == "russian" }
        if logical.hasSuffix("_hotkeysleikeze_english.ctr") { return hotkeys == "leikeze" && language == "english" }
        if logical.hasSuffix("_hotkeysleikeze_russian.ctr") { return hotkeys == "leikeze" && language == "russian" }

        let control = (settings["ControlBar"] ?? "Contra").lowercased()
        if logical.hasSuffix("_controlbarpro.ctr") { return control == "pro" }
        if logical.hasSuffix("_controlbarstandard.ctr") { return control == "standard" }

        let cameos = (settings["Cameos"] ?? "Standard").lowercased()
        if logical.hasSuffix("_cameoshd.ctr") { return cameos == "hd" }

        let music = (settings["Music"] ?? "Standard").lowercased()
        if logical.hasSuffix("_musicenhanced.ctr") || logical.hasSuffix("_newmusic.ctr") { return music == "enhanced" }
        if logical.hasSuffix("_musicthescore.ctr") { return music == "the score" }

        let portraits = (settings["Portraits"] ?? "Standard").lowercased()
        if logical.hasSuffix("_funnygeneralportraits.ctr") { return portraits == "funny" }

        if logical.hasSuffix("_disablefogeffects.ctr") { return !boolValue(settings, "FogEffects", false) }
        if logical.hasSuffix("_disablewatereffects.ctr") { return !boolValue(settings, "WaterEffects", true) }
        if logical.hasSuffix("_disableextrabuildingprops.ctr") { return !boolValue(settings, "ExtraBuildingProps", true) }

        return distributedActive
    }

    func refreshDiagnostics() {
        var lines: [String] = [
            "Options: \(optionsURL.path)",
            "Engine overrides: \(sagePatchURL.path)",
            "Contra settings: \(contraSettingsURL.path)",
            "Contra source: \(contraRoot.path)",
            "Contra runtime: \(contraRuntime.path)",
            "Log: \(logURL.path)",
            ""
        ]

        if let text = try? String(contentsOf: logURL, encoding: .utf8) {
            let tail = text.components(separatedBy: .newlines).suffix(120)
            lines.append(contentsOf: tail)
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

private struct ToggleRow: View {
    let title: String
    @Binding var value: Bool

    var body: some View {
        Toggle(title, isOn: $value)
    }
}

struct MacLauncherView: View {
    @StateObject private var model = MacLauncherModel()

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("CONTRA X").font(.system(size: 30, weight: .bold))
                Text("Beta 2 + Patch 1 · macOS").foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            TabView {
                Form {
                    Picker("Resolution", selection: $model.resolution) {
                        ForEach(model.resolutions, id: \.self) { Text($0) }
                    }
                    Toggle("Fullscreen", isOn: $model.fullscreen)
                    Picker("Texture quality", selection: $model.textureQuality) {
                        ForEach(model.textureQualities, id: \.self) { Text($0) }
                    }
                    Picker("Particles", selection: $model.particleQuality) {
                        ForEach(model.particleQualities, id: \.self) { Text($0) }
                    }
                    Picker("Texture filtering", selection: $model.textureFilter) {
                        ForEach(model.textureFilters, id: \.self) { Text($0) }
                    }
                    ToggleRow(title: "3D shadows", value: $model.shadows3D)
                    ToggleRow(title: "2D shadows", value: $model.shadows2D)
                    ToggleRow(title: "Cloud shadows", value: $model.cloudShadows)
                    ToggleRow(title: "Ground lighting", value: $model.groundLighting)
                    ToggleRow(title: "Soft water edge", value: $model.softWater)
                    ToggleRow(title: "Building occlusion", value: $model.buildingOcclusion)
                    ToggleRow(title: "Trees / props", value: $model.showTrees)
                    ToggleRow(title: "Extra animations", value: $model.extraAnimations)
                    ToggleRow(title: "Dynamic LOD", value: $model.dynamicLOD)
                    ToggleRow(title: "Heat effects", value: $model.heatEffects)
                }
                .padding(16)
                .tabItem { Label("Display", systemImage: "display") }

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
                    Toggle("Enforce maximum camera height", isOn: $model.enforceMaxCameraHeight)
                    HStack {
                        Text("Scroll speed")
                        Slider(value: $model.scrollSpeed, in: 0.5...2.0, step: 0.1)
                        Text(String(format: "%.1fx", model.scrollSpeed)).monospacedDigit().frame(width: 52)
                    }
                    HStack {
                        Text("Terrain draw distance")
                        Slider(value: $model.drawDistance, in: 0.75...2.0, step: 0.05)
                        Text(String(format: "%.2fx", model.drawDistance)).monospacedDigit().frame(width: 52)
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

                Form {
                    Picker("Control bar", selection: $model.controlBar) {
                        ForEach(model.controlBars, id: \.self) { Text($0) }
                    }
                    Picker("Cameos", selection: $model.cameosMode) {
                        ForEach(model.cameos, id: \.self) { Text($0) }
                    }
                    Picker("Music", selection: $model.musicMode) {
                        ForEach(model.musicModes, id: \.self) { Text($0) }
                    }
                    Picker("Unit voices", selection: $model.voiceMode) {
                        ForEach(model.voiceModes, id: \.self) { Text($0) }
                    }
                    Picker("Hotkeys", selection: $model.hotkeyMode) {
                        ForEach(model.hotkeyModes, id: \.self) { Text($0) }
                    }
                    Picker("Hotkey language", selection: $model.hotkeyLanguage) {
                        ForEach(model.hotkeyLanguages, id: \.self) { Text($0) }
                    }
                    Picker("Portraits", selection: $model.portraitMode) {
                        ForEach(model.portraitModes, id: \.self) { Text($0) }
                    }
                    Toggle("Fog effects", isOn: $model.fogEffects)
                    Toggle("Water effects", isOn: $model.waterEffects)
                    Toggle("Extra building props", isOn: $model.extraBuildingProps)
                    Text("Archive choices are applied through a generated ContraRuntime profile; original Contra X files are not modified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .tabItem { Label("Contra X", systemImage: "slider.horizontal.3") }

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
            .frame(minHeight: 500)

            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(model.status.hasPrefix("Save failed") ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Reset defaults") { model.resetDefaults() }
                Spacer()
                Button("Save") { model.save() }
                Button("Play Contra X") { model.play() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 780, height: 700)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct GeneralsXMacLauncherApp: App {
    var body: some Scene {
        WindowGroup("GeneralsZH Contra X") {
            MacLauncherView()
        }
        .windowResizability(.contentSize)
    }
}
