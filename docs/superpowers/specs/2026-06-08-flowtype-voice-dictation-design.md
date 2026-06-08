# FlowType — 系统级语音听写工具 · 设计文档

- 日期：2026-06-08
- 工作名：FlowType（可改）
- 状态：设计已与用户确认，待 spec 复审 → 实现计划

## 1. 目标

一个 macOS 系统级语音听写工具，类似 Typeless：按住热键说话，本地实时把语音转成文字，松开后文字直接插入到当前正在输入的那个输入框的**文本光标（caret）处**。完全离线，零 API 成本，支持中文。

### 成功标准
- 在任意原生 App（备忘录、微信、浏览器输入框等）按住热键说一句话，松开后该句中文文本出现在光标处。
- 全程不联网即可工作。
- 从按下热键到浮窗出现 < 300ms；从松开到文字落地 < 500ms（不含说话时长）。

## 2. 已确认的关键决策

| 决策点 | 选择 |
|--------|------|
| 插入位置 | 当前文本光标处（标准听写式，非鼠标坐标） |
| STT 引擎 | Apple 本地 `SFSpeechRecognizer`，`requiresOnDeviceRecognition = true`，绝不上云 |
| 触发方式 | 两种都要：① 按住热键说话（松开插入）② 热键开关切换（按一下开始/再按停止） |
| 默认热键 | 按住 = `fn`（地球键）；切换 = `⌥Space`（均可在设置改） |
| 默认插入方式 | 智能粘贴（暂存剪贴板 → 写入文本 → 模拟 ⌘V → 恢复剪贴板） |
| 技术栈 | 原生 Swift（SwiftUI 菜单栏 App）。本设计按此推进；最终在实现计划阶段确认 |
| 语言 | 中文（普通话）+ English (US)，设置可切 |

## 3. 架构

纯菜单栏 App（`LSUIElement`，无 Dock 图标、无主窗口），三个边界清晰、可独立测试的核心模块：

```
┌─ 菜单栏 App (SwiftUI, LSUIElement) ───────────────────┐
│  HotkeyManager        录音浮窗 (NSPanel)              │
│  全局热键监听            实时波形 + 部分转写回显          │
│  (CGEventTap)                 ▲                       │
│        │                      │ 状态(@Observable)     │
│        ▼                      │                       │
│  VoiceRecorder ───────────────┘                       │
│  AVCaptureSession → SFSpeechRecognizer (on-device)    │
│        │ 最终文本                                      │
│        ▼                                              │
│  TextInserter                                         │
│  智能粘贴 (NSPasteboard + ⌘V) ／ 回退方案              │
└───────────────────────────────────────────────────────┘
   系统授权：麦克风 · 语音识别 · 辅助功能 · 输入监控
```

### 3.1 模块职责

**HotkeyManager** — 全局热键监听
- 用 `CGEventTap`（监听 `fn` 的按下/松开必须用它；普通快捷键也走它）。
- 输出两类事件给协调层：`pushToTalkDown / pushToTalkUp`（按住模式）、`toggle`（切换模式）。
- 依赖系统「输入监控」授权。
- 接口：`start()`、`stop()`、回调 `onEvent: (HotkeyEvent) -> Void`。

**VoiceRecorder** — 音频采集 + 本地识别
- 复用 Muxy 已验证的同款方案：`AVCaptureSession` + `AVCaptureAudioDataOutput` → `SFSpeechAudioBufferRecognitionRequest`。
- `requiresOnDeviceRecognition = true`、`shouldReportPartialResults = true`、`defaultTaskHint = .dictation`。
- 暴露：当前音频电平（给波形）、部分转写（已定稿/未定稿分段）、最终文本。
- 依赖「麦克风」+「语音识别」授权。
- 接口：`requestPermissions() async`、`start(locale:)`、`stop() -> String`（返回最终文本）、回调 `onUpdate / onLevel`。

