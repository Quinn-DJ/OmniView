import XCTest
@testable import OmniView

final class DeepSeekModelTests: XCTestCase {

    /// 余额响应 JSON 解码
    func testBalanceResponseDecoding() {
        let json = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try? JSONDecoder().decode(BalanceResponse.self, from: data)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.isAvailable)
        XCTAssertEqual(response!.balanceInfos.count, 1)
        XCTAssertEqual(response!.balanceInfos[0].currency, "CNY")
        XCTAssertEqual(response!.balanceInfos[0].totalDecimal, Decimal(string: "110.00"))
        XCTAssertEqual(response!.preferredBalanceInfo?.currency, "CNY")
    }

    /// 用量响应 JSON 解码
    func testUsageResponseDecoding() {
        let json = """
        {
          "data": [
            {
              "id": "abc123",
              "model_name": "deepseek-chat",
              "total_tokens": 1500,
              "prompt_tokens": 1000,
              "input_cache_hit_tokens": 400,
              "input_cache_miss_tokens": 600,
              "completion_tokens": 500,
              "cost_by_currency": { "CNY": 0.015 },
              "date": "2026-08-01",
              "request_count": 12
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let response = try? JSONDecoder().decode(UsageResponse.self, from: data)
        XCTAssertNotNil(response)
        XCTAssertEqual(response!.data.count, 1)
        let record = response!.data[0]
        XCTAssertEqual(record.modelName, "deepseek-chat")
        XCTAssertEqual(record.totalTokens, 1500)
        XCTAssertEqual(record.primaryCurrencyCode, "CNY")
        XCTAssertEqual(record.costAmount, Decimal(string: "0.015"))
    }

    /// 空用量列表
    func testEmptyUsageResponse() {
        let data = Data(#"{"data": []}"#.utf8)
        let response = try? JSONDecoder().decode(UsageResponse.self, from: data)
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.data.isEmpty)
    }
}
