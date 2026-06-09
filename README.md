# FlowType · 本地语音听写

macOS 菜单栏常驻的语音听写小工具：按住或轻点一个热键说话，用 **Apple 本地语音识别**实时转写，文字直接插入到当前输入框的光标处。**全程离线、不上云、免费、支持中文。**

> 灵感来自 Typeless。基于 SwiftUI + Apple Speech 框架，纯本地识别（`requiresOnDeviceRecognition`）。

## 功能

- 🎙️ **本地识别**：Apple `SFSpeechRecognizer` 强制本地，语音不出本机
- ⌨️ **两种触发**
  - **长按右 Option** = 按住说话，松开插入
  - **短按右 Option** = 开始持续录音，再按一下插入
  - **⌥Space（切换式）** = 按一下开始，再按一下插入
- 📥 **智能粘贴**：文字插入到任意 App 的光标处，自动恢复你原来的剪贴板
- 🪟 **录音浮窗**：实时波形 + 转写预览，带「丢弃」按钮
- 🌐 中 / 英文，可在设置切换
- 🧩 菜单栏常驻，无 Dock 图标，不打扰

## 安装与首次使用

1. 下载 [Releases](../../releases) 里的 `FlowType.app.zip`，解压，拖到「应用程序」。
2. 首次打开（菜单栏出现麦克风图标），到 **系统设置 › 隐私与安全性** 逐项授权 **FlowType**：
   - **输入监控**（监听全局热键，必需）
   - **辅助功能**（把文字粘贴到其它 App，必需）
   - **麦克风**、**语音识别**（首次录音会自动弹窗）
3. **授权后请退出并重新打开 FlowType**（热键监听在启动时注册）。
4. 把光标放进任意输入框，**长按右 Option** 说话即可。

> 本应用为自签名（ad-hoc）构建，首次打开若被 Gatekeeper 拦截，右键点 App 选「打开」。

## 从源码构建

需要 Xcode 16+ 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme FlowType -configuration Release -derivedDataPath build build
# 产物：build/Build/Products/Release/FlowType.app
```

运行测试：

```bash
xcodebuild -scheme FlowType -destination 'platform=macOS' -derivedDataPath build test
```

## 架构

纯逻辑（热键解析 / 听写状态机 / 智能粘贴 / 设置）单元测试覆盖；触系统/硬件部分（CGEventTap 全局热键、Apple 识别、合成 ⌘V、SwiftUI）走真机验证。

```
Sources/
├── Core/        热键解析 · 听写状态机 · 智能粘贴 · 设置（纯逻辑，单测）
├── Platform/    CGEventTap 热键 · Apple 识别 · 剪贴板/⌘V · 权限
├── UI/          录音浮窗 · 菜单栏 · 设置 · 权限引导
└── App/         入口 · 协调器 · AppDelegate
```

## 已知限制

- 触发键默认用**右** Option（左 Option 留给 ⌥Space 等组合键，避免冲突）。
- 长句插入的是识别器返回的当前结果，极长句可能是中间稿。
- 改设置需重启 App 生效。

## License

MIT
