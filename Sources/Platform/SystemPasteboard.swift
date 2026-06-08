import AppKit
import CoreGraphics

/// PasteboardAccess 的系统实现。
struct SystemPasteboard: PasteboardAccess {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
    func writeString(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

/// KeyboardSender 的系统实现：合成 ⌘V。
struct CGKeyboardSender: KeyboardSender {
    func sendPasteShortcut() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
