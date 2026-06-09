import SwiftUI
import AppKit

/// 录音浮窗可观察状态。
@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var isVisible = false
    @Published var transcript = ""
    @Published var level: Float = 0
    @Published var phase: Phase = .recording
    enum Phase { case recording, inserting, done }
    /// HUD「丢弃」按钮回调，由协调器注入。
    var onDiscard: () -> Void = {}
}

/// 把热键、识别、插入、HUD 串起来的协调器。
@MainActor
final class AppCoordinator: ObservableObject {
    let viewModel = RecordingViewModel()
    private var machine = DictationStateMachine()
    private let store: SettingsStore
    private let recognizer: SpeechRecognizing
    private let hotkeys: CGEventHotkeyMonitor
    private let inserterFactory: (AppSettings) -> ClipboardInserter
    private var hideTask: DispatchWorkItem?
    private var hudPanel: NSPanel?
    private var pressDownAt: Date?
    private let quickTapThreshold: TimeInterval = 0.4

    init(store: SettingsStore = SettingsStore(),
         recognizer: SpeechRecognizing = AppleSpeechRecognizer()) {
        self.store = store
        self.recognizer = recognizer
        self.hotkeys = CGEventHotkeyMonitor(config: store.settings.hotkeys)
        self.inserterFactory = { settings in
            ClipboardInserter(pasteboard: SystemPasteboard(),
                              keyboard: CGKeyboardSender(),
                              restoreClipboard: settings.restoreClipboard,
                              delay: { Thread.sleep(forTimeInterval: 0.15) })
        }
        configure()
        start()
        maybeShowOnboarding()
    }

    private func configure() {
        recognizer.onTranscript = { [weak self] text, _ in
            Task { @MainActor in self?.viewModel.transcript = text }
        }
        recognizer.onLevel = { [weak self] level in
            Task { @MainActor in self?.viewModel.level = level }
        }
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }
        viewModel.onDiscard = { [weak self] in self?.discard() }
    }

    func start() { hotkeys.start() }

    private func handle(_ event: HotkeyEvent) {
        let input: DictationInput
        switch event {
        case .pushToTalkDown:
            pressDownAt = Date()
            input = .pressDown
        case .pushToTalkUp:
            let quick = pressDownAt.map { Date().timeIntervalSince($0) < quickTapThreshold } ?? true
            input = .pressUp(quickTap: quick)
        case .toggle:
            input = .toggle
        case .confirm:
            input = .confirm
        }
        flog("coordinator.handle: event=\(event) → input=\(input)")
        apply(machine.handle(input))
    }

    /// HUD「丢弃」按钮调用：取消录音，不插入。
    func discard() {
        apply(machine.handle(.cancel))
    }

    private func apply(_ action: DictationAction) {
        flog("coordinator.apply: action=\(action) state=\(machine.state)")
        switch action {
        case .startRecording:
            hideTask?.cancel()
            viewModel.transcript = ""
            viewModel.phase = .recording
            viewModel.isVisible = true
            showHUD()
            do {
                try recognizer.start(locale: store.settings.locale)
                flog("coordinator: recognizer.start 成功 locale=\(store.settings.locale)")
            } catch {
                flog("coordinator: ❌ recognizer.start 抛错 \(error)")
            }
        case .stopAndInsert:
            let text = recognizer.stop()
            viewModel.phase = .inserting
            let inserter = inserterFactory(store.settings)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                inserter.insert(text)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.viewModel.phase = .done
                    self.machine.finished()
                    self.scheduleHide()
                }
            }
        case .discard:
            _ = recognizer.stop()
            machine.finished()
            scheduleHide()
        case .none:
            break
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.viewModel.isVisible = false
            self?.hideHUD()
        }
        hideTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    // MARK: - 录音浮窗（由协调器直接管理，不依赖 SwiftUI Scene.onChange）

    private func showHUD() {
        let panel = hudPanel ?? makeHUDPanel()
        hudPanel = panel
        if let screen = NSScreen.main {
            let size = NSSize(width: 360, height: 64)
            let origin = NSPoint(x: screen.frame.midX - size.width / 2,
                                 y: screen.frame.minY + 140)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func hideHUD() {
        hudPanel?.orderOut(nil)
    }

    private func makeHUDPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RecordingHUD(vm: viewModel))
        return panel
    }

    // MARK: - 设置 / 权限窗口（由协调器直接管理，菜单按钮可靠触发）

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showSettingsWindow() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let w = NSWindow(contentViewController: hosting)
            w.title = "FlowType 设置"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboardingWindow() {
        if onboardingWindow == nil {
            let hosting = NSHostingController(rootView: PermissionsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "欢迎使用 FlowType"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// 首次/未授全时自动弹权限引导。
    func maybeShowOnboarding() {
        let pm = PermissionManager()
        let allGranted = pm.microphone == .granted && pm.speech == .granted && pm.accessibility == .granted
        if !allGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboardingWindow()
            }
        }
    }
}
