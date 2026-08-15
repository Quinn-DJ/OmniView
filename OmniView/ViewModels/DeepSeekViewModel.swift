import Combine
import Foundation

/// 单日 Token 用量拆分（用于堆叠柱状图与 hover 明细）
struct DailyTokenUsage: Identifiable {
    let id = UUID()
    let date: Date
    var cacheHit: Int
    var cacheMiss: Int
    var output: Int
    var requests: Int

    var total: Int { cacheHit + cacheMiss + output }
}

/// DeepSeek 监控视图模型：余额与用量
final class DeepSeekViewModel: ObservableObject {
    @Published var hasAPIKey = false
    @Published var apiKeyInput = ""
    @Published var balance: BalanceInfo?
    @Published var balanceAvailable = false
    @Published var usageRecords: [UsageRecord] = []
    @Published var isLoadingBalance = false
    @Published var isLoadingUsage = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var usageDays: Int = 30

    private let service = DeepSeekService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        hasAPIKey = service.hasAPIKey
    }

    var totalCostThisMonth: Decimal {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return usageRecords
            .compactMap { record -> (Decimal, Date)? in
                guard let date = Self.dateFormatter.date(from: record.date),
                      date >= monthStart
                else { return nil }
                return (record.costAmount, date)
            }
            .reduce(Decimal(0)) { $0 + $1.0 }
    }

    var totalTokens: Int {
        usageRecords.reduce(0) { $0 + $1.totalTokens }
    }

    var dailyCostSeries: [(date: Date, cost: Decimal, tokens: Int)] {
        let calendar = Calendar.current
        var byDay: [Date: (cost: Decimal, tokens: Int)] = [:]
        for record in usageRecords {
            guard let date = Self.dateFormatter.date(from: record.date) else { continue }
            let day = calendar.startOfDay(for: date)
            var entry = byDay[day] ?? (0, 0)
            entry.cost += record.costAmount
            entry.tokens += record.totalTokens
            byDay[day] = entry
        }
        return byDay.map { ($0.key, $0.value.cost, $0.value.tokens) }
            .sorted { $0.date < $1.date }
    }

    /// 按日 Token 消耗拆分（输入缓存命中 / 输入未命中 / 输出 / 请求次数）
    var dailyTokenUsage: [DailyTokenUsage] {
        let calendar = Calendar.current
        var byDay: [Date: DailyTokenUsage] = [:]
        for record in usageRecords {
            guard let date = Self.dateFormatter.date(from: record.date) else { continue }
            let day = calendar.startOfDay(for: date)
            var entry = byDay[day] ?? DailyTokenUsage(
                date: day,
                cacheHit: 0,
                cacheMiss: 0,
                output: 0,
                requests: 0
            )
            entry.cacheHit += record.inputCacheHitTokens
            entry.cacheMiss += record.inputCacheMissTokens
            entry.output += record.completionTokens
            entry.requests += record.requestCount
            byDay[day] = entry
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    var modelSummary: [(model: String, tokens: Int, cost: Decimal)] {
        var byModel: [String: (tokens: Int, cost: Decimal)] = [:]
        for record in usageRecords {
            var entry = byModel[record.modelName] ?? (0, 0)
            entry.tokens += record.totalTokens
            entry.cost += record.costAmount
            byModel[record.modelName] = entry
        }
        return byModel.map { ($0.key, $0.value.tokens, $0.value.cost) }
            .sorted { $0.cost > $1.cost }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try service.saveAPIKey(key)
            hasAPIKey = true
            apiKeyInput = ""
            errorMessage = nil
        } catch {
            errorMessage = "保存 API Key 失败：\(error.localizedDescription)"
        }
    }

    func clearAPIKey() {
        do {
            try service.clearAPIKey()
            hasAPIKey = false
            balance = nil
            usageRecords = []
        } catch {
            errorMessage = "清除 API Key 失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    func refresh() async {
        guard hasAPIKey else { return }
        errorMessage = nil

        isLoadingBalance = true
        do {
            let response = try await service.fetchBalance()
            balance = response.preferredBalanceInfo
            balanceAvailable = response.isAvailable
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingBalance = false

        isLoadingUsage = true
        do {
            let response = try await service.fetchRecentUsage(days: usageDays)
            usageRecords = response.data
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoadingUsage = false
        lastUpdated = Date()
    }
}
