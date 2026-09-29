import AppKit

/// 菜单栏应用（LSUIElement / `.accessory`）在显示窗口时需要临时切回普通激活策略，
/// 否则窗口不会出现在最前面、也没有应用菜单；所有窗口关闭后再恢复无 Dock 图标状态。
@MainActor
enum AppActivation {
    /// 切到普通激活策略并把应用带到前台
    static func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 主窗口与设置窗口都关闭后恢复菜单栏应用状态（隐藏 Dock 图标）
    static func restoreAccessoryIfNoWindows() {
        guard !MainWindowManager.shared.isVisible, !SettingsWindowManager.shared.isVisible else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
