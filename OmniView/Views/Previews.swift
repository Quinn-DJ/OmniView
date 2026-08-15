import SwiftUI

/// 各视图的 Xcode Preview 声明（⌥⌘⏎ 打开画布后选择对应预览）
/// 环境对象已在预览中注入，可直接渲染

#Preview("主界面") {
    ContentView()
        .environmentObject(SystemMonitorViewModel())
        .environmentObject(CalendarViewModel())
        .environmentObject(ZJUViewModel())
        .environmentObject(DeepSeekViewModel())
        .frame(width: 1100, height: 700)
}

#Preview("系统监控") {
    let viewModel = SystemMonitorViewModel()
    return SystemDashboardView()
        .environmentObject(viewModel)
        .frame(width: 1100, height: 800)
        .task { viewModel.sampleNow() }
}

#Preview("系统信息") {
    let viewModel = SystemMonitorViewModel()
    return SystemInfoView()
        .environmentObject(viewModel)
        .frame(width: 900, height: 800)
        .task { viewModel.refreshHardware() }
}

#Preview("日历") {
    CalendarView()
        .environmentObject(CalendarViewModel())
        .frame(width: 1100, height: 700)
}

#Preview("作业待办") {
    HomeworkView()
        .environmentObject(ZJUViewModel())
        .frame(width: 900, height: 600)
}

#Preview("课件") {
    CoursewareView()
        .environmentObject(ZJUViewModel())
        .frame(width: 900, height: 600)
}

#Preview("DeepSeek 看板") {
    DeepSeekDashboardView()
        .environmentObject(DeepSeekViewModel())
        .frame(width: 900, height: 700)
}

#Preview("设置") {
    SettingsView()
        .environmentObject(ZJUViewModel())
        .environmentObject(DeepSeekViewModel())
}
