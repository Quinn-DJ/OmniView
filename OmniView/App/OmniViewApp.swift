import SwiftUI

@main
struct OmniViewApp: App {
    @StateObject private var systemMonitor = SystemMonitorViewModel()
    @StateObject private var calendar = CalendarViewModel()
    @StateObject private var zju = ZJUViewModel()
    @StateObject private var deepSeek = DeepSeekViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(systemMonitor)
                .environmentObject(calendar)
                .environmentObject(zju)
                .environmentObject(deepSeek)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    systemMonitor.start()
                    systemMonitor.refreshHardware()
                    await calendar.requestAccessIfNeeded()
                    await zju.checkLoginState()
                    if zju.hasSavedAccount {
                        await zju.loginWithSavedAccount()
                        await zju.refreshHomework()
                    }
                }
        }
        .windowStyle(.titleBar)
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

        // 设置窗口：菜单栏「OmniView → 设置…」(⌘,)
        Settings {
            SettingsView()
                .environmentObject(zju)
                .environmentObject(deepSeek)
        }
    }
}
