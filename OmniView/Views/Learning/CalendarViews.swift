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

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
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

    // MARK: 顶部工具栏

    private var header: some View {
        HStack(spacing: 12) {
            Picker("", selection: $viewModel.mode) {
                ForEach(CalendarViewModel.DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)

            navigationCluster

            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// 「上一页 / 今天 / 下一页」控制簇：视觉上成组，与模式切换分离
    private var navigationCluster: some View {
        HStack(spacing: 0) {
            navButton("chevron.left") {
                viewModel.move(by: viewModel.mode == .month ? .month : .day, value: -1)
            }
            Button("今天") {
                viewModel.goToToday()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            navButton("chevron.right") {
                viewModel.move(by: viewModel.mode == .month ? .month : .day, value: 1)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func navButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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
            return Self.dayTitleFormatter.string(from: viewModel.currentDate)
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
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(event.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(CalendarStyle.color(for: event).opacity(0.18))
        .foregroundStyle(CalendarStyle.color(for: event))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(CalendarStyle.color(for: event).opacity(0.5), lineWidth: 0.5)
        )
        .help(event.isAllDay ? event.title : "\(event.title)（\(CalendarStyle.timeString(event.startDate)) – \(CalendarStyle.timeString(event.endDate))）")
    }
}

// MARK: - 日视图

struct DayView: View {
    let events: [CalendarEventItem]
    let date: Date

    var body: some View {
        TimelineGrid(
            events: events,
            columns: 1,
            showsNowIndicator: Calendar.current.isDateInToday(date)
        ) { event in
            EventChip(event: event)
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

    private var todayIndex: Int? {
        days.firstIndex { Calendar.current.isDateInToday($0) }
    }

    private var showsToday: Bool {
        todayIndex != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 36)
                ForEach(days, id: \.self) { day in
                    dayHeader(day)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            TimelineGrid(
                events: days.flatMap { eventsByDay[$0] ?? [] },
                columns: 7,
                columnStartDates: days,
                highlightColumn: todayIndex,
                showsNowIndicator: showsToday
            ) { event in
                EventChip(event: event)
            }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let isWeekend = calendar.isDateInWeekend(day)

        return VStack(spacing: 2) {
            Text(Self.weekdayFormatter.string(from: day))
                .font(.caption)
                .foregroundStyle(isWeekend ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            Text(Self.dayFormatter.string(from: day))
                .font(.headline)
                .foregroundStyle(isToday ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 26, height: 26)
                .background(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
                .clipShape(Circle())
        }
    }
}

// MARK: - 时间网格

/// 事件时间轴：左侧时间刻度 + 按时间定位的事件卡片
struct TimelineGrid<Content: View>: View {
    let events: [CalendarEventItem]
    let columns: Int
    var columnStartDates: [Date]? = nil
    var highlightColumn: Int? = nil
    var showsNowIndicator: Bool = false
    let content: (CalendarEventItem) -> Content

    private let dayStart = CalendarStyle.dayStartHour
    private let dayEnd = CalendarStyle.dayEndHour
    private let hourHeight = CalendarStyle.hourHeight

    private var gridHeight: CGFloat {
        CGFloat(dayEnd - dayStart) * hourHeight
    }

    var body: some View {
        ScrollView {
            TimelineView(.everyMinute) { context in
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let columnWidth = (width - 44) / CGFloat(columns)

                    ZStack(alignment: .topLeading) {
                        hourColumn
                        if let highlightColumn {
                            columnHighlight(index: highlightColumn, columnWidth: columnWidth)
                        }
                        eventLayer(columnWidth: columnWidth)
                        if showsNowIndicator, let nowY = nowLineY(for: context.date) {
                            nowIndicator(width: width, y: nowY)
                        }
                    }
                }
                .frame(height: gridHeight)
            }
        }
    }

    /// 时间刻度与网格线
    private var hourColumn: some View {
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
    }

    /// 高亮某一列（周视图中的今天）
    private func columnHighlight(index: Int, columnWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.05))
            .frame(width: max(0, columnWidth - 2), height: gridHeight)
            .position(x: 44 + CGFloat(index) * columnWidth + columnWidth / 2, y: gridHeight / 2)
    }

    /// 事件层
    private func eventLayer(columnWidth: CGFloat) -> some View {
        ForEach(events) { event in
            let position = eventPosition(event, columnWidth: columnWidth)
            content(event)
                .frame(width: position.width)
                .position(x: position.x, y: position.y)
        }
    }

    /// 当前时间指示线（仅当天范围内的视图显示）
    private func nowIndicator(width: CGFloat, y: CGFloat) -> some View {
        Group {
            Rectangle()
                .fill(Color.red.opacity(0.85))
                .frame(width: max(0, width - 44), height: 1)
                .position(x: 44 + max(0, width - 44) / 2, y: y)
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .position(x: 40, y: y)
        }
    }

    /// 当前时间在网格中的 y 坐标（超出 6:00–24:00 则不显示）
    private func nowLineY(for date: Date) -> CGFloat? {
        let calendar = Calendar.current
        let hour = CGFloat(calendar.component(.hour, from: date))
            + CGFloat(calendar.component(.minute, from: date)) / 60
        guard hour >= CGFloat(dayStart), hour <= CGFloat(dayEnd) else { return nil }
        return (hour - CGFloat(dayStart)) * hourHeight
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

    private static let cellSpacing: CGFloat = 3
    private static let rows = 6
    private static let columns = 7

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.cellSpacing) {
                ForEach(Self.weekdayNames, id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // 6 行等分剩余高度：小窗口不溢出、大窗口铺满
            GeometryReader { proxy in
                let spacing = Self.cellSpacing
                let rowHeight = (proxy.size.height - spacing * CGFloat(Self.rows - 1)) / CGFloat(Self.rows)
                VStack(spacing: spacing) {
                    ForEach(0..<Self.rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<Self.columns, id: \.self) { column in
                                let index = row * Self.columns + column
                                if grid.indices.contains(index) {
                                    monthCell(grid[index], cellHeight: rowHeight)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func monthCell(_ day: Date, cellHeight: CGFloat) -> some View {
        let calendar = Calendar.current
        let isCurrentMonth = calendar.isDate(day, equalTo: currentMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let dayEvents = eventsByDay[calendar.startOfDay(for: day)] ?? []
        let visibleCount = min(2, max(1, Int((cellHeight - 39) / 22)))
        let visibleEvents = dayEvents.prefix(visibleCount)
        let hasMore = dayEvents.count > visibleCount

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
                    .opacity(isCurrentMonth ? 1 : 0.55)
            }
            if hasMore {
                Text("+\(dayEvents.count - visibleCount) 项")
                    .font(.system(size: 9))
                    .foregroundStyle(isCurrentMonth ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrentMonth ? Color.primary.opacity(0.03) : Color.primary.opacity(0.012))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Previews

#Preview("日历") {
    CalendarView()
        .environmentObject(CalendarViewModel())
        .frame(width: 1100, height: 700)
}
