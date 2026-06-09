import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator
    var body: some View {
        Text("FlowType · 就绪")
        Text("录音：长按 右Option   ·   切换：⌥Space")
            .font(.caption)
        Divider()
        Button("权限引导…") { (NSApp.delegate as? AppDelegate)?.showOnboarding() }
        SettingsLink { Text("设置…") }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
