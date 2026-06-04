import SwiftUI
import SwiftData
import KeyboardShortcuts

struct ContentView: View {
    @EnvironmentObject private var sessionMgr: FocusSessionManager
    @Environment(\.modelContext) private var ctx

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                phaseSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)   // 让出 traffic lights 浮空的位置
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            // 顶部 scroll edge effect：从窗口顶部开始（与红绿灯所在水平区域平行），
            // 向下渐变淡出到透明。mask 顶部不到满 alpha，让整体保持微妙。
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 50)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.8), location: 0.0),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .onAppear {
            sessionMgr.onBreakFinished = {
                PromisePanel.show(sessionMgr: sessionMgr)
            }
        }
    }

    // MARK: - Header

    /// 快捷键提示文本——读 KeyboardShortcuts 当前设置，用户改了立刻反映。
    /// 用 @State 缓存，应用激活时刷新。
    @State private var shortcutHint: String = ContentView.currentShortcutHint()

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vigil")
                .font(.system(size: 28, weight: .bold))
            Text(shortcutHint)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            shortcutHint = Self.currentShortcutHint()
        }
    }

    private static func currentShortcutHint() -> String {
        if let s = KeyboardShortcuts.getShortcut(for: .startPromise) {
            return "点「开始专注」或按 \(s) 弹出输入框"
        }
        return "点「开始专注」弹出输入框（可在设置里绑快捷键）"
    }

    // MARK: - Phase 区域

    @ViewBuilder
    private var phaseSection: some View {
        switch sessionMgr.phase {
        case .idle:
            StreakCard()
            startButton
            Divider()
            historyList
        case .preparing(let promise):
            preparingView(promise: promise)
        case .running(let promise, let remaining):
            runningView(promise: promise, remaining: remaining)
        case .resting(let remaining):
            restingView(remaining: remaining)
        case .analyzing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在生成复盘…")
            }
            .padding(.vertical, 16)
        case .completed(let id):
            completedView(sessionID: id)
        case .failed(let msg):
            errorView(msg)
        }
    }

    private var startButton: some View {
        Button {
            PromisePanel.show(sessionMgr: sessionMgr)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "target")
                Text("开始专注")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .glassButtonStyle(prominent: true)
        .controlSize(.large)
        .keyboardShortcut("n", modifiers: [.command])
    }

    private func preparingView(promise: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading) {
                Text("准备中…")
                    .font(.callout)
                Text(promise).foregroundStyle(.secondary).font(.body)
            }
        }
    }

    private func runningView(promise: String, remaining: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("进行中", systemImage: "circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                Spacer()
                Text(formatTime(remaining))
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
            }
            Text(promise)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let last = sessionMgr.lastAnalysis {
                latestAnalysisCard(last)
            }

            HStack {
                Spacer()
                Button("停止", role: .destructive) {
                    Task { await sessionMgr.stopManually(reason: nil) }
                }
                .controlSize(.large)
            }
        }
    }

    private func latestAnalysisCard(_ r: AnalysisRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                levelBadge(r.level)
                Text(r.reasoning.isEmpty ? "(无 AI 推理)" : r.reasoning)
                    .font(.callout)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Text("\(r.frontAppName)")
                if let d = r.dhashDistance {
                    Text("dHash=\(d)")
                }
                if r.fromAI {
                    Label("AI 含截图", systemImage: "camera.fill")
                        .help("本帧已把截图发给 AI；要看模型实际收到的 prompt，开启 Settings → Debug")
                } else {
                    Text("复用")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(10)
    }

    private func levelBadge(_ level: FocusLevel) -> some View {
        let color: Color = {
            switch level {
            case .fully:      return .green
            case .wandering:  return .yellow
            case .distracted: return .red
            case .idle:       return .gray
            }
        }()
        return Text(level.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    private func completedView(sessionID: UUID) -> some View {
        let s = try? ctx.fetch(
            FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == sessionID })
        ).first
        return VStack(alignment: .leading, spacing: 14) {
            Label("专注完成", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.headline)
            if let s {
                ratiosBar(s)
                if let summary = s.summary {
                    ScrollView {
                        Text(summary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 140)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("接下来")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button {
                        PromisePanel.show(sessionMgr: sessionMgr)
                    } label: {
                        Label("再来一轮", systemImage: "play.circle.fill")
                    }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)

                    Menu {
                        Button("5 分钟") { sessionMgr.startBreak(durationSeconds: 5 * 60) }
                        Button("10 分钟") { sessionMgr.startBreak(durationSeconds: 10 * 60) }
                        Button("15 分钟") { sessionMgr.startBreak(durationSeconds: 15 * 60) }
                    } label: {
                        Label("休息一下", systemImage: "cup.and.saucer")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.large)

                    Button {
                        sessionMgr.reset()
                    } label: {
                        Label("返回首页", systemImage: "house")
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    @State private var confirmAbortBreak = false

    private func restingView(remaining: TimeInterval) -> some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("休息中")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(formatTime(remaining))
                .font(.system(size: 56, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            Text("期间不会监督屏幕。到时通知你并弹出下一轮承诺面板。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("提前结束休息") {
                confirmAbortBreak = true
            }
            .controlSize(.regular)
            .glassButtonStyle()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "提前结束休息？",
            isPresented: $confirmAbortBreak,
            titleVisibility: .visible
        ) {
            Button("结束休息", role: .destructive) {
                sessionMgr.abortBreak()
            }
            Button("继续休息", role: .cancel) {}
        } message: {
            Text("休息也是工作的一部分。要不要再坚持几分钟？")
        }
    }

    private func ratiosBar(_ s: FocusSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StackedRatioBar(
                segments: [
                    (.green, s.fullyRatio),
                    (.yellow, s.wanderingRatio),
                    (.red, s.distractedRatio),
                    (.gray, s.idleRatio)
                ],
                height: 12
            )
            HStack(spacing: 14) {
                ratioLegend(.green, "专注", s.fullyRatio)
                ratioLegend(.yellow, "走神", s.wanderingRatio)
                ratioLegend(.red, "分心", s.distractedRatio)
                ratioLegend(.gray, "空闲", s.idleRatio)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func ratioLegend(_ color: Color, _ label: String, _ ratio: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text("\(label) \(Int(ratio * 100))%")
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(alignment: .leading) {
            Label("出错了", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(msg)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .foregroundStyle(.red)
        }
    }

    // MARK: - History

    @Query(sort: \FocusSession.startedAt, order: .reverse)
    private var sessions: [FocusSession]

    @State private var selectedSession: FocusSession?
    @State private var historyExpanded: Bool = false

    /// 默认折叠时最多显示几条历史
    private static let historyCollapsedLimit = 8

    private var visibleSessions: [FocusSession] {
        if historyExpanded {
            return Array(sessions)
        }
        return Array(sessions.prefix(Self.historyCollapsedLimit))
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("历史会话")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                Spacer()
                if !sessions.isEmpty {
                    Text("共 \(sessions.count) 条")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if sessions.isEmpty {
                Text("还没有会话")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            } else {
                ForEach(visibleSessions, id: \.id) { s in
                    Button {
                        selectedSession = s
                    } label: {
                        HStack {
                            Text(s.promise).lineLimit(1).foregroundStyle(.primary)
                            Spacer()
                            Text("\(s.actualDuration / 60) min")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.tertiary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if sessions.count > Self.historyCollapsedLimit {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            historyExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                            Text(historyExpanded
                                 ? "收起"
                                 : "展开全部（还有 \(sessions.count - Self.historyCollapsedLimit) 条）")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedSession) { s in
            SessionDetailView(session: s) {
                selectedSession = nil
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
