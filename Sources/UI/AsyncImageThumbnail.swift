import SwiftUI
import AppKit

/// 异步加载本地图片为缩略图，避免阻塞主线程。
struct AsyncImageThumbnail: View {
    let url: URL
    let size: CGSize

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.06)
                    .overlay(ProgressView().controlSize(.mini))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .task(id: url) { await load() }
    }

    private func load() async {
        let url = self.url
        let img = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        await MainActor.run { self.image = img }
    }
}

/// 截图全屏预览 sheet。
///
/// 多屏帧传入多张截图（urls[0] = 最左屏，按物理 minX 从左到右排序）：
/// 底部出现缩略图选择条（当前高亮），←/→ 方向键切换，标题栏显示"屏幕 i/N · 文件名"，
/// "在 Finder 显示"指向当前选中图。
/// 单元素数组时外观与旧版逐像素一致（无选择条、无方向键、标题只有文件名）。
struct ScreenshotPreviewSheet: View {
    /// 本帧全部截图；调用方保证非空（空数组在调用侧走"无截图"分支不会打开本 sheet）
    let urls: [URL]
    let onClose: () -> Void

    /// 当前选中的截图下标（0 起）
    @State private var selection: Int = 0
    @State private var image: NSImage?

    /// 当前选中截图的 URL（selection clamp 在数组范围内，防越界）
    private var currentURL: URL {
        urls[min(max(selection, 0), urls.count - 1)]
    }

    var body: some View {
        VStack(spacing: 12) {
            imageArea
            if urls.count > 1 {
                thumbnailStrip
            }
            bottomBar
        }
        .frame(width: 1100, height: 720)
        // selection 变化 → currentURL 变化 → 重载大图
        .task(id: currentURL) { await loadImage() }
        .background(arrowKeyHandlers)
    }

    @ViewBuilder
    private var imageArea: some View {
        if let img = image {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.6))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 底部缩略图选择条（仅多图）：当前选中 accent 描边高亮，未选中半透明，点击切换
    private var thumbnailStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(urls.enumerated()), id: \.offset) { i, url in
                Button { selection = i } label: {
                    AsyncImageThumbnail(url: url, size: CGSize(width: 96, height: 56))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(i == selection ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .opacity(i == selection ? 1 : 0.7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        HStack {
            titleText
            Spacer()
            Button("在 Finder 显示") {
                NSWorkspace.shared.activateFileViewerSelecting([currentURL])
            }
            Button("关闭") { onClose() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var titleText: some View {
        if urls.count > 1 {
            // i 从 1 起展示；编号 = urls 顺序 = 物理 minX 从左到右
            Text("屏幕 \(selection + 1)/\(urls.count) · \(currentURL.lastPathComponent)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        } else {
            // 单图：与旧版一致，只显示文件名
            Text(currentURL.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    /// ←/→ 方向键切换（仅多图挂载）。隐藏 Button 挂 keyboardShortcut：
    /// SwiftUI 对 .hidden() 视图仍在视图树内派发快捷键，是跨 macOS 版本的稳妥写法。
    @ViewBuilder
    private var arrowKeyHandlers: some View {
        if urls.count > 1 {
            Group {
                Button { moveSelection(-1) } label: { EmptyView() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button { moveSelection(1) } label: { EmptyView() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .hidden()
        }
    }

    private func moveSelection(_ delta: Int) {
        let next = selection + delta
        guard urls.indices.contains(next) else { return }
        selection = next
    }

    /// 异步加载当前选中截图（本地大图同步读会卡 UI，与 AsyncImageThumbnail 同一套路）
    private func loadImage() async {
        image = nil
        let url = currentURL
        let img = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value
        image = img
    }
}

/// `.sheet(item:)` 的 [URL] 包装：URL 自身已 @retroactive Identifiable，数组没有，
/// 需要一层 Identifiable 壳才能用 item 驱动 sheet。
struct ScreenshotPreviewSelection: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.absoluteString).joined(separator: "\n") }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
