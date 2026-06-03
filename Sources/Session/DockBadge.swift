import Foundation
import AppKit

/// 在 Dock 图标右上角显示剩余分钟数（如 "24"）。
/// MVP 用 badgeLabel；环形进度图标留到 v0.2。
@MainActor
enum DockBadge {
    static func setRemaining(seconds: Int?) {
        guard let s = seconds else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        if s <= 0 {
            NSApp.dockTile.badgeLabel = "✓"
        } else if s >= 60 {
            NSApp.dockTile.badgeLabel = "\(s / 60)"
        } else {
            NSApp.dockTile.badgeLabel = "<1"
        }
    }
}
