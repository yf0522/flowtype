import AppKit
import SwiftUI

/// 负责首次启动时自动弹出权限引导窗口，并提供再次打开的入口。
/// 菜单栏常驻（LSUIElement）应用无 Dock/窗口，首启没有任何可见反馈，
/// 故在 applicationDidFinishLaunching 主动展示引导窗，避免用户以为"没打开"。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?
    private let onboardedKey = "flowtype.hasOnboarded.v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !UserDefaults.standard.bool(forKey: onboardedKey) {
            showOnboarding()
            UserDefaults.standard.set(true, forKey: onboardedKey)
        }
    }

    /// 显示权限引导窗口（首启自动调用，也可从菜单手动调用）。
    func showOnboarding() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: PermissionsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "欢迎使用 FlowType"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
