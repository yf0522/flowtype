import Foundation

protocol PasteboardAccess {
    func readString() -> String?
    func writeString(_ s: String)
}

protocol KeyboardSender {
    func sendPasteShortcut() // 合成 ⌘V
}

/// 智能粘贴：暂存剪贴板 → 写入待插入文本 → 合成 ⌘V → 等待 → 恢复原剪贴板。
struct ClipboardInserter {
    let pasteboard: PasteboardAccess
    let keyboard: KeyboardSender
    let restoreClipboard: Bool
    /// 注入的等待（生产环境为 ~150ms，测试为 no-op），确保粘贴完成后再恢复。
    /// 仅当 restoreClipboard == true 时才会被调用。
    let delay: () -> Void

    func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let saved = restoreClipboard ? pasteboard.readString() : nil
        pasteboard.writeString(text)
        keyboard.sendPasteShortcut()
        guard restoreClipboard else { return }
        delay()
        if let saved { pasteboard.writeString(saved) }
    }
}
