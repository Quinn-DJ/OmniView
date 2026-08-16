import AppKit
import SwiftUI

/// 应用代理：菜单栏应用的生命周期管理
/// - 启动系统监控采样与各数据源的加载（原 WindowGroup 的 `.task` 等价逻辑）
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 应用生命周期内持有的视图模型，供各 Scene 共享
    let systemMonitor = SystemMonitorViewModel()
    let calendar = CalendarViewModel()
    let zju = ZJUViewModel()
    let deepSeek = DeepSeekViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainWindowManager.shared.configure(
            systemMonitor: systemMonitor,
            calendar: calendar,
            zju: zju,
            deepSeek: deepSeek
        )
        if ScreenshotRenderer.runIfRequested() { return }
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
            systemMonitor.start()
            systemMonitor.refreshHardware()
            await calendar.requestAccessIfNeeded()
        }

        // 调试：`-skipAccountServices` 跳过账号服务（UI 测试用，避免钥匙串授权弹窗）
        guard !ProcessInfo.processInfo.arguments.contains("-skipAccountServices") else { return }

        // 后台线程：ZJU 登录检查。钥匙串访问可能触发系统授权对话框，
        // 若在主线程执行会阻塞整个菜单栏 UI（状态项无法出现）。
        let zju = zju
        Task.detached(priority: .userInitiated) {
            await zju.checkLoginState()
            if zju.hasSavedAccount {
                await zju.loginWithSavedAccount()
                await zju.refreshHomework()
            }
        }
    }
}

// MARK: - 调试截图渲染

/// 调试工具：启动时传 `-renderScreenshots <输出目录>`，渲染主要界面并导出 PNG 后退出。
/// 用于生成 README 截图，不依赖屏幕录制权限。
@MainActor
private enum ScreenshotRenderer {
    static func runIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-renderScreenshots"),
              arguments.indices.contains(index + 1)
        else {
            return false
        }
        let outputDir = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        fputs("render mode: \(outputDir.path)\n", stderr)
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            await renderAll(to: outputDir)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func renderAll(to outputDir: URL) async {
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            fputs("创建输出目录失败: \(error)\n", stderr)
            return
        }

        // 系统监控数据：采样多次，让曲线有历史点
        fputs("sampling...\n", stderr)
        let system = SystemMonitorViewModel()
        system.start()
        try? await Task.sleep(for: .seconds(1))
        for _ in 0..<8 {
            system.sampleNow()
            try? await Task.sleep(for: .milliseconds(200))
        }
        system.stop()
        system.refreshHardware()
        fputs("sampling done\n", stderr)

        fputs("creating view models...\n", stderr)
        let deepSeek = DeepSeekViewModel()
        injectDeepSeekDemoData(into: deepSeek)
        fputs("view models created\n", stderr)

        // 直接渲染详情页（ImageRenderer 不支持 NavigationSplitView / List 容器）
        let detailViews: [(name: String, view: AnyView)] = [
            ("dashboard", AnyView(SystemDashboardView().environmentObject(system).background(Color(nsColor: .windowBackgroundColor)))),
            ("system-info", AnyView(SystemInfoView().environmentObject(system).background(Color(nsColor: .windowBackgroundColor)))),
            ("deepseek", AnyView(DeepSeekDashboardView().environmentObject(deepSeek).background(Color(nsColor: .windowBackgroundColor)))),
        ]
        for item in detailViews {
            fputs("渲染 \(item.name)...\n", stderr)
            render(
                item.view,
                size: CGSize(width: 1100, height: 700),
                to: outputDir.appendingPathComponent("\(item.name).png")
            )
            fputs("完成 \(item.name)\n", stderr)
        }

        // 菜单栏标签与弹出面板
        fputs("渲染 menu-bar...\n", stderr)
        render(
            MenuBarLabel()
                .environmentObject(system)
                .frame(width: 260, height: 48)
                .background(Color.white),
            size: CGSize(width: 260, height: 48),
            to: outputDir.appendingPathComponent("menu-bar.png")
        )
        fputs("完成 menu-bar\n", stderr)
        fputs("渲染 menu-bar-panel...\n", stderr)
        render(
            MenuBarPanelView()
                .environmentObject(system)
                .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 340, height: 430),
            to: outputDir.appendingPathComponent("menu-bar-panel.png")
        )
        fputs("完成 menu-bar-panel\n", stderr)
    }

    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        // ImageRenderer 无法渲染 ScrollView / List 容器，这里改用离屏 NSHostingView 缓存绘制
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("渲染失败: \(url.lastPathComponent)\n", stderr)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            fputs("PNG 编码失败: \(url.lastPathComponent)\n", stderr)
            return
        }
        do {
            try png.write(to: url)
            print("已生成截图: \(url.path)")
        } catch {
            fputs("写入截图失败: \(url.path) \(error)\n", stderr)
        }
    }

    /// 渲染模式注入演示数据，让 DeepSeek 看板展示余额与用量图表
    private static func injectDeepSeekDemoData(into viewModel: DeepSeekViewModel) {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let models = ["deepseek-chat", "deepseek-reasoner"]
        var records: [UsageRecord] = []
        for dayOffset in stride(from: 29, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let model = models[dayOffset % models.count]
            let wave = (dayOffset * 13) % 40
            let tokens = 25_000 + wave * 1_500
            let cost = Decimal(Double(tokens) * 0.0000008)
            records.append(UsageRecord(
                id: "demo-\(dayOffset)-\(model)",
                modelName: model,
                totalTokens: tokens,
                promptTokens: tokens / 2,
                inputCacheHitTokens: tokens / 4,
                inputCacheMissTokens: tokens / 4,
                completionTokens: tokens / 2,
                costByCurrency: ["CNY": cost],
                date: formatter.string(from: day),
                requestCount: 8 + (dayOffset % 6)
            ))
        }

        viewModel.hasAPIKey = true
        viewModel.balanceAvailable = true
        viewModel.balance = BalanceInfo(
            currency: "CNY",
            totalBalance: "18.50",
            grantedBalance: "5.00",
            toppedUpBalance: "13.50"
        )
        viewModel.usageRecords = records
        viewModel.lastUpdated = today
    }
}
