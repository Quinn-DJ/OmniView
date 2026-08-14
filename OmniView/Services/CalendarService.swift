import AppKit
import EventKit
import Foundation

/// 日历事件（包装 EKEvent）
struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let location: String?
    let notes: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let color: (red: Double, green: Double, blue: Double)
    let url: URL?

    var isClassEvent: Bool { calendarTitle.contains("Celechron") }

    static func == (lhs: CalendarEventItem, rhs: CalendarEventItem) -> Bool {
        lhs.id == rhs.id && lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate
    }
}

/// 日历服务：读取 Apple 日历中的「Celechron课表」与「个人」日历
/// 参考 Celechron (https://github.com/Celechron) 的日历同步逻辑
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    static let celechronCalendarName = "Celechron课表"
    static let personalCalendarName = "个人"

    private let store = EKEventStore()

    @Published var authorizationDenied = false
    @Published var calendars: [EKCalendar] = []

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// 请求日历访问权限
    func requestAccess() async -> Bool {
        let granted: Bool
        if #available(macOS 14.0, *) {
            do {
                granted = try await store.requestFullAccessToEvents()
            } catch {
                granted = false
            }
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { result, _ in
                    continuation.resume(returning: result)
                }
            }
        }
        await MainActor.run {
            authorizationDenied = !granted
            if granted {
                refreshCalendars()
            }
        }
        return granted
    }

    func refreshCalendars() {
        calendars = store.calendars(for: .event)
    }

    /// 获取关注的日历：「Celechron课表」和「个人」
    func watchedCalendars() -> [EKCalendar] {
        let all = store.calendars(for: .event)
        let celechron = all.filter { $0.title == Self.celechronCalendarName }
        let personal = all.filter { $0.title == Self.personalCalendarName }
        if !celechron.isEmpty || !personal.isEmpty {
            return celechron + personal
        }
        // 兜底：如果没有这两个日历，则展示全部可写日历（避免空白界面）
        return all.filter { $0.allowsContentModifications }
    }

    /// 获取日期范围内的事件
    func events(from startDate: Date, to endDate: Date) -> [CalendarEventItem] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return []
        }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: watchedCalendars())
        return store.events(matching: predicate).map { event in
            CalendarEventItem(
                id: event.eventIdentifier,
                title: event.title ?? "无标题",
                location: event.location,
                notes: event.notes,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title,
                color: Self.rgbComponents(of: event.calendar.cgColor),
                url: event.url
            )
        }
    }

    /// 提取日历颜色的 RGB 分量（安全处理灰度/模式颜色）
    private static func rgbComponents(of cgColor: CGColor) -> (red: Double, green: Double, blue: Double) {
        let defaultColor = (red: 0.2, green: 0.5, blue: 0.9)
        guard let nsColor = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return defaultColor
        }
        return (nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent)
    }

    /// 课程事件按天分组（用于周/日视图）
    static func eventsByDay(_ events: [CalendarEventItem], calendar: Calendar = .current) -> [Date: [CalendarEventItem]] {
        var result: [Date: [CalendarEventItem]] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.startDate)
            result[day, default: []].append(event)
        }
        return result
    }

    /// 提取事件中的课程信息（Celechron 事件标题格式：「课程名」）
    static func classInfo(from event: CalendarEventItem) -> (course: String, detail: String)? {
        guard event.isClassEvent else { return nil }
        var detailParts: [String] = []
        if let location = event.location, !location.isEmpty {
            detailParts.append(location)
        }
        if let notes = event.notes, !notes.isEmpty {
            detailParts.append(notes)
        }
        return (event.title, detailParts.joined(separator: " · "))
    }
}
