import XCTest

/// 菜单栏应用交互验证：
/// 1. 菜单栏状态项存在且包含 CPU / 内存 / 网络 指标文本
/// 2. 点击状态项弹出面板，面板包含三个指标卡片
/// 3. 点击「打开完整界面」打开主窗口
final class MenuBarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuBarShowsMetricsAndOpensFullWindow() throws {
        let app = XCUIApplication()
        // 跳过账号服务启动流程，避免钥匙串授权弹窗干扰测试
        app.launchArguments = ["-skipAccountServices"]
        app.launch()

        // 1. 菜单栏状态项出现，且文本包含三项指标
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 15), "菜单栏状态项未出现")
        XCTAssertTrue(
            statusItem.label.contains("CPU"),
            "状态项应包含 CPU 指标，实际标签: \(statusItem.label)"
        )
        XCTAssertTrue(
            statusItem.label.contains("内存") || statusItem.label.contains("G"),
            "状态项应包含内存指标，实际标签: \(statusItem.label)"
        )

        // 2. 点击状态项（避开中央区域的遮挡，点击右侧 90% 处）→ 弹出面板
        statusItem.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()
        let openButton = app.buttons["打开完整界面"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8), "弹出面板中未找到「打开完整界面」按钮")

        // 3. 面板包含 CPU / 内存 / 网络 三个指标
        XCTAssertTrue(app.staticTexts["CPU 使用率"].exists, "面板缺少 CPU 指标")
        XCTAssertTrue(app.staticTexts["内存"].exists, "面板缺少内存指标")
        XCTAssertTrue(app.staticTexts["网络"].exists, "面板缺少网络指标")

        // 4. 点击「打开完整界面」→ 主窗口出现
        openButton.click()
        let mainWindow = app.windows["OmniView"]
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10), "主窗口未打开")

        // 5. 主窗口渲染出系统监控仪表盘
        XCTAssertTrue(
            mainWindow.staticTexts["CPU 使用率"].waitForExistence(timeout: 10),
            "主窗口未渲染系统监控内容"
        )
    }
}
