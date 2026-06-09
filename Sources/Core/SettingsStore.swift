import Foundation

enum InsertionMethod: String, Codable, CaseIterable {
    case smartPaste       // 智能粘贴（默认）
    case simulateTyping   // 模拟键入
    case accessibility    // 辅助功能 API
}

struct AppSettings: Equatable, Codable {
    var hotkeys: HotkeyConfig
    var locale: String
    var insertionMethod: InsertionMethod
    var restoreClipboard: Bool
    var launchAtLogin: Bool
    var forceOnDevice: Bool

    static let `default` = AppSettings(
        hotkeys: HotkeyConfig(pushToTalkKey: .modifierHold(keyCode: 61), // 右 Option 长按
                              toggleKey: .combo(keyCode: 49, modifiers: 0x80000)), // ⌥Space
        locale: "zh-CN",
        insertionMethod: .smartPaste,
        restoreClipboard: true,
        launchAtLogin: false,
        forceOnDevice: true
    )
}

/// 把 AppSettings 以 JSON 存进 UserDefaults。
final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "flowtype.settings.v2" // v2: 默认推键改为右 Option
    private(set) var settings: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    func update(_ newValue: AppSettings) {
        settings = newValue
        if let data = try? JSONEncoder().encode(newValue) {
            defaults.set(data, forKey: key)
        }
    }
}
