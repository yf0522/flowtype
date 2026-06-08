# FlowType 语音听写 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一个 macOS 菜单栏 App，按住/切换热键说话，用 Apple 本地识别实时转写，松开后把文字插入当前输入框的光标处，全程离线。

**Architecture:** 原生 SwiftUI 菜单栏 App（`LSUIElement`），用 XcodeGen 从 `project.yml` 生成 Xcode 工程。纯逻辑（热键解析、听写状态机、剪贴板插入、设置存储）抽成可单测单元用 TDD 驱动；触硬件/系统的部分（CGEventTap、SFSpeechRecognizer、合成 ⌘V、SwiftUI 视图）写真实代码 + 构建通过 + 真机手动验收。

**Tech Stack:** Swift 6.3 / SwiftUI / AppKit（NSPanel、NSStatusItem）/ AVFoundation + Speech（本地 STT）/ CoreGraphics（CGEventTap、合成按键）/ XcodeGen / XCTest。

---

## 文件结构

```
flowtype/
├── project.yml                         # XcodeGen 工程定义
├── Sources/
│   ├── App/
│   │   ├── FlowTypeApp.swift           # @main 入口，菜单栏 App 装配
│   │   ├── AppCoordinator.swift        # 把热键/录音/插入/HUD 接起来的协调器
│   │   ├── Info.plist                  # LSUIElement + 麦克风/语音用途说明
│   │   └── FlowType.entitlements       # 关闭沙盒
│   ├── Core/                           # 纯逻辑，全部可单测
│   │   ├── HotkeyEvent.swift           # 热键事件类型 + HotkeyResolver
│   │   ├── DictationStateMachine.swift # 听写状态机
│   │   ├── ClipboardInserter.swift     # 智能粘贴逻辑 + 协议
│   │   ├── Protocols.swift             # SpeechRecognizing 等抽象
│   │   └── SettingsStore.swift         # AppSettings + 持久化
│   ├── Platform/                       # 系统/硬件具体实现
│   │   ├── CGEventHotkeyMonitor.swift  # CGEventTap 全局热键
│   │   ├── AppleSpeechRecognizer.swift # AVCaptureSession + SFSpeechRecognizer
│   │   ├── SystemPasteboard.swift      # NSPasteboard + 合成 ⌘V
│   │   └── PermissionManager.swift     # 四项授权查询/请求
│   └── UI/
│       ├── RecordingHUD.swift          # 录音浮窗（NSPanel + SwiftUI）
│       ├── MenuBarContent.swift        # 菜单栏下拉
│       ├── SettingsView.swift          # 设置窗口
│       └── PermissionsView.swift       # 首启权限引导
└── Tests/
    └── FlowTypeTests/
        ├── HotkeyResolverTests.swift
        ├── DictationStateMachineTests.swift
        ├── ClipboardInserterTests.swift
        └── SettingsStoreTests.swift
```

---

## Task 0: 工程脚手架（XcodeGen）

**Files:**
- Create: `project.yml`
- Create: `Sources/App/Info.plist`
- Create: `Sources/App/FlowType.entitlements`
- Create: `Sources/App/FlowTypeApp.swift`

- [ ] **Step 1: 写 `project.yml`**

```yaml
name: FlowType
options:
  bundleIdPrefix: com.flowtype
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
targets:
  FlowType:
    type: application
    platform: macOS
    sources:
      - Sources
    info:
      path: Sources/App/Info.plist
    entitlements:
      path: Sources/App/FlowType.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.flowtype.app
        INFOPLIST_KEY_LSUIElement: YES
  FlowTypeTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    dependencies:
      - target: FlowType
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.flowtype.tests
schemes:
  FlowType:
    build:
      targets:
        FlowType: all
        FlowTypeTests: [test]
    test:
      targets:
        - FlowTypeTests
```

- [ ] **Step 2: 写 `Sources/App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FlowType</string>
  <key>CFBundleIdentifier</key><string>com.flowtype.app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>FlowType 需要使用麦克风采集你的语音以进行本地听写。</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>FlowType 使用本地语音识别把你的语音转写为文字，识别在设备本地完成。</string>
</dict>
</plist>
```

