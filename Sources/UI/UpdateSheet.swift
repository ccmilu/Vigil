import SwiftUI
import AppKit

/// 检测到新版本后弹出的 sheet。
///
/// 状态机：idle/failed → 用户点"立即更新" → downloading → mounting → mounted。
/// mounted 后 Finder 已经弹出 dmg 拖动窗口，用户拖到 Applications 即完成。
struct UpdateSheet: View {
    let release: ReleaseInfo
    let currentVersion: SemanticVersion
    @ObservedObject var downloader: UpdateDownloader
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            notesView
            Divider()
            actionRow
        }
        .padding(20)
        .frame(width: 520)
    }

    /// 优先用 GitHub Release 的 name 当主标题（用户自定义的标题最直观）；
    /// 当 name 为空 / 跟 tag 一样没意义时回落到 "Vigil X 已发布" 的合成标题。
    private var hasMeaningfulName: Bool {
        let name = release.name.trimmingCharacters(in: .whitespaces)
        let versionStr = release.version.description
        return !name.isEmpty
            && name != release.tagName
            && name.lowercased() != "v\(versionStr)"
            && name != versionStr
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                    .imageScale(.large)
                if hasMeaningfulName {
                    // GitHub release 的标题是用户内容，verbatim 不本地化
                    Text(verbatim: release.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Vigil \(release.version.description) 已发布")
                        .font(.title2.weight(.semibold))
                }
            }
            HStack(spacing: 6) {
                Text("当前版本 \(currentVersion.description) → \(release.version.description)")
                if let date = release.publishedAt {
                    Text(verbatim: "·")
                    Text("发布于 \(date.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var notesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if release.body.isEmpty {
                    Text("（这一版本暂无更新说明）")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ReleaseNotesView(markdown: release.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxHeight: 240)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionRow: some View {
        switch downloader.state {
        case .idle, .failed:
            idleOrFailedRow
        case .downloading(let progress):
            downloadingRow(progress: progress)
        case .mounting:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在准备安装…").foregroundStyle(.secondary)
                Spacer()
            }
        case .mounted:
            mountedRow
        }
    }

    private var idleOrFailedRow: some View {
        let isFailed: Bool = {
            if case .failed = downloader.state { return true }
            return false
        }()

        return VStack(alignment: .leading, spacing: 8) {
            if case .failed(let msg) = downloader.state {
                VStack(alignment: .leading, spacing: 4) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("国内访问 GitHub 经常卡顿。建议用浏览器直接下载——浏览器自带连接优化，成功率通常比 App 内下载高。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if isFailed {
                failedActionRow
            } else {
                idleActionRow
            }
        }
    }

    /// 正常 idle 状态：左次要、右主按钮（立即更新 = App 内下载）
    private var idleActionRow: some View {
        HStack {
            Button("打开 Release 页") {
                NSWorkspace.shared.open(release.htmlURL)
            }
            Spacer()
            Button("稍后再说") { onDismiss() }
            Button("立即更新") {
                if let dmgURL = release.dmgURL {
                    downloader.download(from: dmgURL)
                } else {
                    // 没有 dmg 资产时退化为打开网页
                    NSWorkspace.shared.open(release.htmlURL)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(release.dmgURL == nil)
            .help(release.dmgURL == nil ? "该版本未上传 dmg 资源，请前往 Release 页手动下载" : "")
        }
    }

    /// failed 状态：重试退到左侧次要、浏览器下载升为右侧主按钮
    /// 因为这种情况下 GitHub 直连大概率持续不通，重试只是给用户兜底
    private var failedActionRow: some View {
        HStack {
            Button("重试下载") {
                if let dmgURL = release.dmgURL {
                    downloader.download(from: dmgURL)
                }
            }
            .disabled(release.dmgURL == nil)
            Spacer()
            Button("稍后再说") { onDismiss() }
            Button {
                NSWorkspace.shared.open(release.htmlURL)
            } label: {
                Label("用浏览器下载", systemImage: "safari")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func downloadingRow(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress) {
                HStack {
                    Text("正在下载新版本…")
                        .font(.callout)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("取消") {
                    downloader.cancel()
                }
                .controlSize(.small)
            }
        }
    }

    private var mountedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("下载完成，请把 Vigil 拖到 Applications 替换旧版本", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Finder 已经为你弹出 dmg 窗口。拖动完成后请退出当前 Vigil 再启动新版本。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("关闭") {
                    downloader.reset()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// release notes Markdown 渲染：
/// SwiftUI 原生 AttributedString(markdown:) 只能渲染 inline 元素（粗体 / 斜体 / 链接），
/// 不支持 block（标题 / 列表 / 引用）。这里按行拆 Markdown，自己处理 block，
/// 行内仍走 AttributedString 拿到加粗 / 链接的渲染效果。
///
/// 空行不渲染（Markdown 的空行只是段落分隔，不该渲染成额外空白 row）——靠 VStack
/// spacing 自身处理段落间距；heading 额外加 top padding 形成视觉层次。
private struct ReleaseNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let lines = parse(markdown)
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, item in
                rowView(item, isFirst: idx == 0)
            }
        }
    }

    private enum Line {
        case heading(Int, String)
        case bullet(String)
        case quote(String)
        case paragraph(String)
    }

    /// 空行直接 compactMap 掉——不参与渲染，靠 VStack spacing 留段落间距。
    ///
    /// **必须 trim `.whitespacesAndNewlines` 而非 `.whitespaces`**：GitHub API 返回的 release body 用
    /// `\r\n` 换行，按 `\n` 拆分后每行末尾会带个 `\r`。`.whitespaces` 不包含 `\r`，导致
    /// 空行残留 `"\r"` 没被 trim 成空，再下游被当作 `.paragraph("\r")` 渲染——视觉上看着是 row 之间
    /// 巨大的空白（看不见但占 line height）。
    private func parse(_ md: String) -> [Line] {
        md.components(separatedBy: "\n").compactMap { raw -> Line? in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return nil }
            if let m = line.range(of: "^#{1,6} ", options: .regularExpression) {
                let level = line[m].filter { $0 == "#" }.count
                let text = String(line[m.upperBound...])
                return .heading(level, text)
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return .bullet(String(line.dropFirst(2)))
            }
            if line.hasPrefix("> ") {
                return .quote(String(line.dropFirst(2)))
            }
            return .paragraph(line)
        }
    }

    @ViewBuilder
    private func rowView(_ line: Line, isFirst: Bool) -> some View {
        switch line {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(level))
                // 第一个 heading 不要 top padding；其余 heading 跟前一行拉开距离
                .padding(.top, isFirst ? 0 : (level <= 2 ? 6 : 2))
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "•").foregroundStyle(.secondary)
                inlineText(text)
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2)
                inlineText(text).foregroundStyle(.secondary)
            }
        case .paragraph(let text):
            inlineText(text)
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if let attr = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attr)
        }
        return Text(verbatim: raw)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.weight(.semibold)
        case 2: return .headline
        default: return .callout.weight(.semibold)
        }
    }
}
