import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator
    var body: some View {
        Text("FlowType · 就绪")
        Text("录音：长按 右Option   ·   切换：⌥Space   ·   回车确定")
            .font(.caption)
        Divider()
        Button("权限引导…") { coordinator.showOnboardingWindow() }
        Button("设置…") { coordinator.showSettingsWindow() }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
