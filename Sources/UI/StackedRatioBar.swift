import SwiftUI

/// 一条 100% 宽的水平堆叠条，按 ratio 切几段。
struct StackedRatioBar: View {
    let segments: [(Color, Double)]
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if seg.1 > 0 {
                        Rectangle()
                            .fill(seg.0)
                            .frame(width: max(geo.size.width * CGFloat(seg.1), 1))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: height / 2))
        .overlay(
            RoundedRectangle(cornerRadius: height / 2)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
}
