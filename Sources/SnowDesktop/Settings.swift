import AppKit
import ServiceManagement
import SnowCore

struct SnowAppearance: Codable {
    var brightness: Double = 0.94
    var warmth: Double = 0
    var color: NSColor {
        let value = 0.56 + brightness * 0.44
        return NSColor(srgbRed: min(1, value + max(0, warmth) * 0.05),
                       green: value * (1 - abs(warmth) * 0.035),
                       blue: min(1, value + max(0, -warmth) * 0.06 - max(0, warmth) * 0.13), alpha: 1)
    }
}

struct Preferences: Codable {
    var enabled = true
    var intensity = 0
    var speed: Double = 1
    var onWindows = true
    var onDock = true
    var fullWidthDock = false
    var falling = SnowAppearance(brightness: 0.92, warmth: 0)
    var settled = SnowAppearance(brightness: 0.98, warmth: -0.08)
    var saverInstalled = false
}

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?
    var value: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "preferences.v1") }
            onChange?()
        }
    }
    private init() {
        if let data = defaults.data(forKey: "preferences.v1"),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            value = decoded
        } else { value = Preferences() }
        value.speed = max(0.35, min(2.5, value.speed))
        value.intensity = max(0, min(2, value.intensity))
        value.falling.brightness = max(0, min(1, value.falling.brightness))
        value.settled.brightness = max(0, min(1, value.settled.brightness))
        value.falling.warmth = max(-1, min(1, value.falling.warmth))
        value.settled.warmth = max(-1, min(1, value.settled.warmth))
    }
    var startsAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
    var saverURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/Snow Desktop.saver")
    }
    func installSaver(_ enabled: Bool) throws {
        if enabled {
            guard let source = Bundle.main.url(forResource: "Snow Desktop", withExtension: "saver") else {
                throw NSError(domain: "SnowDesktop", code: 1, userInfo: [NSLocalizedDescriptionKey: "В сборке отсутствует модуль заставки."])
            }
            try FileManager.default.createDirectory(at: saverURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: saverURL.path) { try FileManager.default.removeItem(at: saverURL) }
            try FileManager.default.copyItem(at: source, to: saverURL)
            openSaverSettings()
        } else if FileManager.default.fileExists(atPath: saverURL.path) {
            try FileManager.default.removeItem(at: saverURL)
        }
        value.saverInstalled = enabled
    }
    func openSaverSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
