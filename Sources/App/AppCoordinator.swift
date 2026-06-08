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
    }

    private func configure() {
        recognizer.onTranscript = { [weak self] text, _ in
            Task { @MainActor in self?.viewModel.transcript = text }
        }
        recognizer.onLevel = { [weak self] level in
            Task { @MainActor in self?.viewModel.level = level }
        }
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }
    }

    func start() { hotkeys.start() }

    private func handle(_ event: HotkeyEvent) {
        switch machine.handle(event) {
        case .startRecording:
            viewModel.transcript = ""
            viewModel.phase = .recording
            viewModel.isVisible = true
            try? recognizer.start(locale: store.settings.locale)
        case .stopAndInsert:
            let text = recognizer.stop()
            viewModel.phase = .inserting
            inserterFactory(store.settings).insert(text)
            viewModel.phase = .done
            machine.insertionFinished()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.viewModel.isVisible = false
            }
        case .none:
            break
        }
    }
}
