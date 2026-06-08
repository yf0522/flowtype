import Foundation

/// 一个可配置的热键标识：要么是 fn（地球键），要么是普通键码+修饰键组合。
enum KeyIdentifier: Equatable, Hashable, Codable {
    case fn
    case combo(keyCode: UInt16, modifiers: UInt)
}

/// 归一化后的原始键事件（由平台层 CGEventTap 翻译而来）。
struct RawKeyEvent: Equatable {
    enum Phase { case down, up }
    let phase: Phase
    let key: KeyIdentifier
}

/// 协调器关心的语义事件。
enum HotkeyEvent: Equatable {
    case pushToTalkDown
    case pushToTalkUp
    case toggle
}

struct HotkeyConfig: Equatable, Codable {
    var pushToTalkKey: KeyIdentifier
    var toggleKey: KeyIdentifier
}

/// 把原始键事件解析为语义事件。纯函数，无副作用。
struct HotkeyResolver {
    let config: HotkeyConfig

    func resolve(_ raw: RawKeyEvent) -> HotkeyEvent? {
        if raw.key == config.pushToTalkKey {
            return raw.phase == .down ? .pushToTalkDown : .pushToTalkUp
        }
        if raw.key == config.toggleKey {
            return raw.phase == .down ? .toggle : nil // 切换键只在按下时触发
        }
        return nil
    }
}
