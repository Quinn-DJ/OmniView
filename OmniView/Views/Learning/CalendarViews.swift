import SwiftUI

// MARK: - 日历主视图

struct CalendarView: View {
    @EnvironmentObject private var viewModel: CalendarViewModel

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    private static let weekRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.authorizationDenied {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("没有日历访问权限")
                        .font(.title3)
                    Text("请在「系统设置 → 隐私与安全性 → 日历」中允许 OmniView 访问日历")
                        .foregroundStyle(.secondary)
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $viewModel.mode) {
                ForEach(CalendarViewModel.DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button {
                viewModel.move(by: viewModel.mode == .month ? .month : .day, value: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Button("今天") {
                viewModel.goToToday()
            }
            .buttonStyle(.borderless)

            Button {
                viewModel.move(by: viewModel.mode == .month ? .month : .day, value: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)

            Text(title)
                .font(.title3.weight(.semibold))
                .frame(minWidth: 200, alignment: .leading)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var title: String {
        switch viewModel.mode {
        case .month:
            return Self.titleFormatter.string(from: viewModel.currentDate)
        case .week:
            let days = viewModel.weekDays
            guard let first = days.first, let last = days.last else { return "" }
            return "\(Self.weekRangeFormatter.string(from: first)) – \(Self.weekRangeFormatter.string(from: last))"
        case .day:
            return Self.titleFormatter.string(from: viewModel.currentDate)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.mode {
        case .day:
            DayView(events: viewModel.events, date: viewModel.currentDate)
        case .week:
            WeekView(days: viewModel.weekDays, eventsByDay: eventsByDay)
        case .month:
            MonthView(grid: viewModel.monthGrid, currentMonth: viewModel.currentDate, eventsByDay: eventsByDay)
        }
    }

    private var eventsByDay: [Date: [CalendarEventItem]] {
        CalendarService.eventsByDay(viewModel.events)
    }
}

// MARK: - 事件样式辅助

enum CalendarStyle {
    static let hourHeight: CGFloat = 56
    static let dayStartHour = 6
    static let dayEndHour = 24

    static func color(for event: CalendarEventItem) -> Color {
        Color(red: event.color.red, green: event.color.green, blue: event.color.blue)
    }

    static func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct EventChip: View {
    let event: CalendarEventItem

    var body: some View {
        HStack(spacing: 4) {
            if event.isClassEvent {
                Image(systemName: "graduationcap")
                    .font(.system(size: 10))
            }
            Text(event.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(CalendarStyle.color(for: event).opacity(0.18))
        .foregroundStyle(CalendarStyle.color(for: event))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(CalendarStyle.color(for: event).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - 日视图

struct DayView: View {
    let events: [CalendarEventItem]
    let date: Date

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.dayTitleFormatter.string(from: date))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            TimelineGrid(events: events, columns: 1) { event in
                EventChip(event: event)
            }
        }
    }
}

// MARK: - 周视图

struct WeekView: View {
    let days: [Date]
    let eventsByDay: [Date: [CalendarEventItem]]

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 36)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 2) {
                        Text(Self.weekdayFormatter.string(from: day))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Self.dayFormatter.string(from: day))
                            .font(.headline)
                            .foregroundStyle(Calendar.current.isDateInToday(day) ? .white : .primary)
                            .frame(width: 26, height: 26)
                            .background(
                                Calendar.current.isDateInToday(day)
                                    ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(.clear)
                            )
                            .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            HStack(spacing: 0) {
                TimelineGrid(events: days.flatMap { eventsByDay[$0] ?? [] }, columns: 7, columnStartDates: days) { event in
                    EventChip(event: event)
                }
            }
        }
    }
}

// MARK: - 时间网格

/// 事件时间轴：左侧时间刻度 + 按时间定位的事件卡片
struct TimelineGrid<Content: View>: View {
    let events: [CalendarEventItem]
    let columns: Int
    var columnStartDates: [Date]? = nil
    let content: (CalendarEventItem) -> Content

    private let dayStart = CalendarStyle.dayStartHour
    private let dayEnd = CalendarStyle.dayEndHour
    private let hourHeight = CalendarStyle.hourHeight

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                let width = proxy.size.width
                let columnWidth = (width - 44) / CGFloat(columns)

                ZStack(alignment: .topLeading) {
                    // 时间刻度与网格线
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(dayStart..<dayEnd, id: \.self) { hour in
                            HStack(spacing: 0) {
                                Text(String(format: "%02d:00", hour))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 36, alignment: .trailing)
                                Rectangle()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 0.5)
                            }
                            .frame(height: hourHeight)
                        }
                    }

                    // 事件
                    ForEach(events) { event in
                        let position = eventPosition(event, columnWidth: columnWidth)
                        content(event)
                            .frame(width: position.width)
                            .position(x: position.x, y: position.y)
                    }
                }
            }
            .frame(height: CGFloat(dayEnd - dayStart) * hourHeight)
        }
    }

    private func eventPosition(_ event: CalendarEventItem, columnWidth: CGFloat) -> (x: CGFloat, y: CGFloat, width: CGFloat) {
        let calendar = Calendar.current
        let startHour = CGFloat(calendar.component(.hour, from: event.startDate))
            + CGFloat(calendar.component(.minute, from: event.startDate)) / 60
        let endHour = max(startHour + 0.25, CGFloat(calendar.component(.hour, from: event.endDate))
            + CGFloat(calendar.component(.minute, from: event.endDate)) / 60)
        let clampedStart = max(startHour, CGFloat(dayStart))
        let clampedEnd = min(endHour, CGFloat(dayEnd))

        let dayIndex: Int = {
            if columns == 1 { return 0 }
            if let columnStartDates {
                // 按事件所在日期在列中的实际位置计算
                for (index, day) in columnStartDates.enumerated()
                where calendar.isDate(event.startDate, inSameDayAs: day) {
                    return min(index, columns - 1)
                }
                return 0
            }
            let weekday = calendar.component(.weekday, from: event.startDate) // 1=周日
            let mondayBased = (weekday + 5) % 7
            return min(max(mondayBased, 0), columns - 1)
        }()

        let slotWidth = columnWidth - 6
        let x = 44 + CGFloat(dayIndex) * columnWidth + slotWidth / 2 + 3
        let y = (clampedStart - CGFloat(dayStart)) * hourHeight
            + (clampedEnd - clampedStart) * hourHeight / 2
        let height = max(CGFloat(20), (clampedEnd - clampedStart) * hourHeight - 4)

        // 简化的重叠避让：同一时段最多 3 列
        let sameDayEvents = events.filter { candidate in
            guard candidate.startDate < event.endDate, candidate.endDate > event.startDate else {
                return false
            }
            if let columnStartDates {
                for day in columnStartDates where calendar.isDate(candidate.startDate, inSameDayAs: day) {
                    return calendar.isDate(event.startDate, inSameDayAs: day)
                }
                return false
            }
            return calendar.component(.weekday, from: candidate.startDate)
                == calendar.component(.weekday, from: event.startDate)
        }
        let sorted = sameDayEvents.sorted { $0.startDate < $1.startDate }
        let index = min(sorted.firstIndex { $0.id == event.id } ?? 0, 2)
        let overlapCount = min(3, sorted.count)
        let subWidth = slotWidth / CGFloat(overlapCount)
        let subX = 44 + CGFloat(dayIndex) * columnWidth + 3 + subWidth * CGFloat(index) + subWidth / 2

        return (columns == 1 ? x : subX, y, columns == 1 ? slotWidth : subWidth - 2)
    }
}

// MARK: - 月视图

struct MonthView: View {
    let grid: [Date]
    let currentMonth: Date
    let eventsByDay: [Date: [CalendarEventItem]]

    private static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(Self.weekdayNames, id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(grid, id: \.self) { day in
                    monthCell(day)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func monthCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isCurrentMonth = calendar.isDate(day, equalTo: currentMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let dayEvents = eventsByDay[calendar.startOfDay(for: day)] ?? []
        let visibleEvents = dayEvents.prefix(3)

        return VStack(alignment: .leading, spacing: 2) {
            Text(Self.dayFormatter.string(from: day))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(
                    isToday
                        ? Color.white
                        : (isCurrentMonth ? Color.primary : Color(nsColor: .tertiaryLabelColor))
                )
                .frame(width: 20, height: 20)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(Circle())

            ForEach(visibleEvents) { event in
                EventChip(event: event)
            }
            if dayEvents.count > 3 {
                Text("+\(dayEvents.count - 3) 项")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isToday ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("日历") {
    CalendarView()
        .environmentObject(CalendarViewModel())
        .frame(width: 1100, height: 700)
}