- [ ] **Step 3: 写 `Sources/App/FlowType.entitlements`**（关闭沙盒，CGEventTap/跨 App 插入需要）

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><false/>
</dict>
</plist>
```

- [ ] **Step 4: 写最小可编译入口 `Sources/App/FlowTypeApp.swift`**

```swift
import SwiftUI

@main
struct FlowTypeApp: App {
    var body: some Scene {
        MenuBarExtra("FlowType", systemImage: "mic.fill") {
            Text("FlowType v0.1")
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
    }
}
```

- [ ] **Step 5: 生成工程并构建**

Run:
```bash
cd /Users/macbook/workSpace/flowtype && xcodegen generate && \
xcodebuild -scheme FlowType -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 把生成物加入忽略并提交**

```bash
cd /Users/macbook/workSpace/flowtype
printf '%s\n' 'FlowType.xcodeproj/' 'DerivedData/' '.DS_Store' 'build/' > .gitignore
git add -A && git commit -m "chore: XcodeGen 脚手架与菜单栏入口骨架"
```

---

## Task 1: 热键事件与解析（TDD）

**Files:**
- Create: `Sources/Core/HotkeyEvent.swift`
- Test: `Tests/FlowTypeTests/HotkeyResolverTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/FlowTypeTests/HotkeyResolverTests.swift`**

```swift
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: 编译失败（`HotkeyConfig` / `HotkeyResolver` 等未定义）。

- [ ] **Step 3: 写实现 `Sources/Core/HotkeyEvent.swift`**

```swift
import Foundation

/// 一个可配置的热键标识：要么是 fn（地球键），要么是普通键码+修饰键组合。
enum KeyIdentifier: Equatable, Hashable, Codable {
    case fn
    case combo(keyCode: UInt16, modifiers: UInt)
}

/// 归一化后的原始键事件（由平台层 CGEventTap 翻译而来）。
struct RawKeyEvent: Equatable {
    enum Phase { case down, up }
    let phase: Phase
    let key: KeyIdentifier
}

/// 协调器关心的语义事件。
enum HotkeyEvent: Equatable {
    case pushToTalkDown
    case pushToTalkUp
    case toggle
}

struct HotkeyConfig: Equatable, Codable {
    var pushToTalkKey: KeyIdentifier
    var toggleKey: KeyIdentifier
}

/// 把原始键事件解析为语义事件。纯函数，无副作用。
struct HotkeyResolver {
    let config: HotkeyConfig

