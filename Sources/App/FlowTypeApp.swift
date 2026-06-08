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
