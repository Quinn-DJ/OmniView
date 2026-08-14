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
    }

    @State private var selection: Section? = .dashboard

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