**TextInserter** — 把文本插入光标处
- 默认「智能粘贴」：读出当前剪贴板内容暂存 → 把识别文本写入 `NSPasteboard` → 用 `CGEvent` 合成 ⌘V → 延时后恢复原剪贴板。
- 依赖「辅助功能」授权（合成键盘事件需要）。
- 设置里提供备选：模拟键入（`CGEvent` 逐字，IME 下可能丢字，作为兜底）、辅助功能 API（`AXUIElement` 直接写焦点元素，兼容性参差）。
- 接口：`insert(_ text: String)`。

**RecordingHUD（录音浮窗）**
- 无边框 `NSPanel`，屏幕底部居中浮现；不抢焦点（否则会破坏目标输入框的 caret）。
- 三态：录音中（波形 + 实时转写 + 热键提示）／处理中（可选）／完成（"已插入 N 字"，0.3s 淡出）。
- 绑定 VoiceRecorder 的 `@Observable` 状态。

**协调层（AppCoordinator）** — 把上面四者接起来的状态机
- 监听 HotkeyManager 事件 → 驱动 VoiceRecorder 起停 → 更新 HUD → 停止时拿最终文本交给 TextInserter。
- 维护"按住"与"切换"两种触发的统一状态机（空闲 / 录音中 / 插入中）。

### 3.2 数据流（一次听写）
1. 按下热键 → HotkeyManager 发事件 → Coordinator 进入"录音中" → HUD 浮现。
2. VoiceRecorder 启动采集，本地流式识别，持续回吐电平 + 部分转写 → HUD 实时刷新。
3. 松开（按住模式）或再按（切换模式）→ VoiceRecorder 停止，返回最终文本。
4. TextInserter 智能粘贴到光标处。
5. HUD 显示"已插入 N 字" → 淡出 → 回到空闲。

## 4. 错误处理
- 任一授权缺失：HUD/菜单栏标红，点击进入权限引导页，逐项「去开启」跳转系统设置对应面板。
- 本地识别模型不可用（某语言未下载）：提示用户在系统设置下载，录音不启动。
- 录音中默认输入设备变更：参考 Muxy，拆掉本次录音并提示。
- 智能粘贴时目标 App 无可编辑焦点：插入静默失败 → HUD 提示"未找到输入位置"，剪贴板已恢复，不丢用户原剪贴板。
- 识别结果为空（没说话）：不插入，HUD 直接淡出。

## 5. 测试策略
- **VoiceRecorder**：注入假音频缓冲，断言部分/最终文本回调与状态流转；权限拒绝路径。
- **TextInserter**：剪贴板暂存→写入→恢复的纯逻辑可单测（不触发真实 ⌘V 的部分抽成可注入的"键盘事件发送器"协议，测试用 mock）。
- **HotkeyManager**：事件解析逻辑（按下/松开/切换判定）抽纯函数单测。
- **AppCoordinator 状态机**：用 mock 的三模块，断言"按住""切换"两条路径下的状态流转与最终插入调用。
- HUD / 系统授权 / 真实 ⌘V 走手动真机验收。

## 6. 第一版范围（YAGNI）

**做：**
- 菜单栏常驻 + 录音浮窗（三态）
- 按住说话 + 开关切换两种触发
- Apple 本地中/英识别 + 实时回显
- 智能粘贴插入到光标处（含剪贴板恢复）
- 设置：热键 / 语言 / 插入方式 / 隐私（强制本地开关）
- 首次启动权限引导（4 项授权）

**暂不做（fast-follow / 以后）：**
- 云端 Whisper / 通义切换
- AI 重写润色、自定义提示词
- 独立的"AI 标点整理"处理态（v1 直接插入识别器输出；Apple dictation 本身带基础标点）
- 转写历史库与搜索
- 自定义词典 / 专有名词纠正
- iOS 端

## 7. 开放项（实现计划阶段再定）
- 最终技术栈确认（原生 Swift vs 其它）。
- 项目脚手架：Xcode 项目 vs Swift Package。
- 打包/签名/分发方式（本地自用 vs 公证分发）。
