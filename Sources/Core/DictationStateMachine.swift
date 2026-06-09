import Foundation

enum DictationState: Equatable { case idle, holding, latched, inserting }

enum DictationAction: Equatable { case startRecording, stopAndInsert, discard, none }

/// 听写状态机输入。
enum DictationInput: Equatable {
    case pressDown
    case pressUp(quickTap: Bool)
    case toggle
    case cancel
}

/// 听写状态机（纯逻辑）。支持三种触发风格：
/// - 长按：按下开始，长按松开插入。
/// - 短按：按下开始，快速松开后持续录音（latched），再按一下插入。
/// - 切换键（⌥Space）：按一下开始（latched），再按一下插入。
/// - 丢弃：录音中取消，不插入。
struct DictationStateMachine {
    private(set) var state: DictationState = .idle

    mutating func handle(_ input: DictationInput) -> DictationAction {
        switch (state, input) {
        // 按下开始录音
        case (.idle, .pressDown):
            state = .holding
            return .startRecording

        // 长按松开 → 插入；快速松开 → 转持续录音
        case (.holding, .pressUp(let quick)):
            if quick {
                state = .latched
                return .none
            } else {
                state = .inserting
                return .stopAndInsert
            }

        // 切换键：空闲按一下进入持续录音
        case (.idle, .toggle):
            state = .latched
            return .startRecording

        // 持续录音中再按（推键第二次按下 / 切换键再按一下）→ 插入
        case (.latched, .pressDown), (.latched, .toggle):
            state = .inserting
            return .stopAndInsert

        // 丢弃：录音中取消
        case (.holding, .cancel), (.latched, .cancel):
            state = .idle
            return .discard

        default:
            return .none
        }
    }

    /// 插入/丢弃完成后回到空闲。
    mutating func finished() {
        state = .idle
    }
}
