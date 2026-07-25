import AppKit

extension NSScreen {
    /// 该屏对应的 CGDirectDisplayID——多屏场景下标识一块物理显示器的稳定 key。
    /// 取不到（理论罕见）返回 nil，调用方应跳过该屏。
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
