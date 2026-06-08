import XCTest
@testable import FlowType

final class SettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "flowtype.tests")!
        d.removePersistentDomain(forName: "flowtype.tests")
        return d
    }

    func test_load_returns_default_when_empty() {
        let store = SettingsStore(defaults: makeDefaults())
        XCTAssertEqual(store.settings, AppSettings.default)
    }

    func test_save_then_load_roundtrip() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        var s = AppSettings.default
        s.locale = "en-US"
        s.insertionMethod = .simulateTyping
        s.restoreClipboard = false
        store.update(s)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settings.locale, "en-US")
        XCTAssertEqual(reloaded.settings.insertionMethod, .simulateTyping)
        XCTAssertFalse(reloaded.settings.restoreClipboard)
    }

    func test_default_hotkeys() {
        XCTAssertEqual(AppSettings.default.hotkeys.pushToTalkKey, .fn)
        XCTAssertEqual(AppSettings.default.locale, "zh-CN")
        XCTAssertEqual(AppSettings.default.insertionMethod, .smartPaste)
    }
}
