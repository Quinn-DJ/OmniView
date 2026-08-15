import SwiftUI

// MARK: - 菜单栏状态项文本（3 列：↑↓速率 ｜ CPU ｜ 内存）

/// 菜单栏状态项文本，三列两行显示，每秒随采样刷新：
/// ```
/// ↑ 1.2M  CPU   内存
/// ↓ 38K   21%   67%
/// ```
///
/// 重要：`MenuBarExtra` 的文本标签不接受 SwiftUI 字体修饰符（系统用菜单栏固定字体渲染），
/// 因此这里把文字用 `NSAttributedString` 绘制成图片（`Image(nsImage:)`）作为标签，
/// 字号与行距完全可控。修改字号请直接改 `fontSize`。
struct MenuBarLabel: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel

    /// 菜单栏文字字号（pt），直接修改此值即可调整大小
    private let fontSize: CGFloat = 9
    /// 两行文字之间的行距（pt）
    private let lineSpacing: CGFloat = 1
    /// 列与列之间的间距（pt）
    private let columnGap: CGFloat = 8

    /// 三列布局：第一列 ↑↓ 网络速率，第二列 CPU，第三列 内存（标签在上、数值在下）。
    /// 列之间用 Tab 分隔，由 `render` 按每列实际宽度自动对齐。
    private var labelText: String {
        guard let snapshot = viewModel.snapshot else { return "—" }
        let up = compactRate(snapshot.network.uploadRate)
        let down = compactRate(snapshot.network.downloadRate)
        let cpu = Format.percent(snapshot.cpu.total)
        let mem = Format.percent(snapshot.memory.usedFraction * 100)
        return "↑ \(up)\tCPU\t内存\n↓ \(down)\t\(cpu)\t\(mem)"
    }

    var body: some View {
        Image(nsImage: Self.render(
            text: labelText,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            columnGap: columnGap
        ))
        .accessibilityLabel(labelText)
        .help(labelText)
    }

    /// 把文字绘制成图片：菜单栏标签只能用图片形式才能自定义字体。
    /// 文本为「Tab 分隔的多列网格」，按各列最大宽度生成制表位实现列对齐。
    ///
    /// 注意：必须用 `lockFocus` 方式绘制（`NSImage(size:flipped:drawingHandler:)`
    /// 在 macOS 26 状态项上下文中会渲染成实心黑块），并标记为模板图以适配深浅色菜单栏。
    static func render(text: String, fontSize: CGFloat, lineSpacing: CGFloat, columnGap: CGFloat = 8, weight: NSFont.Weight = .medium) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        let measure: (String) -> CGFloat = { string in
            NSAttributedString(string: string, attributes: [.font: font]).size().width
        }

        // 按行/列拆分，计算每列最大宽度
        let cells = text.components(separatedBy: "\n").map { $0.components(separatedBy: "\t") }
        let columnCount = cells.map(\.count).max() ?? 1
        var columnWidths: [CGFloat] = []
        for column in 0..<columnCount {
            let width = cells
                .compactMap { $0.indices.contains(column) ? $0[column] : nil }
                .map(measure)
                .max() ?? 0
            columnWidths.append(width)
        }

        // 制表位：第 N 列起点 = 前 N 列宽度之和 + 间距
        var location: CGFloat = 0
        let tabStops = columnWidths.dropLast().map { columnWidth -> NSTextTab in
            location += columnWidth + columnGap
            return NSTextTab(textAlignment: .left, location: location)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = tabStops
        paragraph.lineSpacing = lineSpacing
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        let size = attributed.size()
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        attributed.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// 网络速率紧凑格式：12B / 1.2K / 1.2M / 1.2G
    private func compactRate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        switch value {
        case ..<10_000: return String(format: "%.2fKB/s", value / 1_000)
        case ..<100_000: return String(format: "%.1fKB/s", value / 1_000)
        case ..<1_000_000: return String(format: "%.0fKB/s", value / 1_000)
        case ..<10_000_000: return String(format: "%.2fMB/s", value / 1_000_000)
        case ..<100_000_000: return String(format: "%.1fMB/s", value / 1_000_000)
        case ..<1_000_000_000: return String(format: "%.0fMB/s", value / 1_000_000)
        case ..<10_000_000_000: return String(format: "%.2fGB/s", value / 1_000_000_000)
        case ..<100_000_000_000: return String(format: "%.1fGB/s", value / 1_000_000_000)
        case ..<1_000_000_000_000: return String(format: "%.0fGB/s", value / 1_000_000_000)
        default: return String(format: "%.2fTB/s", value / 1_000_000_000_000)
        }
    }
}

