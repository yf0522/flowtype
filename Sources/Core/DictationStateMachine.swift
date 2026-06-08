import Foundation

enum DictationState: Equatable { case idle, recording, inserting }

enum DictationAction: Equatable { case startRecording, stopAndInsert, none }

/// 统一"按住"与"切换"两种触发的听写状态机。纯逻辑。
struct DictationStateMachine {
    private(set) var state: DictationState = .idle

    mutating func handle(_ event: HotkeyEvent) -> DictationAction {
        switch (state, event) {
        case (.idle, .pushToTalkDown), (.idle, .toggle):
            state = .recording
            return .startRecording
        case (.recording, .pushToTalkUp), (.recording, .toggle):
            state = .inserting
            return .stopAndInsert
        default:
            return .none
        }
    }

    /// TextInserter 完成插入后回调，回到空闲。
    mutating func insertionFinished() {
        state = .idle
    }
}
