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

        Settings {
            SettingsView(store: SettingsStore())
        }
        Window("欢迎使用 FlowType", id: "permissions") {
            PermissionsView()
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
