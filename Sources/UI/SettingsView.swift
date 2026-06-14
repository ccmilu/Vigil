import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var store: ProviderStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            ProvidersTab(store: store)
                .tabItem { Label("AI", systemImage: "brain") }
            CaptureTab(settings: settings)
                .tabItem { Label("截屏", systemImage: "camera.viewfinder") }
            AlertsTab(settings: settings)
                .tabItem { Label("提醒", systemImage: "bell.badge") }
            SoundTab()
                .tabItem { Label("声音", systemImage: "speaker.wave.2") }
            DebugTab(settings: settings)
                .tabItem { Label("调试", systemImage: "ladybug") }
        }
        .frame(
            minWidth: 540, idealWidth: 580, maxWidth: 620,
            minHeight: 460, idealHeight: 540, maxHeight: 720
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

/// 通用设置：语言 / 快捷键 / 自动更新 / 关于。
///
/// 「快捷键」和「关于」原本是独立的 tab，2026-06 合并进通用以减少 Tab 数量。
private struct GeneralTab: View {
    @ObservedObject private var localizer = LocalizationManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updateService = UpdateService.shared

    var body: some View {
        Form {
            // 关于放在最顶——打开设置时第一眼就是项目身份 + GitHub 引导
            AboutSection()
            LanguageSection(localizer: localizer)
            ShortcutsSection()
            UpdatesSection(settings: settings, updateService: updateService)
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
    }
}

/// 界面语言（同时也是 AI 回复语言）。
/// 用户切换后：
/// - SwiftUI 视图通过 LocalizationManager 的 @Published 触发 redraw
/// - 顶层 environment(\.locale) 也跟随刷新（FocusApp 里注入）
/// - 菜单栏 / 通知下次构造时拿新 bundle（current AppKit code 都现读 L()，自动跟）
/// - 进行中的 session 仍用 start 时快照的语言（避免 AI 输出语言突变）
private struct LanguageSection: View {
    @ObservedObject var localizer: LocalizationManager

    var body: some View {
        Section("界面语言") {
            Picker(selection: Binding(
                get: { localizer.language },
                set: { localizer.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    // displayName 故意不本地化（每种语言显示自己的名字），让用户在任何
                    // 当前语言下都能识别可选项
                    Text(verbatim: lang.displayName).tag(lang)
                }
            } label: {
                Text("语言")
            }
            .pickerStyle(.inline)

            Text("界面文案与 AI 反馈都会跟随这个语言。默认跟随系统设置。\n切换后菜单栏与通知会在下次构造时刷新；主界面立即生效。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 全局快捷键：⇧⌘⌥Space 打开承诺面板。
/// KeyboardShortcuts.Recorder 自带录制 UI + 默认值还原。
private struct ShortcutsSection: View {
    var body: some View {
        Section("全局快捷键") {
            KeyboardShortcuts.Recorder(for: .startPromise) {
                Text("打开承诺面板")
            }
            Text("默认 ⇧⌘⌥Space。⌘⌥Space 默认被 Spotlight 占用。点击右侧按钮可重新录制。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 自动更新：开关 + 当前版本 + 上次检查时间 + 立即检查按钮。
/// 启用时 App 启动 5s 后跑一次，并每 24h 重跑。
private struct UpdatesSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateService: UpdateService
    @State private var nowTick = Date()

    /// 每分钟刷一次 "上次检查 xx 分钟前" 的相对时间显示。
    private let tickTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("自动更新") {
            Toggle("自动检查更新", isOn: $settings.autoCheckUpdates)
            Text("启用后，Vigil 在启动 5 秒后检查一次，并每 24 小时自动检查新版本。\n更新通过 GitHub Releases 推送，不会上传任何用户数据。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LabeledContent("当前版本") {
                Text(updateService.currentVersion().description)
                    .font(.system(.callout, design: .monospaced))
            }
            LabeledContent("上次检查") {
                Text(lastCheckText)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            if let statusText {
                Label(statusText, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            HStack {
                Spacer()
                Button {
                    updateService.manualCheck()
                } label: {
                    if isChecking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在检查…")
                        }
                    } else {
                        Label("立即检查更新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isChecking)
            }
        }
        .onReceive(tickTimer) { nowTick = $0 }
    }

    private var isChecking: Bool {
        if case .checking = updateService.state { return true }
        return false
    }

    private var lastCheckText: String {
        _ = nowTick   // 触发依赖：Timer 的 Date 推送让 lastCheckText 重算
        guard let date = updateService.lastCheckedAt else {
            return L("从未")
        }
        let f = RelativeDateTimeFormatter()
        // 显式用用户在 Settings 里选的语言，避免回退到 Locale.current
        f.locale = LocalizationManager.shared.language.locale
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// 返回 LocalizedStringKey 以让 Label 走 SwiftUI 的自动本地化路径（key + 插值 → xcstrings 抽取）。
    private var statusText: LocalizedStringKey? {
        switch updateService.state {
        case .idle, .checking: return nil
        case .upToDate: return "已是最新版本"
        case .available(let info): return "发现新版本 \(info.version.description)，将弹出更新窗口"
        case .error(let msg, _): return "检查失败：\(msg)"
        }
    }

    private var statusIcon: String {
        switch updateService.state {
        case .available: return "sparkles"
        case .error: return "exclamationmark.triangle"
        case .upToDate: return "checkmark.circle"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch updateService.state {
        case .available: return .accentColor
        case .error: return .red
        case .upToDate: return .secondary
        default: return .secondary
        }
    }
}

/// 关于 Vigil：App 图标 + 一句话简介 + GitHub 按钮 + 求 star 引导。
private struct AboutSection: View {
    static let githubURL = URL(string: "https://github.com/ccmilu/Vigil")!

    var body: some View {
        Section("关于 Vigil") {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vigil")
                        .font(.title3.weight(.semibold))
                    Text("AI 守护你的专注。写下承诺，AI 实时分析屏幕，温柔提醒你回到正事上。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            HStack {
                Button {
                    NSWorkspace.shared.open(Self.githubURL)
                } label: {
                    Label("打开 GitHub 仓库", systemImage: "globe")
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(Self.githubURL)
                } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
            }

            Text("Vigil 是个人维护的开源项目。如果它对你有帮助，请点一下 Star ❤️——这是对独立开发者最大的鼓励，也能让更多人发现它。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

            // "存储"从独立 tab 合并进调试（2026-06）
            StorageSection()
        }
        .formStyle(.grouped)
        .alert("已重置引导", isPresented: $showRestartAlert) {
            Button("好") {}
        } message: {
            Text("关闭主窗口（Cmd+W）→ 从 Dock 重新点击 Vigil 图标，引导会再次出现。")
        }
    }
}

/// 截图与诊断日志的存储管理。原 StorageTab，2026-06 合并到调试 tab 的最后一个 Section。
private struct StorageSection: View {
    private var screenshotsURL: URL { ScreenshotStore.rootDirectory }
    @State private var sizeBytes: Int64 = 0
    @State private var fileCount: Int = 0
    @State private var showClearConfirm = false

    var body: some View {
        Section("截图与诊断日志") {
            VStack(alignment: .leading, spacing: 6) {
                Text("当前路径")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                Text(screenshotsURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("沙盒 App 的截图只能保存在 Container 内部目录；自定义路径需要 Security-Scoped Bookmark（v0.2 计划）。")
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("清空所有截图", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
        .onAppear { refresh() }
        .confirmationDialog(
            "确认清空所有截图与诊断日志？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("全部删除", role: .destructive) { clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销。历史 session 的截图与 diagnostic.jsonl 都会被删除。")
        }
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
                        testResult = L("连通测试中…")
                        Task { testResult = await testConnectivity(p) }
                    },
                    onTestVision: { p in
                        testResult = L("视觉测试中（约 5-15s）…")
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
            return L("✓ 连通；模型 %@ 响应正常", args: p.model as CVarArg)
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }

    private func testVision(_ p: AIProvider) async -> String {
        guard let svc = p.makeService() as? OpenAICompatibleService else {
            return L("✗ 当前 provider 不支持视觉测试")
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
            // "没有看到图片" / "看不到" 是 describeImage 的固定中文 fallback 文案，
            // 与界面语言无关——这里只是用来识别"模型说看不到图"。
            if trimmed.contains("没有看到图片") || trimmed.contains("看不到") || trimmed.lowercased().contains("can't see") {
                return L("✗ 模型回复看不到图片——可能不是多模态，或没加载视觉权重。\n原回复：%@", args: trimmed as CVarArg)
            }
            return L("✓ 模型确实收到了图片，描述：\n%@", args: trimmed as CVarArg)
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
