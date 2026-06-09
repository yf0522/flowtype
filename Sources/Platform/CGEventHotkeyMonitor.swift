import AppKit
import CoreGraphics
import ApplicationServices

/// 用 CGEventTap 监听全局键盘事件，翻译为 RawKeyEvent 后用 HotkeyResolver 解析。
final class CGEventHotkeyMonitor: @unchecked Sendable {
    var onEvent: ((HotkeyEvent) -> Void)?
    private var resolver: HotkeyResolver
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDown = false
    private var modifierDown: Set<UInt16> = []

    /// keyCode → 对应修饰键 flag（区分左右：54/55=Cmd, 56/60=Shift, 58/61=Option, 59/62=Control）。
    private static func modifierFlag(for keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        default: return nil
        }
    }

    init(config: HotkeyConfig) {
        self.resolver = HotkeyResolver(config: config)
    }

    func updateConfig(_ config: HotkeyConfig) {
        resolver = HotkeyResolver(config: config)
    }

    func start() {
        guard tap == nil else { flog("start(): 已有 tap，跳过"); return }
        let pre = CGPreflightListenEventAccess()
        flog("start(): CGPreflightListenEventAccess=\(pre) AXIsProcessTrusted=\(AXIsProcessTrusted())")
        if !pre {
            let granted = CGRequestListenEventAccess()
            flog("start(): CGRequestListenEventAccess 触发请求，返回=\(granted)（若为 false 需到设置授权后重启）")
        }
        flog("start(): 准备创建 CGEventTap")
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            flog("callback 触发: type=\(type.rawValue)")
            let monitor = Unmanaged<CGEventHotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            flog("start(): ❌ tapCreate 返回 nil —— 很可能缺少“输入监控”或“辅助功能”权限")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        flog("start(): ✅ tap 创建并启用成功")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系统临时禁用了 tap（启动时常见），必须重新启用，否则永久失效。
            flog("⚠️ tap 被禁用(type=\(type.rawValue))，重新启用")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            flog("flagsChanged: keyCode=\(keyCode) rawFlags=0x\(String(event.flags.rawValue, radix: 16))")
            // fn 键：secondaryFn 标志位
            let isFn = event.flags.contains(.maskSecondaryFn)
            if isFn != fnDown {
                fnDown = isFn
                emit(RawKeyEvent(phase: isFn ? .down : .up, key: .fn))
            }
            // 修饰键长按（右 Option 等）：按该 keyCode 对应的 flag 判断按下/松开
            if let flag = Self.modifierFlag(for: keyCode) {
                let pressed = event.flags.contains(flag)
                let wasDown = modifierDown.contains(keyCode)
                if pressed && !wasDown {
                    modifierDown.insert(keyCode)
                    emit(RawKeyEvent(phase: .down, key: .modifierHold(keyCode: keyCode)))
                } else if !pressed && wasDown {
                    modifierDown.remove(keyCode)
                    emit(RawKeyEvent(phase: .up, key: .modifierHold(keyCode: keyCode)))
                }
            }
        case .keyDown, .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let mods = event.flags.rawValue & (CGEventFlags.maskCommand.rawValue |
                                               CGEventFlags.maskAlternate.rawValue |
                                               CGEventFlags.maskShift.rawValue |
                                               CGEventFlags.maskControl.rawValue)
            let key = KeyIdentifier.combo(keyCode: keyCode, modifiers: UInt(mods))
            emit(RawKeyEvent(phase: type == .keyDown ? .down : .up, key: key))
        default:
            break
        }
    }

    private func emit(_ raw: RawKeyEvent) {
        let resolved = resolver.resolve(raw)
        flog("emit: raw=\(raw) → resolved=\(String(describing: resolved))")
        if let evt = resolved {
            DispatchQueue.main.async { [weak self] in self?.onEvent?(evt) }
        }
    }
}
