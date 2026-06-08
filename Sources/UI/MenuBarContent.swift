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
