import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var store: ProviderStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            ProvidersTab(store: store)
                .tabItem { Label("AI", systemImage: "brain") }
            CaptureTab(settings: settings)
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            SoundTab()
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            StorageTab()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
            DebugTab(settings: settings)
                .tabItem { Label("Debug", systemImage: "ladybug") }
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 520, idealHeight: 580)
    }
}

private struct CaptureTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("画面变化阈值（dHash 汉明距离）") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.dhashThreshold) },
                            set: { settings.dhashThreshold = Int($0) }
                        ),
                        in: 0...100, step: 5
                    )
                    Text("\(settings.dhashThreshold)")
                        .frame(width: 36, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                Text("256-bit 下经验值：15~30 微小变化，30~60 明显变化，60+ 大变化。默认 30。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("时间兜底（即使画面没变也至少 X 秒调一次 AI）") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxAIIntervalSec) },
                            set: { settings.maxAIIntervalSec = Int($0) }
                        ),
                        in: 10...120, step: 5
                    )
                    Text("\(settings.maxAIIntervalSec)s")
                        .frame(width: 48, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                Text("默认 30s。设小耗 token 多但更敏感；设大省 token。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("空闲判定（用户无输入多久算 idle）") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.idleThresholdSec) },
                            set: { settings.idleThresholdSec = Int($0) }
                        ),
                        in: 30...300, step: 10
                    )
                    Text("\(settings.idleThresholdSec)s")
                        .frame(width: 48, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                Text("默认 60s。空闲时段标 idle 且不调 AI。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("AI 调用熔断（单次最长等待）") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.aiHardTimeoutSec) },
                            set: { settings.aiHardTimeoutSec = Int($0) }
                        ),
                        in: 10...90, step: 5
                    )
                    Text("\(settings.aiHardTimeoutSec)s")
                        .frame(width: 48, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                Text("默认 30s。超过此时长强制取消，复用上次 level 入库。设短=容错激进、占用低；设长=容忍网络波动 / 大模型慢。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
    }
}

private struct SoundTab: View {
    @State private var enabled = SoundPlayer.shared.isEnabled
    @State private var volume = SoundPlayer.shared.volume
    @State private var startName = SoundPlayer.shared.currentName(for: .start)
    @State private var distractName = SoundPlayer.shared.currentName(for: .distract)
    @State private var completeName = SoundPlayer.shared.currentName(for: .complete)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Section {
                    Toggle("启用提示音", isOn: $enabled)
                        .onChange(of: enabled) { _, v in SoundPlayer.shared.isEnabled = v }
                    HStack {
                        Text("音量").frame(width: 60, alignment: .leading)
                        Slider(value: $volume, in: 0...1)
                            .onChange(of: volume) { _, v in SoundPlayer.shared.volume = v }
                        Text("\(Int(volume * 100))%")
                            .frame(width: 44, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .padding(12)

                Text("鼠标悬停某个音名即可试听，点击选中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                soundPickerRow(label: "开始 session", cue: .start, selected: $startName)
                soundPickerRow(label: "检测到分心", cue: .distract, selected: $distractName)
                soundPickerRow(label: "session 完成", cue: .complete, selected: $completeName)
            }
            .padding(20)
        }
    }

    private func soundPickerRow(label: String, cue: SoundPlayer.Cue, selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.callout.weight(.medium))
                Spacer()
                Text("当前：\(selected.wrappedValue)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SoundPlayer.availableSystemSounds, id: \.self) { name in
                        SoundChip(
                            name: name,
                            isSelected: selected.wrappedValue == name,
                            onSelect: {
                                selected.wrappedValue = name
                                SoundPlayer.shared.setSound(cue, name: name)
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
    }
}

private struct SoundChip: View {
    let name: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(name)
                .font(.caption)
        }
        .glassButtonStyle(prominent: isSelected)
        .controlSize(.small)
        .onHover { hovering in
            if hovering {
                HoverSoundPreview.play(name)
            }
        }
    }
}

private struct DebugTab: View {
    @ObservedObject var settings: AppSettings
    @AppStorage("onboarding.completed") private var onboardingDone = false
    @State private var showRestartAlert = false

