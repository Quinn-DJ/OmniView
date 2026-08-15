# OmniView

macOS 原生仪表盘应用（SwiftUI），集学习、系统监控与 AI 监控于一体的 Dashboard。

## 功能

### 1. 学习相关
- **日历**：读取 Apple 日历中的 `Celechron课表` 与 `个人` 日历，支持 **日 / 周 / 月** 三种视图展示（参考 [Celechron](https://github.com/Celechron) 的展示方式），支持前后翻页与「今天」跳转
- **作业待办**：登录学在浙大（CAS 统一身份认证）后查看各课程作业与截止时间，支持逾期 / 进行中分组与已提交筛选（参考 [fiz](https://github.com/CrazySpottedDove/fiz)）
- **课件**：按课程浏览课件资料，支持一键下载到本地（Office 文件可走预览转换）

### 2. 系统监控（参考 [mac-scope](https://github.com/shenmuoso/mac-scope)）
- **系统负载**：CPU 使用率（环形仪表 + 30 分钟曲线）、内存占用、功耗（W）、温度（SoC / 电池 / 存储）、风扇转速（AppleSMC）
- **活动**：网络上下行速率与总量、磁盘读写速率与容量、电池电量 / 循环 / 健康度
- **系统信息**：机型、芯片、内存、显卡、macOS 版本、序列号、启动磁盘、存储等

### 3. AI 监控（参考 [DeepSeekMonitor](https://github.com/JayHome137/DeepSeekMonitor)）
- **DeepSeek 余额**：`GET /user/balance`，展示总余额 / 赠送 / 充值余额
- **用量监控**：`GET /v1/usage`，最近 7 / 30 / 90 天 Token 消耗与费用曲线，按模型汇总
- API Key 通过 macOS 钥匙串（Keychain）安全存储

## 技术栈

- SwiftUI + Swift Charts（macOS 14+）
- EventKit（日历）、IOKit / sysctl / Mach API（系统指标）、AppleSMC（风扇）
- 纯 Swift 实现的 BigUInt 裸 RSA（ZJU CAS 登录加密），无第三方依赖
- 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成（`project.yml`）

## 构建

```bash
# 安装 XcodeGen（首次）
brew install xcodegen

# 生成工程并构建
xcodegen generate
xcodebuild -project OmniView.xcodeproj -scheme OmniView -configuration Debug \
  -derivedDataPath build/DerivedData build

# 运行
open build/DerivedData/Build/Products/Debug/OmniView.app
```

## 打包 DMG

```bash
./scripts/build_dmg.sh                                  # 输出 build/OmniView-0.1.0-arm64.dmg
./scripts/build_dmg.sh ~/Desktop/OmniView.dmg           # 自定义输出路径
ARCH=x86_64 ./scripts/build_dmg.sh                      # 其他架构（默认 arm64）
```

脚本会构建 Release 版本，将 `OmniView.app` 与 `Applications` 快捷方式打包为只读 UDZO 压缩 DMG。
**默认仅打包 arm64**（Apple Silicon 原生），可通过 `ARCH` 环境变量指定其他架构。
应用为临时签名（ad-hoc），仅供本机/个人使用；如需分发给他人，请配置开发者签名后重新打包。

## 发布 GitHub Release（自动化）

配置了 GitHub Actions（`.github/workflows/release.yml`），两种触发方式：

```bash
# 方式一：手动触发（推荐）— 自动读取版本号、打 tag、构建 DMG、发布
#   GitHub 仓库页面 → Actions → Release → Run workflow

# 方式二：推送版本标签
git tag v0.2.0
git push origin v0.2.0
```

流程：读取 `project.yml` 的 `MARKETING_VERSION` → 构建 arm64 DMG → 创建 `v<版本>` 标签 → 发布 GitHub Release 并附上 `OmniView-<版本>-arm64.dmg` 产物、自动生成 release notes。

## 说明

- 应用未开启沙盒（与 Stats / iStat Menus 等系统监控工具一致），以便读取 SMC / IOKit 数据
- 首次启动会请求「日历」访问权限；日历数据仅在本机读取，不上传
- ZJU 登录凭据与 DeepSeek API Key 均保存在钥匙串中
