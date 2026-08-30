import Foundation

/// Settings persisted as JSON, kept byte-compatible with the JSON the app has
/// always written (`terminal`, `custom_command`, `open_in_tab`), so an existing
/// settings file keeps working without migration.
struct AppSettings: Codable {
    var terminal: String = "Terminal"
    var customCommand: String = ""
    var openInTab: Bool = false

    enum CodingKeys: String, CodingKey {
        case terminal
        case customCommand = "custom_command"
        case openInTab = "open_in_tab"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        terminal = try c.decodeIfPresent(String.self, forKey: .terminal) ?? "Terminal"
        customCommand = try c.decodeIfPresent(String.self, forKey: .customCommand) ?? ""
        openInTab = try c.decodeIfPresent(Bool.self, forKey: .openInTab) ?? false
    }
}

enum SettingsStore {
    static let terminals: [(value: String, label: String)] = [
        ("Terminal", "Terminal.app"),
        ("iTerm", "iTerm2"),
        ("Warp", "Warp"),
        ("Ghostty", "Ghostty"),
        ("WezTerm", "WezTerm"),
        ("kitty", "Kitty"),
        ("Alacritty", "Alacritty"),
    ]

    static var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.go2shellnext.app", isDirectory: true)
        return dir.appendingPathComponent("settings.json")
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    static func save(_ settings: AppSettings) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
