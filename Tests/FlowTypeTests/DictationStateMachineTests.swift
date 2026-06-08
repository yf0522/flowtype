import XCTest
@testable import FlowType

final class DictationStateMachineTests: XCTestCase {
    func test_pushToTalk_full_cycle() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.pushToTalkDown), .startRecording)
        XCTAssertEqual(m.state, .recording)
        XCTAssertEqual(m.handle(.pushToTalkUp), .stopAndInsert)
        XCTAssertEqual(m.state, .inserting)
        m.insertionFinished()
        XCTAssertEqual(m.state, .idle)
    }

    func test_toggle_cycle() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.toggle), .startRecording)
        XCTAssertEqual(m.state, .recording)
        XCTAssertEqual(m.handle(.toggle), .stopAndInsert)
        XCTAssertEqual(m.state, .inserting)
    }

    func test_pushToTalkUp_while_idle_is_noop() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.pushToTalkUp), .none)
        XCTAssertEqual(m.state, .idle)
    }

    func test_repeated_pushToTalkDown_while_recording_is_noop() {
        var m = DictationStateMachine()
        _ = m.handle(.pushToTalkDown)
        XCTAssertEqual(m.handle(.pushToTalkDown), .none)
        XCTAssertEqual(m.state, .recording)
    }

    func test_events_ignored_while_inserting() {
        var m = DictationStateMachine()
        _ = m.handle(.pushToTalkDown)
        _ = m.handle(.pushToTalkUp)
        XCTAssertEqual(m.handle(.toggle), .none)
        XCTAssertEqual(m.state, .inserting)
    }
}
