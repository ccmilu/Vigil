import AppKit
import SwiftUI

/// 按 ⇧⌘⌥Space 或主窗口按钮触发的"起 session"面板。
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
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

    @State private var promise: String = ""
    @State private var durationMin: Int = 25
    @State private var isStarting = false
    @FocusState private var focused: Bool

    private let presetMinutes = [10, 15, 25, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("This time I promise to...")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("写一份周报", text: $promise, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(2...4)
                .focused($focused)

            HStack(spacing: 8) {
                Text("时长")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(presetMinutes, id: \.self) { m in
                    Button("\(m)") {
                        durationMin = m
                    }
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
                Button("Start \(durationMin) min") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(promise.trimmingCharacters(in: .whitespaces).isEmpty || isStarting)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { focused = true }
    }

    private func submit() async {
        let trimmed = promise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isStarting = true
        defer { isStarting = false }
        _ = await sessionMgr.start(promise: trimmed, durationSeconds: durationMin * 60)
        dismiss()
    }
}
