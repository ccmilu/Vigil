import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var store: ProviderStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            ShortcutsTab()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            ProvidersTab(store: store)
                .tabItem { Label("AI", systemImage: "brain") }
            CaptureTab(settings: settings)
                .tabItem { Label("截屏", systemImage: "camera.viewfinder") }
            AlertsTab(settings: settings)
                .tabItem { Label("提醒", systemImage: "bell.badge") }
            SoundTab()
                .tabItem { Label("声音", systemImage: "speaker.wave.2") }
            StorageTab()
                .tabItem { Label("存储", systemImage: "externaldrive") }
            DebugTab(settings: settings)
                .tabItem { Label("调试", systemImage: "ladybug") }
        }
        .frame(
            minWidth: 520, idealWidth: 560, maxWidth: 600,
            minHeight: 440, idealHeight: 480, maxHeight: 640
        )
        // 在 tab bar 区域叠一层 withinWindow vibrancy，模糊同窗口内
        // 滚动到 tab bar 后面的内容（控制中心同款）。
        // SwiftUI 的 .thinMaterial 用的是 behindWindow（模糊桌面），
        // Settings 下面没桌面所以显示成白底。这里手写 NSVisualEffectView 走 withinWindow。
        // tab bar 是 NSToolbar 在 AppKit 更上层，overlay 不会盖住它。
        .overlay(alignment: .top) {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                .frame(height: 88)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }
}

/// withinWindow vibrancy 包装：模糊同窗口内的内容（控制中心式效果）。
private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private struct AlertsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("分心持续提醒") {
                Toggle("分心未回时每隔一段时间再弹一次", isOn: $settings.distractIntervalEnabled)
                Text(verbatim: "首次跳变到分心一定会弹遮罩；关掉此项后，持续分心不再额外提醒，直到状态切换。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if settings.distractIntervalEnabled {
                    HStack {
                        Text("间隔")
                            .frame(width: 40, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(settings.distractIntervalSec) },
                                set: { settings.distractIntervalSec = Int($0) }
                            ),
                            in: 10...300, step: 10
                        )
                        Text("\(settings.distractIntervalSec)s")
                            .frame(width: 48, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("从遮罩关闭瞬间起计算。默认 30s。第 3 次起遮罩多一个 \"AI 可能误判，本次不再提醒\" 按钮。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("长时间不在电脑前（idle）") {
                Toggle("idle 持续过久时通过刘海岛 + 声音召回", isOn: $settings.idleAlertEnabled)
                Text(verbatim: "用户长时间无键鼠输入 = 可能离开电脑去玩手机。靠声音提醒（不看屏幕）。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if settings.idleAlertEnabled {
                    HStack {
                        Text("阈值")
                            .frame(width: 40, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(settings.idleAlertThresholdSec) },
                                set: { settings.idleAlertThresholdSec = Int($0) }
                            ),
                            in: 30...600, step: 30
                        )
                        Text("\(settings.idleAlertThresholdSec)s")
                            .frame(width: 48, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("idle 持续多久才开始提醒。默认 120s。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("重弹")
                            .frame(width: 40, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(settings.idleAlertRepeatSec) },
                                set: { settings.idleAlertRepeatSec = Int($0) }
                            ),
                            in: 10...120, step: 5
                        )
                        Text("\(settings.idleAlertRepeatSec)s")
                            .frame(width: 48, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("idle 持续期间每隔多少秒再播放一次提示音。默认 30s。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("持续走神（wandering）") {
                Toggle("wandering 连续过久时弹刘海软提醒", isOn: $settings.wanderingAlertEnabled)
                Text(verbatim: "比 distract 弱：黄色描边 + 12s 自动收回，不发声、不弹遮罩。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if settings.wanderingAlertEnabled {
                    HStack {
                        Text("阈值")
                            .frame(width: 40, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(settings.wanderingAlertThresholdSec) },
                                set: { settings.wanderingAlertThresholdSec = Int($0) }
                            ),
                            in: 30...600, step: 30
                        )
                        Text("\(settings.wanderingAlertThresholdSec)s")
                            .frame(width: 48, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("连续 wandering 多久后触发首次提醒。默认 120s。回到 fully 后计时重置。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("间隔")
                            .frame(width: 40, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(settings.wanderingAlertIntervalSec) },
                                set: { settings.wanderingAlertIntervalSec = Int($0) }
                            ),
                            in: 20...300, step: 10
                        )
                        Text("\(settings.wanderingAlertIntervalSec)s")
                            .frame(width: 48, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("首次提醒后，wandering 仍持续时每隔多少秒重弹一次。默认 60s。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
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
                Text(verbatim: "256-bit 下经验值：15~30 微小变化，30~60 明显变化，60+ 大变化。默认 30。")
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

                soundPickerRow(label: "开始专注", cue: .start, selected: $startName)
                soundPickerRow(label: "检测到分心", cue: .distract, selected: $distractName)
                soundPickerRow(label: "专注完成", cue: .complete, selected: $completeName)
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
            // 横向滚动：两侧渐变 fade 暗示"还有内容"，滚动条独占底部一行
            ScrollView(.horizontal) {
                // VStack + Spacer 强制把 chip 钉在顶，下方留 22pt 给 indicator
                VStack(alignment: .leading, spacing: 0) {
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
                    .padding(.horizontal, 16)
                    Spacer(minLength: 5)
                }
            }
            .scrollIndicators(.visible, axes: .horizontal)
            .frame(height: 40)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.10),
                        .init(color: .black, location: 0.90),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        }
        .padding(12)
    }
}

private struct SoundChip: View {
    let name: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        // 横向并排多个 chip 避开嵌套玻璃造成的奇怪阴影：
        // 选中用 .borderedProminent + 强调色；未选 .bordered。视觉差异够，且无玻璃叠加。
        Group {
            if isSelected {
                Button(action: onSelect) { Text(name).font(.caption) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: onSelect) { Text(name).font(.caption) }
                    .buttonStyle(.bordered)
            }
        }
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
                Text("点击后关闭 Vigil 主窗口再重新打开（Cmd+W → Dock 点击图标），引导流程会再次出现。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("已重置引导", isPresented: $showRestartAlert) {
            Button("好") {}
        } message: {
            Text("关闭主窗口（Cmd+W）→ 从 Dock 重新点击 Vigil 图标，引导会再次出现。")
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
                Text("打开专注面板")
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
                Text("AI 服务")
                    .font(.headline)
                Spacer()
                Button {
                    let p = AIProvider(
                        nickname: "新建服务",
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
                    .help("本地 / 局域网服务，不出公网")
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
                Text("编辑服务")
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
