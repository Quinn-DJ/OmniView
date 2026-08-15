import AppKit

/// 应用代理：菜单栏应用的生命周期管理
/// - 启动系统监控采样与各数据源的加载（原 WindowGroup 的 `.task` 等价逻辑）
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 视图模型由 `OmniViewApp.body` 注入（body 在 didFinishLaunching 之前求值）
    var systemMonitor: SystemMonitorViewModel?
    var calendar: CalendarViewModel?
    var zju: ZJUViewModel?
    var deepSeek: DeepSeekViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startServices()

        // 调试：`-debugShowWindow` 启动 3 秒后自动打开主窗口（验证窗口创建路径）
        if ProcessInfo.processInfo.arguments.contains("-debugShowWindow") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                MainWindowManager.shared.show()
            }
        }
    }

    /// 应用关闭最后一个窗口后不退出（菜单栏应用常驻）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func startServices() {
        // 主线程：立即启动采样与硬件信息读取，保证菜单栏状态项快速出现
        Task { @MainActor in
            systemMonitor?.start()
            systemMonitor?.refreshHardware()
            await calendar?.requestAccessIfNeeded()
        }

        // 调试：`-skipAccountServices` 跳过账号服务（UI 测试用，避免钥匙串授权弹窗）
        guard !ProcessInfo.processInfo.arguments.contains("-skipAccountServices") else { return }

        // 后台线程：ZJU 登录检查。钥匙串访问可能触发系统授权对话框，
        // 若在主线程执行会阻塞整个菜单栏 UI（状态项无法出现）。
        let zju = zju
        Task.detached(priority: .userInitiated) {
            await zju?.checkLoginState()
            if zju?.hasSavedAccount == true {
                await zju?.loginWithSavedAccount()
                await zju?.refreshHomework()
            }
        }
    }
}
