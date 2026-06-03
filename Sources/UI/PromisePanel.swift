import AppKit
import SwiftUI

/// 一个轻量浮动面板：按 ⌘⌥Space 出现，输入承诺后回车提交。
/// 这是后续做"专注会话起跑面板"的雏形。
enum PromisePanel {

    @MainActor
    static func show(sessionVM: SessionViewModel) {
        if let existing = PromisePanelWindow.shared {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let win = PromisePanelWindow(sessionVM: sessionVM)
        PromisePanelWindow.shared = win
        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }
}

final class PromisePanelWindow: NSPanel {
    nonisolated(unsafe) static var shared: PromisePanelWindow?

    init(sessionVM: SessionViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "What's the promise?"
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let host = NSHostingController(
            rootView: PromisePanelContent(sessionVM: sessionVM, dismiss: { [weak self] in
                self?.close()
            })
        )
        contentViewController = host
    }

    override func close() {
        super.close()
        Self.shared = nil
    }

    override var canBecomeKey: Bool { true }
}

private struct PromisePanelContent: View {
    @ObservedObject var sessionVM: SessionViewModel
    let dismiss: () -> Void

    @State private var promise: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This time I promise to...")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextField("", text: $promise, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(2...4)
                .focused($focused)
                .onSubmit { Task { await submit() } }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(promise.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { focused = true }
    }

    private func submit() async {
        await sessionVM.submit(promise: promise)
        dismiss()
    }
}
