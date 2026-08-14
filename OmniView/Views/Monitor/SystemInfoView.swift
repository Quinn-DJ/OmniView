import SwiftUI

/// 系统信息视图
struct SystemInfoView: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let hardware = viewModel.hardware {
                    infoCard(hardware)
                } else {
                    ProgressView("正在读取系统信息…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(16)
        }
        .navigationTitle("系统信息")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refreshHardware()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func infoCard(_ hardware: HardwareInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 概览头部
            HStack(spacing: 14) {
                Image(systemName: "macbook")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hardware.modelName)
                        .font(.title3.weight(.bold))
                    Text(hardware.modelIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            Group {
                row("芯片", hardware.chip, icon: "cpu")
                row("核心数", "\(hardware.cpuCores)", icon: "square.grid.3x3")
                row("内存", Format.bytes(hardware.memoryBytes), icon: "memorychip")
                row("图形处理器", hardware.graphics, icon: "gpu")
                row("macOS", "\(hardware.macOSVersion) (\(hardware.macOSBuild))", icon: "apple.logo")
                row("内核", hardware.kernelVersion, icon: "terminal")
                row("序列号", hardware.serialNumber, icon: "number")
                row("启动磁盘", hardware.bootVolumeName ?? "—", icon: "internaldrive")
                row("存储总量", Format.bytes(hardware.storageTotal), icon: "externaldrive")
                row("存储可用", Format.bytes(hardware.storageAvailable), icon: "externaldrive.badge.checkmark")
                row("运行时间", Format.time(hardware.systemUptime), icon: "timer")
            }
            .padding(.horizontal, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func row(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 7)
    }
}
