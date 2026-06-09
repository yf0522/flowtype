import SwiftUI
import AppKit

@main
struct FlowTypeApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("FlowType", systemImage: "mic.fill") {
            MenuBarContent().environmentObject(coordinator)
        }
    }
}
