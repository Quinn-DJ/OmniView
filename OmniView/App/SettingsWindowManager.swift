import AppKit
import SwiftUI

/// 设置窗口管理器：手动创建并显示设置窗口（教务网登录 / DeepSeek API Key）。
///
/// 为什么不用 SwiftUI `Settings` 场景：在 `LSUIElement` 菜单栏应用里，
/// `Settings` 场景对应的「设置…」菜单项只有在主窗口打开、应用处于前台时才可能被点到，
/// 菜单栏弹出面板（MenuBarExtra）中则完全没有入口 —— 用户会表现为「打不开设置」。
/// 这里与 `MainWindowManager` 采用同一套做法：AppKit 直接创建窗口，
/// 并在显示时临时切换激活策略（`.regular`）把窗口带到前台。
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private var zju: ZJUViewModel?
    private var deepSeek: DeepSeekViewModel?

    private init() {}

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// 由 `AppDelegate` 在启动时注入视图模型
    func configure(zju: ZJUViewModel, deepSeek: DeepSeekViewModel) {
        self.zju = zju
        self.deepSeek = deepSeek
    }

    /// 打开设置窗口（已存在则带到前台）
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            AppActivation.activate()
            return
        }
        guard let zju, let deepSeek else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OmniView 设置"
        window.isReleasedWhenClosed = false // 关闭后保留窗口，再次打开直接复用
        window.contentView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(zju)
                .environmentObject(deepSeek)
        )

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppActivation.restoreAccessoryIfNoWindows()
            }
        }

        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        AppActivation.activate()
    }
}
