import SwiftUI

/// 物理刘海"反向圆角"形状。
///
/// - 顶部两角是 **concave**（圆心在矩形外）—— 像被刘海"咬"了一口，
///   从两个外侧弯进矩形内部
/// - 底部两角是 **convex**（圆心在矩形内）—— 普通圆角
///
/// 参考 boring.notch / DynamicNotchKit 的 NotchShape 实现。
struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // 左上 concave（从外侧向内弯）
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // 左侧垂直
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // 左下 convex（普通圆角）
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // 底部水平
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // 右下 convex
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // 右侧垂直
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // 右上 concave
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // 顶部水平回起点
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

/// 用于描边——只画 U 形（左下 + 底部 + 右下），不画顶部水平边。
/// 这样 distracted 红色描边不会出现在贴菜单栏的顶部。
struct NotchBottomBorder: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 起点：岛最左上角（顶部水平线的左端点）
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // 左上 concave（反向）圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // 左侧垂直
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // 左下 convex 圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // 底部水平
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // 右下 convex 圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // 右侧垂直
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // 右上 concave（反向）圆角
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // 故意不闭合：不画顶部水平线，避免贴菜单栏处出现描边
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            .fill(.black)
            .frame(width: 220, height: 32)
        NotchShape(topCornerRadius: 10, bottomCornerRadius: 20)
            .fill(.black)
            .frame(width: 520, height: 110)
    }
    .padding(40)
    .background(Color.blue.opacity(0.2))
}
