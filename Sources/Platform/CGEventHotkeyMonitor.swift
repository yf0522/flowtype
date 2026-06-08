import AppKit
import CoreGraphics

/// 用 CGEventTap 监听全局键盘事件，翻译为 RawKeyEvent 后用 HotkeyResolver 解析。
final class CGEventHotkeyMonitor: @unchecked Sendable {
    var onEvent: ((HotkeyEvent) -> Void)?
    private var resolver: HotkeyResolver
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDown = false

    init(config: HotkeyConfig) {
        self.resolver = HotkeyResolver(config: config)
    }

    func updateConfig(_ config: HotkeyConfig) {
        resolver = HotkeyResolver(config: config)
    }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
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
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            // fn 键：secondaryFn 标志位
            let isFn = event.flags.contains(.maskSecondaryFn)
            if isFn != fnDown {
                fnDown = isFn
                emit(RawKeyEvent(phase: isFn ? .down : .up, key: .fn))
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
        if let evt = resolver.resolve(raw) {
            DispatchQueue.main.async { [weak self] in self?.onEvent?(evt) }
        }
    }
}
