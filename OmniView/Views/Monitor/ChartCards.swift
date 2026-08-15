import Charts
import SwiftUI

// MARK: - 状态指标卡（参考 mac-scope 的 PerformanceStatusMetric）

struct StatusMetricCard: View {
    let title: String
    let systemImage: String
    let value: String
    let detail: String
    var detailLines: [String] = []
    let indicatorColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(indicatorColor)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if detailLines.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    ForEach(detailLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 面板（参考 mac-scope 的 PerformancePanel）

struct InfoPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 图表图例行（窄列布局：圆点 + 标题 + 数值）

struct ChartLegendRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - 折线图（带安全 y 域，避免颜色溢出）

/// 图表点（多序列）
struct LineChartPoint: Identifiable {
    enum Series: String {
        case system = "系统"
        case charging = "充电"
        case download = "下载"
        case upload = "上传"
        case fan = "风扇"

        var color: Color {
            switch self {
            case .system: return .orange
            case .charging: return .green
            case .download: return .blue
            case .upload: return .green
            case .fan: return .teal
            }
        }
    }

    let timestamp: Date
    let value: Double
    let series: String
    let color: Color

    var id: String { "\(timestamp.timeIntervalSinceReferenceDate):\(series)" }
}

/// 性能面板图表：多序列折线，y 域带安全下限与上浮，避免面积/线条溢出
struct PerformanceLineChart: View {
    let points: [LineChartPoint]
    var yDomain: ClosedRange<Double>? = nil
    var height: CGFloat = 180
    var showYAxis = true
    var colorBySeries = true

    var body: some View {
        if points.count < 2 {
            collectingView(height: height)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("时间", point.timestamp),
                    y: .value("数值", point.value),
                    series: .value("序列", point.series)
                )
                .foregroundStyle(colorBySeries ? point.color : .blue)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                if showYAxis {
                    AxisMarks(position: .leading)
                }
            }
            .chartYScale(domain: yDomain ?? Self.safeDomain(values: points.map(\.value)))
            .frame(height: height)
            .transaction { $0.animation = nil }
        }
    }

    /// 安全 y 域：始终非零且有上浮空间（参考 mac-scope：0...max(1, max*1.15)）
    static func safeDomain(values: [Double], floor: Double = 1, headroom: Double = 1.15) -> ClosedRange<Double> {
        let maximum = values.max() ?? 0
        return 0...max(floor, maximum * headroom)
    }

    /// 带上下留白的 y 域（用于温度等有自然下限的指标）
    static func paddedDomain(values: [Double], paddingFraction: Double = 0.2, minimumSpan: Double = 1) -> ClosedRange<Double> {
        let minimum = values.min() ?? 0
        let maximum = max(minimum + minimumSpan, values.max() ?? minimum + minimumSpan)
        let padding = max(2, (maximum - minimum) * paddingFraction)
        return (minimum - padding)...(maximum + padding)
    }

    func collectingView(height: CGFloat) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在收集数据…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

// MARK: - 折线 + 面积图（CPU）

struct PerformanceAreaLineChart: View {
    let points: [LineChartPoint]
    var color: Color = .blue
    var height: CGFloat = 180

    var body: some View {
        if points.count < 2 {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在收集数据…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: height)
        } else {
            Chart(points) { point in
                AreaMark(
                    x: .value("时间", point.timestamp),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("时间", point.timestamp),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartYScale(domain: 0...100)
            .frame(height: height)
            .transaction { $0.animation = nil }
        }
    }
}

// MARK: - 百分比条形

struct PercentBar: View {
    let fraction: Double
    var color: Color = .blue

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - 状态点

struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
