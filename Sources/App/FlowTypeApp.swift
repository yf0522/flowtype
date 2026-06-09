import SwiftUI
import AppKit

@main
struct FlowTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("FlowType", systemImage: "mic.fill") {
            MenuBarContent().environmentObject(coordinator)
        }

        Settings {
            SettingsView(store: SettingsStore())
        }
    }
}
