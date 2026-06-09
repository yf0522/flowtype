import XCTest
@testable import FlowType

final class DictationStateMachineTests: XCTestCase {
    // 长按：按下开始 → 长按松开（quick=false）插入
    func test_hold_to_talk_cycle() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.pressDown), .startRecording)
        XCTAssertEqual(m.state, .holding)
        XCTAssertEqual(m.handle(.pressUp(quickTap: false)), .stopAndInsert)
        XCTAssertEqual(m.state, .inserting)
        m.finished()
        XCTAssertEqual(m.state, .idle)
    }

    // 短按：按下开始 → 快速松开转持续录音 → 再按一下插入
    func test_short_tap_latches_then_second_press_inserts() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.pressDown), .startRecording)
        XCTAssertEqual(m.handle(.pressUp(quickTap: true)), .none)
        XCTAssertEqual(m.state, .latched)
        // 持续录音中再按
        XCTAssertEqual(m.handle(.pressDown), .stopAndInsert)
        XCTAssertEqual(m.state, .inserting)
    }

    // 切换键：按一下开始（持续），再按一下插入
    func test_toggle_cycle() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.toggle), .startRecording)
        XCTAssertEqual(m.state, .latched)
        XCTAssertEqual(m.handle(.toggle), .stopAndInsert)
        XCTAssertEqual(m.state, .inserting)
    }

    // 丢弃：长按录音中取消 → discard，回空闲
    func test_cancel_while_holding_discards() {
        var m = DictationStateMachine()
        _ = m.handle(.pressDown)
        XCTAssertEqual(m.handle(.cancel), .discard)
        XCTAssertEqual(m.state, .idle)
    }

    // 丢弃：持续录音中取消
    func test_cancel_while_latched_discards() {
        var m = DictationStateMachine()
        _ = m.handle(.toggle)
        XCTAssertEqual(m.handle(.cancel), .discard)
        XCTAssertEqual(m.state, .idle)
    }

    // 回车：持续录音中确定插入
    func test_confirm_while_latched_inserts() {
        var m = DictationStateMachine()
        _ = m.handle(.toggle)
        XCTAssertEqual(m.handle(.confirm), .stopAndInsert)
        XCTAssertEqual(m.state, .inserting)
    }

    // 回车：空闲时无效
    func test_confirm_while_idle_is_noop() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.confirm), .none)
        XCTAssertEqual(m.state, .idle)
    }

    // 空闲时松开是 no-op
    func test_pressUp_while_idle_is_noop() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.pressUp(quickTap: true)), .none)
        XCTAssertEqual(m.state, .idle)
    }

    // 插入中忽略其它输入
    func test_inputs_ignored_while_inserting() {
        var m = DictationStateMachine()
        _ = m.handle(.pressDown)
        _ = m.handle(.pressUp(quickTap: false)) // → inserting
        XCTAssertEqual(m.handle(.toggle), .none)
        XCTAssertEqual(m.handle(.pressDown), .none)
        XCTAssertEqual(m.state, .inserting)
    }
}
