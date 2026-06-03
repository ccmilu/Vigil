import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @StateObject private var store = ProviderStore()

    var body: some View {
        TabView {
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            ProvidersTab(store: store)
                .tabItem { Label("AI", systemImage: "brain") }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 500, idealHeight: 540)
    }
}

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(for: .startPromise) {
                Text("起 Promise 面板")
            }
        }
        .padding(20)
    }
}

private struct ProvidersTab: View {
    @ObservedObject var store: ProviderStore
    @State private var editing: AIProvider?
    @State private var testResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Providers")
                    .font(.headline)
                Spacer()
                Button {
                    let p = AIProvider(
                        nickname: "新建 Provider",
                        baseURL: "http://localhost:1234/v1",
                        model: "qwen2.5-vl-7b-instruct",
                        apiKey: ""
                    )
                    store.add(p)
                    editing = p
                } label: {
                    Label("新增", systemImage: "plus")
                }
            }

            providerList

            if let editing = editing {
                Divider()
                ProviderEditor(
                    provider: editing,
                    onSave: { updated in
                        store.update(updated)
                        self.editing = updated
                    },
                    onDelete: {
                        store.remove(editing)
                        self.editing = nil
                    },
                    onTest: { p in
                        testResult = "测试中…"
                        Task {
                            testResult = await testConnectivity(p)
                        }
                    }
                )
                if let result = testResult {
                    Text(result)
                        .font(.callout)
                        .foregroundStyle(result.contains("✓") ? .green : .red)
                        .padding(.top, 4)
                }
            }
        }
        .padding(20)
    }

    private var providerList: some View {
        VStack(spacing: 4) {
            ForEach(store.providers) { p in
                providerRow(p)
            }
        }
    }

    private func providerRow(_ p: AIProvider) -> some View {
        let isSelected = store.selectedID == p.id
        let isEditing = editing?.id == p.id
        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .onTapGesture { store.select(p.id) }
            VStack(alignment: .leading, spacing: 2) {
                Text(p.nickname).font(.callout)
                Text("\(p.family.displayName) · \(p.model)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLocal(p) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.green)
                    .help("本地 / 局域网 Provider，不出公网")
            }
            Button("编辑") { editing = p }
                .buttonStyle(.borderless)
        }
        .padding(8)
        .background(isEditing ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(.rect(cornerRadius: 6))
    }

    private func isLocal(_ p: AIProvider) -> Bool {
        guard let host = URL(string: p.baseURL)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1"
            || host.hasPrefix("192.168.") || host.hasPrefix("10.")
            || host.hasSuffix(".local")
    }

    private func testConnectivity(_ p: AIProvider) async -> String {
        do {
            _ = try await p.makeService().analyzeTask("ping connection test")
            return "✓ 连通；模型 \(p.model) 响应正常"
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }
}

private struct ProviderEditor: View {
    @State var provider: AIProvider
    let onSave: (AIProvider) -> Void
    let onDelete: () -> Void
    let onTest: (AIProvider) -> Void

    var body: some View {
        Form {
            TextField("昵称", text: $provider.nickname)
            TextField("Base URL", text: $provider.baseURL)
                .textContentType(.URL)
                .autocorrectionDisabled()
            TextField("Model", text: $provider.model)
                .autocorrectionDisabled()
            SecureField("API Key", text: $provider.apiKey)
        }
        .padding(.top, 4)
        .onChange(of: provider) { _, new in onSave(new) }

        HStack {
            Button("测试连通性") { onTest(provider) }
            Spacer()
            Button("删除", role: .destructive) { onDelete() }
        }
    }
}