    func resolve(_ raw: RawKeyEvent) -> HotkeyEvent? {
        if raw.key == config.pushToTalkKey {
            return raw.phase == .down ? .pushToTalkDown : .pushToTalkUp
        }
        if raw.key == config.toggleKey {
            return raw.phase == .down ? .toggle : nil // 切换键只在按下时触发
        }
        return nil
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **`，5 个测试通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(core): 热键事件类型与 HotkeyResolver 解析（TDD）"
```

---

## Task 2: 听写状态机（TDD）

**Files:**
- Create: `Sources/Core/DictationStateMachine.swift`
- Test: `Tests/FlowTypeTests/DictationStateMachineTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/FlowTypeTests/DictationStateMachineTests.swift`**

```swift
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: 编译失败（`DictationStateMachine` 未定义）。

- [ ] **Step 3: 写实现 `Sources/Core/DictationStateMachine.swift`**

```swift
import Foundation

enum DictationState: Equatable { case idle, recording, inserting }

enum DictationAction: Equatable { case startRecording, stopAndInsert, none }

/// 统一"按住"与"切换"两种触发的听写状态机。纯逻辑。
struct DictationStateMachine {
    private(set) var state: DictationState = .idle

    mutating func handle(_ event: HotkeyEvent) -> DictationAction {
        switch (state, event) {
        case (.idle, .pushToTalkDown), (.idle, .toggle):
            state = .recording
            return .startRecording
        case (.recording, .pushToTalkUp), (.recording, .toggle):
            state = .inserting
            return .stopAndInsert
        default:
            return .none
        }
    }

    /// TextInserter 完成插入后回调，回到空闲。
    mutating func insertionFinished() {
        state = .idle
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(core): 听写状态机统一按住/切换触发（TDD）"
```

---

## Task 3: 智能粘贴插入器（TDD）

**Files:**
- Create: `Sources/Core/ClipboardInserter.swift`
- Test: `Tests/FlowTypeTests/ClipboardInserterTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/FlowTypeTests/ClipboardInserterTests.swift`**

```swift
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

    func test_empty_text_does_nothing() {
        let pb = SpyPasteboard(); pb.current = "原有"
        let kb = SpyKeyboard()
        let inserter = ClipboardInserter(pasteboard: pb, keyboard: kb, restoreClipboard: true, delay: {})

        inserter.insert("")

        XCTAssertEqual(kb.pasteCount, 0)
        XCTAssertEqual(pb.writes, [])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: 编译失败（`PasteboardAccess` / `KeyboardSender` / `ClipboardInserter` 未定义）。

- [ ] **Step 3: 写实现 `Sources/Core/ClipboardInserter.swift`**

```swift
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 5: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(core): 智能粘贴插入器含剪贴板恢复（TDD）"
```

---

## Task 4: 设置模型与持久化（TDD）

**Files:**
- Create: `Sources/Core/SettingsStore.swift`
- Test: `Tests/FlowTypeTests/SettingsStoreTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/FlowTypeTests/SettingsStoreTests.swift`**

```swift
import XCTest
@testable import FlowType

final class SettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "flowtype.tests")!
        d.removePersistentDomain(forName: "flowtype.tests")
        return d
    }

    func test_load_returns_default_when_empty() {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertEqual(store.settings, AppSettings.default)
    }

    func test_save_then_load_roundtrip() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        var s = AppSettings.default
        s.locale = "en-US"
        s.insertionMethod = .simulateTyping
        s.restoreClipboard = false
        store.update(s)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.locale, "en-US")
        XCTAssertEqual(reloaded.settings.insertionMethod, .simulateTyping)
        XCTAssertFalse(reloaded.settings.restoreClipboard)
    }

    func test_default_hotkeys() {
        XCTAssertEqual(AppSettings.default.hotkeys.pushToTalkKey, .fn)
        XCTAssertEqual(AppSettings.default.locale, "zh-CN")
        XCTAssertEqual(AppSettings.default.insertionMethod, .smartPaste)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: 编译失败（`AppSettings` / `SettingsStore` 未定义）。

- [ ] **Step 3: 写实现 `Sources/Core/SettingsStore.swift`**

```swift
import Foundation

enum InsertionMethod: String, Codable, CaseIterable {
    case smartPaste       // 智能粘贴（默认）
    case simulateTyping   // 模拟键入
    case accessibility    // 辅助功能 API
}

struct AppSettings: Equatable, Codable {
    var hotkeys: HotkeyConfig
    var locale: String
    var insertionMethod: InsertionMethod
    var restoreClipboard: Bool
    var launchAtLogin: Bool
    var forceOnDevice: Bool

    static let `default` = AppSettings(
        hotkeys: HotkeyConfig(pushToTalkKey: .fn,
                              toggleKey: .combo(keyCode: 49, modifiers: 0x80000)), // ⌥Space
        locale: "zh-CN",
        insertionMethod: .smartPaste,
        restoreClipboard: true,
        launchAtLogin: false,
        forceOnDevice: true
    )
}

/// 把 AppSettings 以 JSON 存进 UserDefaults。
final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "flowtype.settings.v1"
    private(set) var settings: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    func update(_ newValue: AppSettings) {
        settings = newValue
        if let data = try? JSONEncoder().encode(newValue) {
            defaults.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **`，四个测试文件累计全部通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(core): AppSettings 模型与 UserDefaults 持久化（TDD）"
```

---

## Task 5: 听写协议与 Apple 本地识别实现

**Files:**
- Create: `Sources/Core/Protocols.swift`
- Create: `Sources/Platform/AppleSpeechRecognizer.swift`

> 这一步触硬件（麦克风/识别），不做单测；以"构建通过"为门槛，真机验收放到 Task 10。

- [ ] **Step 1: 写 `Sources/Core/Protocols.swift`**

```swift
import Foundation

/// 听写引擎抽象，便于协调器解耦具体实现。
protocol SpeechRecognizing: AnyObject {
    /// 部分/最终转写回调：(文本, 是否最终)
    var onTranscript: ((String, Bool) -> Void)? { get set }
    /// 实时音频电平回调，0...1，用于波形。
    var onLevel: ((Float) -> Void)? { get set }
    func start(locale: String) throws
    /// 停止并返回最终文本。
    func stop() -> String
}

enum SpeechError: Error { case onDeviceUnavailable, notAuthorized, engineFailure }
```

- [ ] **Step 2: 写 `Sources/Platform/AppleSpeechRecognizer.swift`**

```swift
import Foundation
import AVFoundation
import Speech

/// 基于 Apple 本地 SFSpeechRecognizer 的实现。参考 Muxy 同款方案。
final class AppleSpeechRecognizer: NSObject, SpeechRecognizing {
    var onTranscript: ((String, Bool) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "flowtype.audio")
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastText = ""

    func start(locale: String) throws {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
            throw SpeechError.engineFailure
        }
        guard rec.supportsOnDeviceRecognition else { throw SpeechError.onDeviceUnavailable }
        rec.defaultTaskHint = .dictation
        recognizer = rec
        lastText = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        request = req

        // 配置采集
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            throw SpeechError.engineFailure
        }
        session.addInput(input)
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }
        session.commitConfiguration()

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.lastText = result.bestTranscription.formattedString
                self.onTranscript?(self.lastText, result.isFinal)
            }
            if error != nil { /* 交由 stop 收尾 */ }
        }

        session.startRunning()
    }

    func stop() -> String {
        session.stopRunning()
        request?.endAudio()
        task?.finish()
        request = nil; task = nil
        return lastText
    }
}

extension AppleSpeechRecognizer: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        request?.appendAudioSampleBuffer(sampleBuffer)
        // 粗略电平：取样本绝对均值
        if let level = sampleBuffer.approxLevel { onLevel?(level) }
    }
}

private extension CMSampleBuffer {
    /// 简单的 RMS 近似，用于波形 UI（非精确）。
    var approxLevel: Float? {
        guard let bb = CMSampleBufferGetDataBuffer(self) else { return nil }
        var length = 0; var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let ptr = dataPointer, length > 1 else { return nil }
        let count = length / 2
        let samples = ptr.withMemoryRebound(to: Int16.self, capacity: count) { p in
            UnsafeBufferPointer(start: p, count: count)
        }
        var sum: Float = 0
        for s in samples { let v = Float(s) / 32768.0; sum += v * v }
        return min(1, sqrt(sum / Float(count)) * 4)
    }
}
```

- [ ] **Step 3: 构建确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodegen generate && xcodebuild -scheme FlowType -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(platform): SpeechRecognizing 协议与 Apple 本地识别实现"
```

---

## Task 6: 系统剪贴板 + 合成 ⌘V

**Files:**
- Create: `Sources/Platform/SystemPasteboard.swift`

- [ ] **Step 1: 写 `Sources/Platform/SystemPasteboard.swift`**

```swift
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
```

- [ ] **Step 2: 构建确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodegen generate && xcodebuild -scheme FlowType -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(platform): 系统剪贴板与合成 ⌘V 实现"
```

---

## Task 7: 全局热键监听（CGEventTap）

**Files:**
- Create: `Sources/Platform/CGEventHotkeyMonitor.swift`

- [ ] **Step 1: 写 `Sources/Platform/CGEventHotkeyMonitor.swift`**

```swift
import AppKit
import CoreGraphics

/// 用 CGEventTap 监听全局键盘事件，翻译为 RawKeyEvent 后用 HotkeyResolver 解析。
final class CGEventHotkeyMonitor {
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
```

> 注：`⌥Space` 的 modifiers 期望值 `0x80000` 对应 `CGEventFlags.maskAlternate`。若 Task 8 联调发现匹配不上，在此处把 `combo` 的 modifiers 归一化口径与 `AppSettings.default` 对齐（二者必须用同一套 rawValue）。

- [ ] **Step 2: 构建确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodegen generate && xcodebuild -scheme FlowType -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(platform): CGEventTap 全局热键监听"
```

---

## Task 8: 权限管理

**Files:**
- Create: `Sources/Platform/PermissionManager.swift`

- [ ] **Step 1: 写 `Sources/Platform/PermissionManager.swift`**

```swift
import AppKit
import AVFoundation
import Speech
import ApplicationServices

enum PermissionState: Equatable { case granted, denied, notDetermined }

/// 查询/请求四项授权：麦克风、语音识别、辅助功能、输入监控。
final class PermissionManager {
    var microphone: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    var speech: PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    var accessibility: PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    /// 弹出系统辅助功能授权提示（用户需手动到系统设置勾选）。
    func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// 打开"系统设置 > 隐私与安全性 > 输入监控"。
    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: 构建确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodegen generate && xcodebuild -scheme FlowType -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(platform): 四项授权的权限管理器"
```

---

## Task 9: 协调器 + UI 装配

**Files:**
- Create: `Sources/App/AppCoordinator.swift`
- Create: `Sources/UI/RecordingHUD.swift`
- Create: `Sources/UI/MenuBarContent.swift`
- Modify: `Sources/App/FlowTypeApp.swift`

- [ ] **Step 1: 写 `Sources/App/AppCoordinator.swift`**

```swift
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
                              delay: { usleep(150_000) })
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
```

- [ ] **Step 2: 写 `Sources/UI/RecordingHUD.swift`**

```swift
import SwiftUI

struct RecordingHUD: View {
    @ObservedObject var vm: RecordingViewModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: iconName).font(.system(size: 13)).foregroundStyle(.white))
            WaveformView(level: vm.level)
                .frame(width: 44, height: 22)
            Text(vm.transcript.isEmpty ? "聆听中…" : vm.transcript)
                .lineLimit(1).truncationMode(.head)
                .foregroundStyle(.white)
                .frame(maxWidth: 220, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.black.opacity(0.85), in: Capsule())
    }

    private var iconName: String {
        switch vm.phase { case .recording: "mic.fill"; case .inserting: "ellipsis"; case .done: "checkmark" }
    }
}

struct WaveformView: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(.purple)
                    .frame(width: 3, height: max(4, CGFloat(level) * 22 * heights[i]))
            }
        }
    }
    private let heights: [CGFloat] = [0.6, 1.0, 0.8, 1.0, 0.5]
}
```

- [ ] **Step 3: 写 `Sources/UI/MenuBarContent.swift`**

```swift
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator
    var body: some View {
        Text("FlowType · 就绪")
        Divider()
        Button("设置…") { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
```

- [ ] **Step 4: 改写 `Sources/App/FlowTypeApp.swift` 装配 HUD 浮窗**

```swift
import SwiftUI
import AppKit

@main
struct FlowTypeApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @State private var hud: NSWindow?

    var body: some Scene {
        MenuBarExtra("FlowType", systemImage: "mic.fill") {
            MenuBarContent().environmentObject(coordinator)
        }
        .onChange(of: coordinator.viewModel.isVisible) { _, visible in
            visible ? showHUD() : hud?.orderOut(nil)
        }
    }

    private func showHUD() {
        let panel = hud ?? makePanel()
        hud = panel
        if let screen = NSScreen.main {
            let size = NSSize(width: 360, height: 60)
            let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 80)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = NSHostingView(rootView: RecordingHUD(vm: coordinator.viewModel))
        return panel
    }
}
```

- [ ] **Step 5: 在 `AppCoordinator` 启动时调用 `start()`**

在 `FlowTypeApp` 的 `MenuBarExtra` 闭包后追加 `.task { coordinator.start() }`，或在 `AppCoordinator.init` 末尾的 `configure()` 之后调用 `start()`。这里采用前者——把 `MenuBarContent()...` 改为：

```swift
MenuBarContent().environmentObject(coordinator)
    .task { coordinator.start() }
```

- [ ] **Step 6: 构建确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodegen generate && xcodebuild -scheme FlowType -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat: 协调器与录音浮窗/菜单栏 UI 装配"
```

---

## Task 10: 设置窗口 + 权限引导 UI

**Files:**
- Create: `Sources/UI/SettingsView.swift`
- Create: `Sources/UI/PermissionsView.swift`
- Modify: `Sources/App/FlowTypeApp.swift`（加 `Settings` 场景）

- [ ] **Step 1: 写 `Sources/UI/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @State private var settings: AppSettings
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        _settings = State(initialValue: store.settings)
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("通用", systemImage: "keyboard") }
            insertTab.tabItem { Label("插入", systemImage: "text.cursor") }
            privacyTab.tabItem { Label("隐私", systemImage: "lock") }
        }
        .frame(width: 460, height: 300)
        .onChange(of: settings) { _, new in store.update(new) }
    }

    private var generalTab: some View {
        Form {
            Picker("听写语言", selection: $settings.locale) {
                Text("中文（普通话）").tag("zh-CN")
                Text("English (US)").tag("en-US")
            }
            Toggle("开机自启动", isOn: $settings.launchAtLogin)
            Text("按住说话：fn（地球键）  ·  切换式：⌥Space").foregroundStyle(.secondary).font(.caption)
        }.padding()
    }

    private var insertTab: some View {
        Form {
            Picker("插入方式", selection: $settings.insertionMethod) {
                Text("智能粘贴").tag(InsertionMethod.smartPaste)
                Text("模拟键入").tag(InsertionMethod.simulateTyping)
                Text("辅助功能 API").tag(InsertionMethod.accessibility)
            }
            Toggle("粘贴后恢复剪贴板", isOn: $settings.restoreClipboard)
        }.padding()
    }

    private var privacyTab: some View {
        Form {
            Toggle("强制本地识别（绝不上云）", isOn: $settings.forceOnDevice).disabled(true)
            Text("第一版仅支持本地识别。").foregroundStyle(.secondary).font(.caption)
        }.padding()
    }
}
```

- [ ] **Step 2: 写 `Sources/UI/PermissionsView.swift`**

```swift
import SwiftUI

struct PermissionsView: View {
    @State private var manager = PermissionManager()
    @State private var refresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("让 FlowType 开始工作").font(.title3.bold())
            row("麦克风", "采集你的语音", manager.microphone) { _ = await manager.requestMicrophone(); refresh.toggle() }
            row("语音识别", "本地识别模型", manager.speech) { _ = await manager.requestSpeech(); refresh.toggle() }
            row("辅助功能", "把文字插入其它 App", manager.accessibility) { manager.promptAccessibility() }
            row("输入监控", "监听全局热键", .denied) { manager.openInputMonitoringSettings() }
        }
        .padding(20).frame(width: 420)
        .id(refresh)
    }

    private func row(_ title: String, _ sub: String, _ state: PermissionState,
                     _ action: @escaping () async -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.body)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state == .granted {
                Text("已授权").foregroundStyle(.green)
            } else {
                Button("去开启") { Task { await action() } }
            }
        }
    }
}
```

- [ ] **Step 3: 在 `FlowTypeApp` 加 `Settings` 场景**

在 `body` 的 `MenuBarExtra {...}` 之后追加：

```swift
        Settings {
            SettingsView(store: SettingsStore())
        }
        Window("欢迎使用 FlowType", id: "permissions") {
            PermissionsView()
        }
```

- [ ] **Step 4: 构建确认通过**

Run: `cd /Users/macbook/workSpace/flowtype && xcodegen generate && xcodebuild -scheme FlowType -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "feat(ui): 设置窗口与权限引导界面"
```

---

## Task 11: 真机端到端验收

> 单测覆盖纯逻辑；本任务用真实运行验证触系统的链路。无代码改动，全部为人工检查项。

- [ ] **Step 1: 全量测试 + 构建**

Run: `cd /Users/macbook/workSpace/flowtype && xcodegen generate && xcodebuild -scheme FlowType -destination 'platform=macOS' test 2>&1 | tail -8`
Expected: `** TEST SUCCEEDED **`（4 个测试文件全过）。

- [ ] **Step 2: 运行 App**

Run: `cd /Users/macbook/workSpace/flowtype && xcodebuild -scheme FlowType -destination 'platform=macOS' -derivedDataPath build build 2>&1 | tail -3 && open build/Build/Products/Debug/FlowType.app`
Expected: 菜单栏出现麦克风图标，无 Dock 图标。

- [ ] **Step 3: 逐项手动验收（勾选）**

- [ ] 首次启动弹出权限引导，逐项授权后状态变「已授权」
- [ ] 在「系统设置 > 隐私 > 辅助功能 / 输入监控」中开启 FlowType
- [ ] 打开备忘录，光标置于文本中
- [ ] **按住 fn**：底部浮现录音浮窗，波形随说话起伏，实时显示转写文字
- [ ] **松开 fn**：浮窗消失，中文文字插入到备忘录光标处
- [ ] 复制一段文字到剪贴板 → 听写一句 → 插入后 ⌘V 仍是原来复制的内容（剪贴板已恢复）
- [ ] **按 ⌥Space**：开始持续录音；再按 ⌥Space：停止并插入
- [ ] 切到浏览器地址栏 / 微信输入框重复，文字落在正确光标处
- [ ] 断网后重复一次，仍可识别（确认纯本地）

- [ ] **Step 4: 记录验收结果并提交**

```bash
cd /Users/macbook/workSpace/flowtype
git add -A && git commit -m "docs: 真机端到端验收通过记录" --allow-empty
```

---

## 备注 / 已知风险（实现时留意）

1. **fn 键 listenOnly 局限**：`CGEventTap` 用 `.listenOnly` 不拦截系统对 fn 的默认行为（如触发系统听写/Emoji）。若冲突，在「系统设置 > 键盘 > 听写/按 fn 键」里改 fn 行为，或在设置里换默认按住键（如右 ⌘）。Task 7 联调时确认。
2. **modifiers rawValue 口径一致**：`AppSettings.default.toggleKey` 与 `CGEventHotkeyMonitor` 解析出的 modifiers 必须用同一套掩码（见 Task 7 注）。
3. **非沙盒**：本地自用无需公证；若日后分发需配置签名与公证。
4. **HUD 不抢焦点**：用 `.nonactivatingPanel` + `orderFrontRegardless()`，避免改变目标输入框的 caret 焦点。
5. **改键 UI 延后**：Task 10 设置页第一版只「展示」当前热键文本，不含交互式录制改键控件（捕获按键组合的 UI 较繁琐）。默认 fn / ⌥Space 已可用；改键录制作为 fast-follow。若联调发现默认键冲突，先在代码里改 `AppSettings.default`。
6. **录音中设备变更**：spec §4 提到的「录音中默认输入设备改变则拆掉重来」第一版未实现（v1 录音时段短，风险低）。如真机验收发现问题再补 `AudioInputDeviceObserver`。

## 最终复审后已知限制（MVP 验收时知悉，留待后续迭代）

最终整体复审修掉了 4 个 Critical（热键启动注册/剪贴板主线程/采集泄漏/状态竞争，见 commit `b09d839`）。以下 Important/Minor 项有意延后，不阻断 MVP：

- **I4 stop() 返回草稿转写而非最终结果**：`AppleSpeechRecognizer.stop()` 同步返回当前 `lastText`，而 `SFSpeechRecognitionTask` 的最终（isFinal）结果稍后才异步到达。短句本地识别下 partial≈final，长句可能插入的是草稿。后续改为等待 `isFinal` 或用 continuation。
- **I5 fn 键用 `.listenOnly`**：无法拦截系统对 fn 的默认行为（emoji/Globe 选择器）。按住 fn 说话时可能弹出 emoji 选择器。后续改用 `.defaultTap` 主动 tap 并在匹配热键时返回 nil 消费事件。
- **设置需重启生效**：设置窗口与协调器各持有独立 `SettingsStore`，改语言/触发键已持久化到磁盘但需重启 App 才被运行中的协调器读到。后续把协调器的 store 通过环境共享。
- **launchAtLogin / 非智能粘贴插入方式**：UI 已禁用并标注（未接 `SMAppService`、仅实现 smartPaste），待实现后再启用。
- **权限授予后需重启**：协调器在 `init` 注册 CGEventTap，若此时尚无输入监控权限会静默失败；用户授权后需重启 App。后续可加权限变更监听重注册。
