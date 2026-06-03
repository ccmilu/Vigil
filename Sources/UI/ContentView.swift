import SwiftUI
import SwiftData
import KeyboardShortcuts

struct ContentView: View {
    @EnvironmentObject private var sessionMgr: FocusSessionManager
    @Environment(\.modelContext) private var ctx

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            phaseSection
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus")
                .font(.system(size: 28, weight: .bold))
            Text("点 Start Promise 或按 ⇧⌘⌥Space 弹出输入框")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Phase 区域

    @ViewBuilder
    private var phaseSection: some View {
        switch sessionMgr.phase {
        case .idle:
            startButton
            Divider()
            historyList
        case .preparing(let promise):
            preparingView(promise: promise)
        case .running(let promise, let remaining):
            runningView(promise: promise, remaining: remaining)
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
                Text("Start Promise")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
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
                Label("Running", systemImage: "circle.fill")
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
                .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 8))

            if let last = sessionMgr.lastAnalysis {
                latestAnalysisCard(last)
            }

            HStack {
                Spacer()
                Button("Stop", role: .destructive) {
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
                Text(r.fromAI ? "AI" : "复用")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.gray.opacity(0.06), in: .rect(cornerRadius: 6))
    }

    private func levelBadge(_ level: FocusLevel) -> some View {
        let (color, name): (Color, String) = {
            switch level {
            case .fully: return (.green, "fully")
            case .wandering: return (.yellow, "wandering")
            case .distracted: return (.red, "distracted")
            case .idle: return (.gray, "idle")
            }
        }()
        return Text(name)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    private func completedView(sessionID: UUID) -> some View {
        let s = try? ctx.fetch(
            FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == sessionID })
        ).first
        return VStack(alignment: .leading, spacing: 12) {
            Label("Session 完成", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.headline)
            if let s {
                ratiosBar(s)
                if let summary = s.summary {
                    Text(summary)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color.gray.opacity(0.06), in: .rect(cornerRadius: 6))
                }
            }
            Button("再来一轮") {
                PromisePanel.show(sessionMgr: sessionMgr)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
    }

    private func ratiosBar(_ s: FocusSession) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(.green).frame(maxWidth: .infinity)
                .scaleEffect(x: max(CGFloat(s.fullyRatio), 0.01), anchor: .leading)
            Rectangle().fill(.yellow).frame(maxWidth: .infinity)
                .scaleEffect(x: max(CGFloat(s.wanderingRatio), 0.01), anchor: .leading)
            Rectangle().fill(.red).frame(maxWidth: .infinity)
                .scaleEffect(x: max(CGFloat(s.distractedRatio), 0.01), anchor: .leading)
            Rectangle().fill(.gray).frame(maxWidth: .infinity)
                .scaleEffect(x: max(CGFloat(s.idleRatio), 0.01), anchor: .leading)
        }
        .frame(height: 8)
        .clipShape(.rect(cornerRadius: 4))
    }

    private func errorView(_ msg: String) -> some View {
        VStack(alignment: .leading) {
            Label("出错了", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(msg)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 6))
        }
    }

    // MARK: - History

    @Query(sort: \FocusSession.startedAt, order: .reverse)
    private var sessions: [FocusSession]

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史会话")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
            if sessions.isEmpty {
                Text("还没有会话")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            } else {
                ForEach(sessions.prefix(8), id: \.id) { s in
                    HStack {
                        Text(s.promise).lineLimit(1)
                        Spacer()
                        Text("\(s.actualDuration / 60) min")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Provider: \(DemoConfig.baseURL.absoluteString) · \(DemoConfig.model)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
