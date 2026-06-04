import SwiftUI
import SwiftData
import AppKit

/// 历史会话详情：promise / 时长 / 分布条 / summary / 每帧时间轴。
struct SessionDetailView: View {
    let session: FocusSession
    let onClose: () -> Void

    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            distributionBar
            if let summary = session.summary, !summary.isEmpty {
                ScrollView {
                    Text(summary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 120)
            }
            Text("时间轴")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
            timeline
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("关闭") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 760, height: 580)
        .sheet(item: $previewURL) { url in
            ScreenshotPreviewSheet(url: url) { previewURL = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.promise)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Label(
                    "\(session.actualDuration / 60) 分 \(session.actualDuration % 60) 秒",
                    systemImage: "clock"
                )
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                Text(session.status.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.12), in: .capsule)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var distributionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            StackedRatioBar(
                segments: [
                    (.green, session.fullyRatio),
                    (.yellow, session.wanderingRatio),
                    (.red, session.distractedRatio),
                    (.gray, session.idleRatio)
                ],
                height: 12
            )
            HStack(spacing: 14) {
                legend(color: .green, label: FocusLevel.fully.displayName, ratio: session.fullyRatio)
                legend(color: .yellow, label: FocusLevel.wandering.displayName, ratio: session.wanderingRatio)
                legend(color: .red, label: FocusLevel.distracted.displayName, ratio: session.distractedRatio)
                legend(color: .gray, label: FocusLevel.idle.displayName, ratio: session.idleRatio)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(color: Color, label: String, ratio: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text("\(label) \(Int(ratio * 100))%")
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(sortedRecords(), id: \.id) { r in
                    recordRow(r)
                }
            }
        }
    }

    private func sortedRecords() -> [AnalysisRecord] {
        session.records.sorted(by: { $0.createdAt < $1.createdAt })
    }

    private func recordRow(_ r: AnalysisRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // 缩略图：仅在有路径时显示
            if let url = screenshotURL(r.screenshotLocalPath) {
                Button { previewURL = url } label: {
                    AsyncImageThumbnail(url: url, size: CGSize(width: 60, height: 36))
                }
                .buttonStyle(.plain)
            } else {
                Color.gray.opacity(0.05)
                    .frame(width: 60, height: 36)
                    .clipShape(.rect(cornerRadius: 3))
            }

            Text(r.createdAt.formatted(.dateTime.hour().minute().second()))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)
            levelBadge(r.level)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.reasoning.isEmpty ? "(无 AI 推理)" : r.reasoning)
                    .font(.callout)
                if !r.frontAppName.isEmpty {
                    Text(r.frontAppName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if let dist = r.dhashDistance {
                Text("d=\(dist)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Text(r.fromAI ? "AI" : "复用")
                .font(.caption2.bold())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(r.fromAI ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(.capsule)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func screenshotURL(_ relativePath: String?) -> URL? {
        guard let p = relativePath, !p.isEmpty else { return nil }
        let url = ScreenshotStore.rootDirectory.appendingPathComponent(p)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }
}
