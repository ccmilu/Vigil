import AppKit
import CoreGraphics

/// 屏幕度量辅助：自动检测物理刘海尺寸 + 菜单栏高度。
/// 借鉴 boring.notch 的实现。
///
/// 多显示器改造后全部参数化为 `xxx(for screen:)`，回退值逻辑内聚在各函数内
/// （notchWidth 220 / menuBarHeight 24 / notchHeight 0 / hasNotchedDisplay false）。
/// 无参 `static var` 是 `.main` 的兼容壳，供旧调用方与测试零改动使用。
@MainActor
enum ScreenMetrics {

    /// 指定屏幕是否有物理刘海
    static func hasNotchedDisplay(for screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return screen.safeAreaInsets.top > 0
    }

    /// 兼容壳：主屏是否有物理刘海
    static var hasNotchedDisplay: Bool { hasNotchedDisplay(for: .main) }

    /// 指定屏幕的物理刘海实际宽度（pt）。无刘海 / 无信息时返回回退值 220
    static func notchWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 220 }
        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            // boring.notch +4 是为了让岛盖住刘海的反锯齿边缘
            return screen.frame.width - left - right + 4
        }
        return 220  // 无 auxiliary area 信息时的回退
    }

    /// 兼容壳：主屏刘海宽度
    static var notchWidth: CGFloat { notchWidth(for: .main) }

    /// 指定屏幕的菜单栏总高度（含刘海机型的刘海高度）。
    /// 注意：无菜单栏的副屏（罕见配置）返回 0，调用方按需自行回退。
    static func menuBarHeight(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return 24 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    /// 兼容壳：主屏菜单栏高度
    static var menuBarHeight: CGFloat { menuBarHeight(for: .main) }

    /// 指定屏幕的刘海高度（无刘海机型返回 0）
    static func notchHeight(for screen: NSScreen?) -> CGFloat {
        screen?.safeAreaInsets.top ?? 0
    }

    /// 兼容壳：主屏刘海高度
    static var notchHeight: CGFloat { notchHeight(for: .main) }
}
