import XCTest
@testable import FlowType

final class HotkeyResolverTests: XCTestCase {
    let config = HotkeyConfig(pushToTalkKey: .fn, toggleKey: .combo(keyCode: 49, modifiers: 0x80000)) // ⌥Space

    func test_pushKey_down_yields_pushToTalkDown() {
        let r = HotkeyResolver(config: config)
        XCTAssertEqual(r.resolve(RawKeyEvent(phase: .down, key: .fn)), .pushToTalkDown)
    }

    func test_pushKey_up_yields_pushToTalkUp() {
        let r = HotkeyResolver(config: config)
        XCTAssertEqual(r.resolve(RawKeyEvent(phase: .up, key: .fn)), .pushToTalkUp)
    }

    func test_toggleKey_down_yields_toggle() {
        let r = HotkeyResolver(config: config)
        XCTAssertEqual(r.resolve(RawKeyEvent(phase: .down, key: .combo(keyCode: 49, modifiers: 0x80000))), .toggle)
    }

    func test_toggleKey_up_is_ignored() {
        let r = HotkeyResolver(config: config)
        XCTAssertNil(r.resolve(RawKeyEvent(phase: .up, key: .combo(keyCode: 49, modifiers: 0x80000))))
    }

    func test_unrelated_key_is_ignored() {
        let r = HotkeyResolver(config: config)
        XCTAssertNil(r.resolve(RawKeyEvent(phase: .down, key: .combo(keyCode: 0, modifiers: 0))))
    }
}
