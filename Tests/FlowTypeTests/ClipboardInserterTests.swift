import XCTest
@testable import FlowType

private final class SpyPasteboard: PasteboardAccess {
    var current: String?
    private(set) var writes: [String] = []
    func readString() -> String? { current }
    func writeString(_ s: String) { current = s; writes.append(s) }
}

private final class SpyKeyboard: KeyboardSender {
    private(set) var pasteCount = 0
    func sendPasteShortcut() { pasteCount += 1 }
}

final class ClipboardInserterTests: XCTestCase {
    func test_insert_saves_writes_pastes_then_restores() {
        let pb = SpyPasteboard(); pb.current = "原有剪贴板"
        let kb = SpyKeyboard()
        let inserter = ClipboardInserter(pasteboard: pb, keyboard: kb, restoreClipboard: true, delay: {})

        inserter.insert("你好世界")

        XCTAssertEqual(kb.pasteCount, 1)
        // 先写入待插入文本，再恢复原内容
        XCTAssertEqual(pb.writes, ["你好世界", "原有剪贴板"])
        XCTAssertEqual(pb.current, "原有剪贴板")
    }

    func test_insert_without_restore_keeps_text() {
        let pb = SpyPasteboard(); pb.current = "原有"
        let kb = SpyKeyboard()
        let inserter = ClipboardInserter(pasteboard: pb, keyboard: kb, restoreClipboard: false, delay: {})

        inserter.insert("文本")

        XCTAssertEqual(pb.writes, ["文本"])
        XCTAssertEqual(pb.current, "文本")
    }

    func test_insert_with_restore_but_empty_original_keeps_text() {
        let pb = SpyPasteboard() // current is nil
        let kb = SpyKeyboard()
        let inserter = ClipboardInserter(pasteboard: pb, keyboard: kb, restoreClipboard: true, delay: {})
        inserter.insert("文本")
        XCTAssertEqual(kb.pasteCount, 1)
        XCTAssertEqual(pb.writes, ["文本"])
        XCTAssertEqual(pb.current, "文本")
    }

    func test_empty_text_does_nothing() {
        let pb = SpyPasteboard(); pb.current = "原有"
        let kb = SpyKeyboard()
        let inserter = ClipboardInserter(pasteboard: pb, keyboard: kb, restoreClipboard: true, delay: {})

        inserter.insert("")

        XCTAssertEqual(kb.pasteCount, 0)
        XCTAssertEqual(pb.writes, [])
    }
}
