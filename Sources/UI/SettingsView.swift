import SwiftUI

struct SettingsView: View {
    @State private var settings: AppSettings
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        _settings = State(initialValue: store.settings)
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("通用", systemImage: "keyboard") }
            insertTab.tabItem { Label("插入", systemImage: "text.cursor") }
            privacyTab.tabItem { Label("隐私", systemImage: "lock") }
        }
        .frame(width: 460, height: 300)
        .onChange(of: settings) { _, new in store.update(new) }
    }

    private var generalTab: some View {
        Form {
            Picker("听写语言", selection: $settings.locale) {
                Text("中文（普通话）").tag("zh-CN")
                Text("English (US)").tag("en-US")
            }
            Toggle("开机自启动（即将推出）", isOn: $settings.launchAtLogin).disabled(true)
            Text("按住说话：fn（地球键）  ·  切换式：⌥Space").foregroundStyle(.secondary).font(.caption)
        }.padding()
    }

    private var insertTab: some View {
        Form {
            Picker("插入方式", selection: $settings.insertionMethod) {
                Text("智能粘贴").tag(InsertionMethod.smartPaste)
                Text("模拟键入").tag(InsertionMethod.simulateTyping)
                Text("辅助功能 API").tag(InsertionMethod.accessibility)
            }.disabled(true)
            Text("第一版仅支持智能粘贴。").foregroundStyle(.secondary).font(.caption)
            Toggle("粘贴后恢复剪贴板", isOn: $settings.restoreClipboard)
        }.padding()
    }

    private var privacyTab: some View {
        Form {
            Toggle("强制本地识别（绝不上云）", isOn: $settings.forceOnDevice).disabled(true)
            Text("第一版仅支持本地识别。").foregroundStyle(.secondary).font(.caption)
        }.padding()
    }
}
