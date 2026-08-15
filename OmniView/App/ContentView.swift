import SwiftUI

/// 主导航：侧边栏 + 内容区
struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case calendar = "日历"
        case homework = "作业待办"
        case courseware = "课件"
        case dashboard = "系统监控"
        case systemInfo = "系统信息"
        case deepSeek = "DeepSeek"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .calendar: return "calendar"
            case .homework: return "checklist"
            case .courseware: return "doc.richtext"
            case .dashboard: return "gauge.with.dots.needle.67percent"
            case .systemInfo: return "info.circle"
            case .deepSeek: return "brain"
            }
        }

        var group: String {
            switch self {
            case .calendar, .homework, .courseware: return "学习"
            case .dashboard, .systemInfo: return "系统监控"
            case .deepSeek: return "AI 监控"
            }
        }

        /// 调试启动参数 `-initialSection` 使用的英文标识
        var debugValue: String {
            switch self {
            case .calendar: return "calendar"
            case .homework: return "homework"
            case .courseware: return "courseware"
            case .dashboard: return "dashboard"
            case .systemInfo: return "systemInfo"
            case .deepSeek: return "deepSeek"
            }
        }
    }

    @State private var selection: Section?

    init(initialSection: Section? = nil) {
        _selection = State(initialValue: initialSection ?? Self.defaultSection)
    }

    /// 调试启动参数：`-initialSection <key>`，可选值为 `debugValue`
    private static var defaultSection: Section? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-initialSection"),
              arguments.indices.contains(index + 1),
              let section = Section.allCases.first(where: { $0.debugValue == arguments[index + 1] })
        else {
            return .dashboard
        }
        return section
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
            .navigationTitle("OmniView")
        } detail: {
            switch selection ?? .dashboard {
            case .calendar:
                CalendarView()
            case .homework:
                HomeworkView()
            case .courseware:
                CoursewareView()
            case .dashboard:
                SystemDashboardView()
            case .systemInfo:
                SystemInfoView()
            case .deepSeek:
                DeepSeekDashboardView()
            }
        }
    }
}

// MARK: - Previews

#Preview("主界面") {
    ContentView()
        .environmentObject(SystemMonitorViewModel())
        .environmentObject(CalendarViewModel())
        .environmentObject(ZJUViewModel())
        .environmentObject(DeepSeekViewModel())
        .frame(width: 1100, height: 700)
}
