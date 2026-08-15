import Foundation

// MARK: - 错误类型

enum APIError: LocalizedError, Equatable {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case usageEndpointUnavailable
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API Key 未配置"
        case .invalidURL: return "无效的 URL"
        case .invalidResponse: return "服务器返回无效响应"
        case .unauthorized: return "API Key 无效或已过期"
        case .rateLimited: return "请求过于频繁，请稍后重试"
        case .serverError(let code): return "服务器错误 (\(code))"
        case .httpError(let code): return "HTTP 错误 (\(code))"
        case .usageEndpointUnavailable: return "DeepSeek 当前未公开用量查询接口，已仅显示余额"
        case .networkError(let msg): return "网络错误: \(msg)"
        case .decodingError(let msg): return "数据解析错误: \(msg)"
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - 响应模型

struct BalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    var preferredBalanceInfo: BalanceInfo? {
        let nonZero = balanceInfos.filter {
            (Decimal(string: $0.totalBalance, locale: Locale(identifier: "en_US_POSIX")) ?? .zero) != .zero
        }
        return nonZero.first ?? balanceInfos.first
    }
}

struct BalanceInfo: Codable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    var totalDecimal: Decimal {
        Decimal(string: totalBalance, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }
}

struct UsageResponse: Codable {
    let data: [UsageRecord]
}

struct UsageRecord: Codable, Identifiable {
    let id: String
    let modelName: String
    let totalTokens: Int
    let promptTokens: Int
    let inputCacheHitTokens: Int
    let inputCacheMissTokens: Int
    let completionTokens: Int
    let costByCurrency: [String: Decimal]
    let date: String
    let requestCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case modelName = "model_name"
        case totalTokens = "total_tokens"
        case promptTokens = "prompt_tokens"
        case inputCacheHitTokens = "input_cache_hit_tokens"
        case inputCacheMissTokens = "input_cache_miss_tokens"
        case completionTokens = "completion_tokens"
        case costByCurrency = "cost_by_currency"
        case date
        case requestCount = "request_count"
    }

    var primaryCurrencyCode: String {
        if costByCurrency.keys.contains("CNY") { return "CNY" }
        return costByCurrency.keys.sorted().first ?? "CNY"
    }

    var costAmount: Decimal {
        costByCurrency[primaryCurrencyCode] ?? 0
    }
}

// MARK: - DeepSeek API 服务

/// 封装 DeepSeek 官方 API：
///   - GET /user/balance → 账户余额
///   - GET /v1/usage     → Token 用量明细
/// 参考 https://github.com/JayHome137/DeepSeekMonitor
final class DeepSeekService {
    static let shared = DeepSeekService()

    private let baseURL = "https://api.deepseek.com"
    private let session: URLSession
    private var storedAPIKey: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        // 截图渲染 / 跳过账号服务时不读取钥匙串，避免系统授权弹窗阻塞启动
        if ProcessInfo.processInfo.arguments.contains("-renderScreenshots")
            || ProcessInfo.processInfo.arguments.contains("-skipAccountServices") {
            storedAPIKey = nil
        } else {
            storedAPIKey = KeychainStore.load(account: "deepseek_api_key")
        }
    }

    var hasAPIKey: Bool { !(storedAPIKey ?? "").isEmpty }
    var apiKeyConfigured: Bool { hasAPIKey }

    func saveAPIKey(_ apiKey: String) throws {
        try KeychainStore.save(apiKey, account: "deepseek_api_key")
        storedAPIKey = apiKey
    }

    func clearAPIKey() throws {
        try KeychainStore.delete(account: "deepseek_api_key")
        storedAPIKey = nil
    }

    /// 查询账户余额
    func fetchBalance() async throws -> BalanceResponse {
        guard hasAPIKey else { throw APIError.noAPIKey }
        var request = URLRequest(url: try makeURL(path: "/user/balance"))
        request.httpMethod = "GET"
        setRequestHeaders(&request)
        return try await performRequest(request)
    }

    /// 查询指定日期范围内的用量
    func fetchUsage(from startDate: Date, to endDate: Date) async throws -> UsageResponse {
        guard hasAPIKey else { throw APIError.noAPIKey }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]

        var components = URLComponents(string: "\(baseURL)/v1/usage")!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: fmt.string(from: startDate)),
            URLQueryItem(name: "end_date", value: fmt.string(from: endDate)),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        setRequestHeaders(&request)

        do {
            return try await performRequest(request)
        } catch let error as APIError {
            if case .httpError(let statusCode) = error, statusCode == 404 {
                throw APIError.usageEndpointUnavailable
            }
            throw error
        }
    }

    /// 获取最近 N 天的用量
    func fetchRecentUsage(days: Int = 30) async throws -> UsageResponse {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -(days - 1), to: endDate)!
        return try await fetchUsage(from: startDate, to: endDate)
    }

    // MARK: - Helpers

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        return url
    }

    private func setRequestHeaders(_ request: inout URLRequest) {
        request.setValue("Bearer \(storedAPIKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        try validateResponse(response)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
}
