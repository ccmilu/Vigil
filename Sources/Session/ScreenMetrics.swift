import AppKit
import CoreGraphics

/// 屏幕度量辅助：自动检测物理刘海尺寸 + 菜单栏高度。
/// 借鉴 boring.notch 的实现。
@MainActor
enum ScreenMetrics {

    /// 屏幕是否有物理刘海
    static var hasNotchedDisplay: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    /// 物理刘海实际宽度（pt）。无刘海机型返回默认值 220（用作折叠岛的最小宽度）
    static var notchWidth: CGFloat {
        guard let screen = NSScreen.main else { return 220 }
        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            // boring.notch +4 是为了让岛盖住刘海的反锯齿边缘
            return screen.frame.width - left - right + 4
        }
        return 220  // 无 auxiliary area 信息时的回退
    }

    /// 菜单栏总高度（含刘海机型的刘海高度）
    static var menuBarHeight: CGFloat {
        guard let screen = NSScreen.main else { return 24 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    /// 刘海高度（无刘海机型返回 0）
    static var notchHeight: CGFloat {
        NSScreen.main?.safeAreaInsets.top ?? 0
    }
}
