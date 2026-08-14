import Charts
import SwiftUI

// MARK: - 通用仪表卡片

struct MetricCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - 环形仪表

struct RingGauge: View {
    let value: Double          // 0-1
    let displayValue: String
    let unit: String
    var color: Color = .blue
    var gradient: LinearGradient? = nil

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.01, min(1, value)))
                    .stroke(
                        gradient ?? LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: value)
                VStack(spacing: 0) {
                    Text(displayValue)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
        }
    }
}

// MARK: - 迷你趋势图

struct MiniLineChart: View {
    struct Point: Identifiable {
        let id = UUID()
        let timestamp: Date
        let value: Double
    }

    let points: [Point]
    var color: Color = .blue
    var baseline: Double = 0

    var body: some View {
        if points.count < 2 {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.1))
                .frame(height: 56)
                .overlay {
                    Text("采样中…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        } else {
            Chart(points) { point in
                AreaMark(
                    x: .value("时间", point.timestamp),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("时间", point.timestamp),
                    y: .value("数值", point.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartYScale(domain: (points.map(\.value).min() ?? baseline)...(points.map(\.value).max() ?? baseline + 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)
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
