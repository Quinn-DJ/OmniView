import Combine
import EventKit
import Foundation

/// 日历视图模型：按日/周/月加载「Celechron课表」与「个人」日历事件
final class CalendarViewModel: ObservableObject {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case day = "日"
        case week = "周"
        case month = "月"

        var id: String { rawValue }
    }

    @Published var mode: DisplayMode = .week
    @Published var currentDate = Date()
    @Published var events: [CalendarEventItem] = []
    @Published var authorizationDenied = false
    @Published var isLoading = false
    @Published var lastError: String?

    private let service = CalendarService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        service.$authorizationDenied
            .receive(on: RunLoop.main)
            .assign(to: &$authorizationDenied)

        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    var visibleRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        switch mode {
        case .day:
            let start = calendar.startOfDay(for: currentDate)
            return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: currentDate)!.start
            return (start, calendar.date(byAdding: .day, value: 7, to: start)!)
        case .month:
            let start = calendar.dateInterval(of: .month, for: currentDate)!.start
            return (start, calendar.date(byAdding: .month, value: 1, to: start)!)
        }
    }

    func requestAccessIfNeeded() async {
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            _ = await service.requestAccess()
        }
        await MainActor.run { reload() }
    }

    func reload() {
        let range = visibleRange
        isLoading = true
        lastError = nil
        events = service.events(from: range.start, to: range.end)
        isLoading = false
    }

    func move(by component: Calendar.Component, value: Int) {
        currentDate = Calendar.current.date(byAdding: component, value: value, to: currentDate) ?? currentDate
        reload()
    }

    func goToToday() {
        currentDate = Date()
        reload()
    }

    /// 一周的七天（周一开始）
    var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: currentDate)!.start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// 某一天的事件
    func events(on day: Date) -> [CalendarEventItem] {
        let calendar = Calendar.current
        return events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
    }

    /// 月份网格（含前后月补位）
    var monthGrid: [Date] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: currentDate)!
        let firstWeekday = calendar.component(.weekday, from: interval.start) // 1=周日
        let leading = (firstWeekday + 5) % 7 // 周一开始
        let start = calendar.date(byAdding: .day, value: -leading, to: interval.start)!
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}
