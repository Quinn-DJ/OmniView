import SwiftUI

@main
struct OmniViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var systemMonitor = SystemMonitorViewModel()
    @StateObject private var calendar = CalendarViewModel()
    @StateObject private var zju = ZJUViewModel()
    @StateObject private var deepSeek = DeepSeekViewModel()

    var body: some Scene {
        // 将视图模型注入应用代理与主窗口管理器（body 在启动时求值）
        appDelegate.systemMonitor = systemMonitor
        appDelegate.calendar = calendar
        appDelegate.zju = zju
        appDelegate.deepSeek = deepSeek
        MainWindowManager.shared.configure(
            systemMonitor: systemMonitor,
            calendar: calendar,
            zju: zju,
            deepSeek: deepSeek
        )

        // 菜单栏：3 列指标文本，点击弹出面板
        return MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(systemMonitor)
        } label: {
            MenuBarLabel()
                .environmentObject(systemMonitor)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口：菜单栏「OmniView → 设置…」(⌘,)
        Settings {
            SettingsView()
                .environmentObject(zju)
                .environmentObject(deepSeek)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新全部数据") {
                    Task {
                        await calendar.reload()
                        await deepSeek.refresh()
                        await zju.refreshHomework()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
