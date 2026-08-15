import Combine
import Foundation

/// 系统监控视图模型：定时采样并维护历史曲线数据
@MainActor
final class SystemMonitorViewModel: ObservableObject {
    @Published var snapshot: SystemSnapshot?
    @Published var hardware: HardwareInfo?
    @Published var isSampling = false
    @Published var sampleError: String?

    // 历史数据（每秒一个采样点，保留 15 分钟）
    @Published private(set) var cpuHistory: [CPUSample] = []
    @Published private(set) var networkHistory: [NetworkUsage] = []
    @Published private(set) var powerHistory: [PowerUsage] = []
    @Published private(set) var temperatureHistory: [TemperatureUsage] = []
    @Published private(set) var coolingHistory: [CoolingUsage] = []

    let maxHistoryCount = 900
    let sampleInterval: TimeInterval = 1

    private let sampler = SystemSampler()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        guard !isSampling else { return }
        isSampling = true
        sampleNow()
        let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.sampleNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isSampling = false
        timer?.invalidate()
        timer = nil
    }

    func refreshHardware() {
        hardware = HardwareInfoService.read()
    }

    func sampleNow() {
        let result = sampler.sample()
        snapshot = result

        cpuHistory.append(result.cpu)
        if cpuHistory.count > maxHistoryCount {
            cpuHistory.removeFirst(cpuHistory.count - maxHistoryCount)
        }

        networkHistory.append(result.network)
        if networkHistory.count > maxHistoryCount {
            networkHistory.removeFirst(networkHistory.count - maxHistoryCount)
        }

        powerHistory.append(result.power)
        if powerHistory.count > maxHistoryCount {
            powerHistory.removeFirst(powerHistory.count - maxHistoryCount)
        }

        temperatureHistory.append(result.temperature)
        if temperatureHistory.count > maxHistoryCount {
            temperatureHistory.removeFirst(temperatureHistory.count - maxHistoryCount)
        }

        coolingHistory.append(result.cooling)
        if coolingHistory.count > maxHistoryCount {
            coolingHistory.removeFirst(coolingHistory.count - maxHistoryCount)
        }
    }
}
