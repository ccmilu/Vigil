import AppKit
import SwiftUI

enum PromisePanel {
    @MainActor
    static func show(sessionMgr: FocusSessionManager) {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = PromisePanelWindow.shared {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let win = PromisePanelWindow(sessionMgr: sessionMgr)
        PromisePanelWindow.shared = win
        win.center()
        win.makeKeyAndOrderFront(nil)
    }
}

final class PromisePanelWindow: NSPanel {
    nonisolated(unsafe) static var shared: PromisePanelWindow?

    init(sessionMgr: FocusSessionManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "What's the promise?"
        isFloatingPanel = true
        level = .floating
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        contentViewController = NSHostingController(
            rootView: PromisePanelContent(sessionMgr: sessionMgr, dismiss: { [weak self] in
                self?.close()
            })
        )
    }
    override func close() { super.close(); Self.shared = nil }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct PromisePanelContent: View {
    let sessionMgr: FocusSessionManager
    let dismiss: () -> Void

    /// 用 @AppStorage 持久化最近一次输入，下次打开面板自动预填
    @AppStorage("promise.lastInput") private var promise: String = ""
    @AppStorage("promise.lastDurationMin") private var durationMin: Int = 25
    @State private var isStarting = false
    @State private var aiSuggestion: String? = nil   // 非 nil 说明 promise 不够具体
    @State private var aiUnreachable: String? = nil  // 非 nil 说明 AI 服务连不上
    @State private var hasAskedAI = false
    @FocusState private var focused: Bool

    private let presetMinutes = [10, 15, 25, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This time I promise to...")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("例：完成季度报告初稿", text: $promise, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(2...4)
                .focused($focused)

            if let suggestion = aiSuggestion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                    Text(suggestion)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 6))
            }

            if let unreachable = aiUnreachable {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.red)
                        Text("无法连接 AI 服务")
                            .font(.callout.weight(.medium))
                    }
                    Text(unreachable)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(10)
                .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Text("时长")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(presetMinutes, id: \.self) { m in
                    Button("\(m)") { durationMin = m }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .background(
                            durationMin == m ? Color.accentColor.opacity(0.15) : .clear,
                            in: .rect(cornerRadius: 6)
                        )
                }
                Text("分钟")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                if aiSuggestion == nil && aiUnreachable == nil {
                    Button(isStarting ? "校验中…" : "Start \(durationMin) min") {
                        Task { await onStartTapped() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(promise.trimmingCharacters(in: .whitespaces).isEmpty || isStarting)
                } else if aiUnreachable != nil {
                    Button("重试") { Task { await onStartTapped() } }
                    Button("仍然开始（离线）") { Task { await actuallyStart() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("仍然开始") { Task { await actuallyStart() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isStarting)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            // NSHostingController 嵌入 NSPanel 时 @FocusState 设置过早会失效，延迟 50ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focused = true
            }
        }
        .onChange(of: promise) { _, _ in
            // 用户改了 promise 后清除上次的反问 / 错误
            aiSuggestion = nil
            aiUnreachable = nil
            hasAskedAI = false
        }
    }

    /// 第一次点 Start：先调 validatePromise 校验 + 探活
    private func onStartTapped() async {
        let trimmed = promise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isStarting = true
        defer { isStarting = false }
        aiSuggestion = nil
        aiUnreachable = nil

        switch await sessionMgr.validatePromise(trimmed) {
        case .clear:
            await actuallyStart()
        case .needsClarification(let s):
            aiSuggestion = s
            hasAskedAI = true
        case .serviceUnreachable(let msg):
            aiUnreachable = msg
        }
    }

    /// 用户改完 promise 后点"仍然开始"，跳过二次校验
    private func actuallyStart() async {
        let trimmed = promise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isStarting = true
        defer { isStarting = false }
        _ = await sessionMgr.start(promise: trimmed, durationSeconds: durationMin * 60)
        dismiss()
    }
}
