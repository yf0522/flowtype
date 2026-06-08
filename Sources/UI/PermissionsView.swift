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