// MARK: - 菜单栏弹出面板

/// 点击菜单栏图标弹出的面板：CPU / 内存 / 网络 三项指标 + 打开完整界面
///
/// 面板在应用失活或窗口失去焦点时自动关闭（macOS 26 的窗口式菜单栏面板
/// 不会自动随外部点击关闭，需手动监听失焦通知）。
struct MenuBarPanelView: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            header

            if let snapshot = viewModel.snapshot {
                cpuCard(snapshot)
                memoryCard(snapshot)
                networkCard(snapshot)
            } else {
                ProgressView("正在采集系统指标…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 340)
        // 失焦自动关闭：点击其他应用/桌面/其他窗口时收起面板
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            dismiss()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 15, weight: .semibold))
            Text("OmniView")
                .font(.headline)
            Spacer()
            Button {
                viewModel.sampleNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("立即采样")
        }
    }

    // MARK: - 三个指标卡片

    private func cpuCard(_ snapshot: SystemSnapshot) -> some View {
        StatusMetricCard(
            title: "CPU 使用率",
            systemImage: "cpu",
            value: Format.percent(snapshot.cpu.total),
            detail: "用户 \(Format.percent(snapshot.cpu.user, fractionDigits: 1)) · 系统 \(Format.percent(snapshot.cpu.system, fractionDigits: 1))",
            indicatorColor: utilizationColor(snapshot.cpu.total / 100)
        )
    }

    private func memoryCard(_ snapshot: SystemSnapshot) -> some View {
        StatusMetricCard(
            title: "内存",
            systemImage: "memorychip",
            value: "\(Format.bytes(snapshot.memory.used)) / \(Format.bytes(snapshot.memory.total))",
            detail: "已用 \(Format.percent(snapshot.memory.usedFraction * 100)) · 可用 \(Format.bytes(snapshot.memory.available))",
            indicatorColor: memoryColor(snapshot.memory.usedFraction)
        )
    }

    private func networkCard(_ snapshot: SystemSnapshot) -> some View {
        StatusMetricCard(
            title: "网络",
            systemImage: "network",
            value: "↓ \(Format.rate(snapshot.network.downloadRate))",
            detail: "↑ \(Format.rate(snapshot.network.uploadRate)) · 累计 ↓\(Format.bytes(snapshot.network.downloadTotal)) ↑\(Format.bytes(snapshot.network.uploadTotal))",
            indicatorColor: .blue
        )
    }

    // MARK: - 底部操作

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
                MainWindowManager.shared.show()
            } label: {
                Label("打开完整界面", systemImage: "macwindow")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Spacer()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出 OmniView")
        }
    }

    // MARK: - 颜色辅助（与系统仪表盘一致）

    private func utilizationColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.5: return .blue
        case ..<0.8: return .orange
        default: return .red
        }
    }

    private func memoryColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .blue
        case ..<0.85: return .orange
        default: return .red
        }
    }
}

// MARK: - Previews

#Preview("菜单栏弹出面板") {
    let viewModel = SystemMonitorViewModel()
    return MenuBarPanelView()
        .environmentObject(viewModel)
        .task { viewModel.sampleNow() }
}

#Preview("菜单栏文本") {
    let viewModel = SystemMonitorViewModel()
    return MenuBarLabel()
        .environmentObject(viewModel)
        .padding()
        .task { viewModel.sampleNow() }
}
