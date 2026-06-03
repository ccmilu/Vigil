import SwiftUI
import KeyboardShortcuts

struct ContentView: View {
    @EnvironmentObject private var sessionVM: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            Divider()

            stateView

            Spacer()

            footer
        }
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus")
                .font(.system(size: 28, weight: .bold))
            Text("按 ⌘⌥Space 弹出 Promise 输入框，写一句你打算做的事")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch sessionVM.state {
        case .idle:
            Label("准备就绪 — 按 ⌘⌥Space 开始", systemImage: "keyboard")
                .foregroundStyle(.secondary)

        case .analyzing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("AI 正在判断 promise：\(sessionVM.lastPromise)")
            }

        case .ready(let result):
            VStack(alignment: .leading, spacing: 10) {
                Label("AI 判断完成", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                LabeledRow(label: "Promise", value: sessionVM.lastPromise)
                LabeledRow(label: "taskType", value: result.taskType.rawValue)
                LabeledRow(
                    label: "suggestion",
                    value: result.suggestion ?? "（promise 已足够清晰）"
                )
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("调用失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 6))
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Provider: \(DemoConfig.baseURL.absoluteString) · \(DemoConfig.model)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("重置") { sessionVM.reset() }
                .controlSize(.small)
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.smallCaps())
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionViewModel())
        .frame(width: 560, height: 380)
}
