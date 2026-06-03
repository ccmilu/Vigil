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

/// 截图全屏预览 sheet
struct ScreenshotPreviewSheet: View {
    let url: URL
    let onClose: () -> Void

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 12) {
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
            HStack {
                Text(url.lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("在 Finder 显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("关闭") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(width: 1100, height: 720)
        .task { image = NSImage(contentsOf: url) }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
