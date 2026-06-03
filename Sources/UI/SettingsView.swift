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
            StorageTab()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 500, idealHeight: 540)
    }
}

private struct StorageTab: View {
    private var screenshotsURL: URL { ScreenshotStore.rootDirectory }
    @State private var sizeBytes: Int64 = 0
    @State private var fileCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("截图与诊断日志")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前路径")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                Text(screenshotsURL.path)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08), in: .rect(cornerRadius: 6))
                Text("沙盒 App 的截图必须保存在 Container 内部目录；自定义路径需要 v0.2 用 Security-Scoped Bookmarks 处理。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(screenshotsURL)
                } label: {
                    Label("在 Finder 打开", systemImage: "folder")
                }
                Button("刷新统计") { refresh() }
                Spacer()
                Text("共 \(fileCount) 个文件 · \(formatBytes(sizeBytes))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("诊断日志（每帧决策）")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                Text("每个 session 的 diagnostic.jsonl 写在该 session 的子目录里：")
                    .font(.callout)
                Text("\(screenshotsURL.path)/<sessionUUID>/diagnostic.jsonl")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("清空所有截图", role: .destructive) {
                    clearAll()
                }
            }
        }
        .padding(20)
        .onAppear { refresh() }
    }

    private func refresh() {
        let fm = FileManager.default
        var bytes: Int64 = 0
        var count = 0
        if let enumerator = fm.enumerator(at: screenshotsURL, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                    bytes += Int64(size)
                    count += 1
                }
            }
        }
        sizeBytes = bytes
        fileCount = count
    }

    private func clearAll() {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: screenshotsURL, includingPropertiesForKeys: nil) {
            for url in items {
                try? fm.removeItem(at: url)
            }
        }
        refresh()
    }

    private func formatBytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: b)
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