    var body: some View {
        Form {
            Section {
                Toggle("记录完整 prompt 进出", isOn: $settings.debugEnabled)
                Text("开启后，每个 session 目录下会生成 prompts.jsonl，记录每次 AI 调用的 system / user prompt、是否带图、完整响应、耗时。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("查看日志") {
                Button {
                    NSWorkspace.shared.open(ScreenshotStore.rootDirectory)
                } label: {
                    Label("打开 sessions 目录", systemImage: "folder")
                }
                Text("各 session 目录里：\n• diagnostic.jsonl — 每帧决策（dHash 距离、是否调 AI、level）\n• prompts.jsonl — 完整 prompt（仅 debug 开启）\n• *.jpg — 调 AI 时落盘的截图")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("重置") {
                Button {
                    onboardingDone = false
                    showRestartAlert = true
                } label: {
                    Label("重新查看引导流程", systemImage: "arrow.counterclockwise")
                }
                Text("点击后关闭 Focus 主窗口再重新打开（Cmd+W → Dock 点击图标），引导流程会再次出现。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("已重置引导", isPresented: $showRestartAlert) {
            Button("好") {}
        } message: {
            Text("关闭主窗口（Cmd+W）→ 从 Dock 重新点击 Focus 图标，引导会再次出现。")
        }
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

struct ProvidersTab: View {
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
                    onDone: {
                        self.editing = nil
                        self.testResult = nil
                    },
                    onDelete: {
                        store.remove(editing)
                        self.editing = nil
                        self.testResult = nil
                    },
                    onTest: { p in
                        testResult = "连通测试中…"
                        Task { testResult = await testConnectivity(p) }
                    },
                    onTestVision: { p in
                        testResult = "视觉测试中（约 5-15s）…"
                        Task { testResult = await testVision(p) }
                    }
                )
                // 关键：editing 变化时强制重建 ProviderEditor 内部 @State
                .id(editing.id)
                if let result = testResult {
                    ScrollView {
                        Text(result)
                            .font(.callout)
                            .foregroundStyle(result.contains("✓") ? .green : .red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 100)
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
        .background(isEditing ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
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

    private func testVision(_ p: AIProvider) async -> String {
        guard let svc = p.makeService() as? OpenAICompatibleService else {
            return "✗ 当前 provider 不支持视觉测试"
        }
        do {
            let mgr = ScreenCaptureManager()
            let img = try await mgr.captureMainDisplay()
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("focus-vision-test.jpg")
            try mgr.encodeAndWrite(img, to: tempURL)
            let jpeg = try Data(contentsOf: tempURL)
            try? FileManager.default.removeItem(at: tempURL)

            let answer = try await svc.describeImage(jpeg)
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("没有看到图片") || trimmed.contains("看不到") {
                return "✗ 模型回复看不到图片——可能不是多模态，或没加载视觉权重。\n原回复：\(trimmed)"
            }
            return "✓ 模型确实收到了图片，描述：\n\(trimmed)"
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }
}

private struct ProviderEditor: View {
    @State var provider: AIProvider
    let onSave: (AIProvider) -> Void
    let onDone: () -> Void
    let onDelete: () -> Void
    let onTest: (AIProvider) -> Void
    let onTestVision: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("编辑 Provider")
                    .font(.headline)
                Spacer()
                Button("完成") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            Form {
                TextField("昵称", text: $provider.nickname)
                TextField("Base URL", text: $provider.baseURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                TextField("Model", text: $provider.model)
                    .autocorrectionDisabled()
                SecureField("API Key", text: $provider.apiKey)
            }
            .onChange(of: provider) { _, new in onSave(new) }

            HStack(spacing: 8) {
                Button("测试连通性") { onTest(provider) }
                Button("测试视觉") { onTestVision(provider) }
                    .help("截当前屏 + 让模型描述，验证模型是否真有视觉能力")
                Spacer()
                Button("删除", role: .destructive) { onDelete() }
            }
        }
        .padding(.top, 4)
    }
}
