import AppKit
import SwiftUI

/// 主窗口管理器：手动创建并显示完整界面窗口。
///
/// 为什么不用 SwiftUI `Window` 场景：在 `LSUIElement`（无 Dock 图标）菜单栏应用里，
/// `Window` 场景配合 `openWindow` 在 macOS 26 上不可靠（窗口可能不创建或创建在其他应用后面）。
/// 这里用 AppKit 直接创建窗口，并在显示时临时切换激活策略（.regular）把窗口带到前台，
/// 窗口关闭后再恢复 .accessory（无 Dock 图标）——这是社区公认的菜单栏应用方案。
@MainActor
final class MainWindowManager {
    static let shared = MainWindowManager()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private var systemMonitor: SystemMonitorViewModel?
    private var calendar: CalendarViewModel?
    private var zju: ZJUViewModel?
    private var deepSeek: DeepSeekViewModel?

    private init() {}

    /// 由 `OmniViewApp.body` 注入视图模型（body 在应用启动时求值）
    func configure(
        systemMonitor: SystemMonitorViewModel,
        calendar: CalendarViewModel,
        zju: ZJUViewModel,
        deepSeek: DeepSeekViewModel
    ) {
        self.systemMonitor = systemMonitor
        self.calendar = calendar
        self.zju = zju
        self.deepSeek = deepSeek
    }

    /// 打开完整界面窗口（已存在则带到前台）
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }
        guard let systemMonitor, let calendar, let zju, let deepSeek else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OmniView"
        window.minSize = NSSize(width: 1000, height: 640)
        window.isReleasedWhenClosed = false // 关闭后保留窗口，再次打开直接复用
        window.setFrameAutosaveName("OmniViewMainWindow")

        let contentView = ContentView()
            .environmentObject(systemMonitor)
            .environmentObject(calendar)
            .environmentObject(zju)
            .environmentObject(deepSeek)
        window.contentView = NSHostingView(rootView: contentView)

        // 窗口关闭时恢复菜单栏应用状态（隐藏 Dock 图标）
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }

        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        activateApp()
    }

    /// LSUIElement 应用需要临时切回普通激活策略，窗口才能显示在其他应用之上
    private func activateApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
