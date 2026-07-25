import SwiftUI
import SwiftData
import AppKit

/// 时间轴分段：一帧"锚点"（有信息增量）+ 后续被合并的无增量帧。
/// 时间轴按段展示，时间显示为区间，不再逐行罗列"复用"帧。
struct TimelineSegment: Identifiable {
    let first: AnalysisRecord
    private(set) var last: AnalysisRecord
    /// 段内总帧数（锚点帧 + 被合并帧）
    private(set) var count: Int

    var id: UUID { first.id }

    init(anchor: AnalysisRecord) {
        first = anchor
        last = anchor
        count = 1
    }

    mutating func extend(with r: AnalysisRecord) {
        last = r
        count += 1
    }
}

enum TimelineSegmenter {
    /// 合并规则：非 AI 判定（dHash 复用 / 客户端 idle 帧）且无截图、level 与上一段一致 → 并入上一段。
    /// AI 超时回落帧有截图（画面确实变了），保留独立行。
    /// 入参必须先按 createdAt 升序排好。
    static func makeSegments(from sorted: [AnalysisRecord]) -> [TimelineSegment] {
        var segs: [TimelineSegment] = []
        for r in sorted {
            let mergeable = !r.fromAI && r.screenshotLocalPath == nil
            if mergeable, !segs.isEmpty, segs[segs.count - 1].first.level == r.level {
                segs[segs.count - 1].extend(with: r)
            } else {
                segs.append(TimelineSegment(anchor: r))
            }
        }
        return segs
    }
}

/// 历史会话详情：promise / 时长 / 分布条 / summary / 时间轴（分段合并）。
struct SessionDetailView: View {
    let session: FocusSession
    let onClose: () -> Void

    @State private var previewURL: URL?
    /// 详情页头部 + 每条 record 时间的格式跟随用户语言
    @Environment(\.locale) private var locale

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
                Text(session.startedAt.formatted(.dateTime.locale(locale).year().month().day().hour().minute()))
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
            // label 已 L() 本地化，verbatim 避免 SwiftUI 当 LocalizedStringKey "%@ %lld%%"
            Text(verbatim: "\(label) \(Int(ratio * 100))%")
        }
    }

    private var timeline: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(TimelineSegmenter.makeSegments(from: sortedRecords())) { seg in
                    segmentRow(seg)
                }
            }
        }
    }

    private func sortedRecords() -> [AnalysisRecord] {
        session.records.sorted(by: { $0.createdAt < $1.createdAt })
    }

    private func segmentRow(_ seg: TimelineSegment) -> some View {
        let r = seg.first
        return HStack(alignment: .top, spacing: 8) {
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

            timeColumn(seg)
            levelBadge(r.level)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                reasoningText(r)
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
            sourceBadge(r)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    /// 时间列：单帧段只显示一个时刻；合并段显示起止区间（第二行）
    private func timeColumn(_ seg: TimelineSegment) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(seg.first.createdAt.formatted(.dateTime.locale(locale).hour().minute().second()))
            if seg.count > 1 {
                // 纯标点连接，走 verbatim 不进字符串目录
                Text(verbatim: "– \(seg.last.createdAt.formatted(.dateTime.locale(locale).hour().minute().second()))")
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.tertiary)
        .frame(width: 76, alignment: .leading)
    }

    @ViewBuilder
    private func reasoningText(_ r: AnalysisRecord) -> some View {
        if !r.reasoning.isEmpty {
            Text(r.reasoning).font(.callout)
        } else if r.level == .idle {
            Text("(无键鼠操作，标记为空闲)").font(.callout)
        } else {
            Text("(无 AI 推理)").font(.callout)
        }
    }

    /// 来源标识：AI 判定 → "AI"；非 AI 且非空闲（如超时回落帧）→ "复用"；空闲段不标（level 徽章已表明）
    @ViewBuilder
    private func sourceBadge(_ r: AnalysisRecord) -> some View {
        if r.fromAI {
            badge(Text("AI"), tint: .blue)
        } else if r.level != .idle {
            badge(Text("复用"), tint: .gray)
        }
    }

    private func badge(_ text: Text, tint: Color) -> some View {
        text
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(tint.opacity(0.15))
            .clipShape(.capsule)
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
