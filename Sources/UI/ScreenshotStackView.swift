import SwiftUI

/// 多屏截图"一叠卡片"缩略图组件（历史详情时间轴用）。
///
/// - 单张：渲染与旧版完全一致的 60×36 缩略图（纯 AsyncImageThumbnail 退化，无偏移/无角标/无阴影）
/// - 多张：ZStack 倒序渲染（urls[0] 最左屏在最上层），每张向右下偏移 7pt/5pt，
///   每张卡片带轻微投影（落在下一张卡片露出的右下边缘上，营造堆叠纵深）；
///   右上角 `×N` 角标；整体 frame 随张数放大（宽 60+7×(N-1)，高 36+5×(N-1)）
/// - 点击整块触发 onTap（由调用方打开多图预览）
struct ScreenshotStackView: View {
    /// 按物理从左到右排序的截图 URL（urls[0] 最左屏，渲染在最上层）。
    /// 调用方约定空数组走"无截图"灰块分支；组件内部仍对空数组兜底。
    let urls: [URL]
    /// 单张卡片尺寸，默认与历史时间轴现状一致（60×36）
    var size: CGSize = CGSize(width: 60, height: 36)
    /// 点击整块堆叠
    let onTap: () -> Void

    /// 每张卡片相对前一张的右下偏移（右 7 / 下 5）
    private static let offsetStep = CGSize(width: 7, height: 5)

    var body: some View {
        Button(action: onTap) {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if urls.count > 1 {
            stackedCards
        } else if let first = urls.first {
            // 单张：退化为现状外观（Button + AsyncImageThumbnail，与旧版逐像素一致）
            AsyncImageThumbnail(url: first, size: size)
        } else {
            // 空数组兜底：与调用方"无截图"灰块一致
            Color.gray.opacity(0.05)
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 3))
        }
    }

    /// 多屏堆叠：indices 倒序渲染（SwiftUI ZStack 后声明的在上层），
    /// 让 urls[0]（最左屏、offset 0）最终压在最上面。
    private var stackedCards: some View {
        let step = Self.offsetStep
        return ZStack(alignment: .topLeading) {
            ForEach(Array(urls.indices.reversed()), id: \.self) { i in
                AsyncImageThumbnail(url: urls[i], size: size)
                    // 卡片 i 的右下投影正好落在卡片 i+1 露出的右下边缘上，形成一叠的层次感
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0.5, y: 1)
                    .offset(x: step.width * CGFloat(i), y: step.height * CGFloat(i))
            }
        }
        .frame(
            width: size.width + step.width * CGFloat(urls.count - 1),
            height: size.height + step.height * CGFloat(urls.count - 1),
            alignment: .topLeading
        )
        .overlay(alignment: .topTrailing) { countBadge }
    }

    /// 右上角张数角标。"×" 是纯符号、中英同形，不进字符串目录，用 verbatim。
    private var countBadge: some View {
        Text(verbatim: "×\(urls.count)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.black.opacity(0.65), in: .capsule)
            .offset(x: 4, y: -4)
    }
}
