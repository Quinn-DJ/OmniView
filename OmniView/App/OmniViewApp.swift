import SwiftUI

@main
struct OmniViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单栏：3 列指标文本，点击弹出面板
        MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(appDelegate.systemMonitor)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.systemMonitor)
        }
        .menuBarExtraStyle(.window)
        .commands {
            // 设置窗口：菜单栏「OmniView → 设置…」(⌘,)
            // 不用 SwiftUI `Settings` 场景：菜单栏应用里它无法从弹出面板打开（见 SettingsWindowManager）
            CommandGroup(after: .appInfo) {
                Button("设置…") {
                    SettingsWindowManager.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("刷新全部数据") {
                    Task {
                        await appDelegate.calendar.reload()
                        await appDelegate.deepSeek.refresh()
                        await appDelegate.zju.refreshHomework()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
