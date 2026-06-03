import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            shortcuts
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            provider
                .tabItem { Label("AI", systemImage: "brain") }
        }
        .padding(20)
    }

    private var shortcuts: some View {
        Form {
            KeyboardShortcuts.Recorder(for: .startPromise) {
                Text("起 Promise 面板")
            }
        }
    }

    private var provider: some View {
        Form {
            LabeledContent("Base URL", value: DemoConfig.baseURL.absoluteString)
            LabeledContent("Model", value: DemoConfig.model)
            Text("Demo 阶段写在 DemoConfig.swift；后续支持设置页编辑 + Keychain 存 Key。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 480, height: 320)
}
