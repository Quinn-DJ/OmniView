import SwiftUI

/// 设置窗口：教务网登录 / DeepSeek API Key
/// 通过 SwiftUI `Settings` scene 接入，菜单栏「OmniView → 设置…」(⌘,)
struct SettingsView: View {
    var body: some View {
        TabView {
            ZJUSettingsTab()
                .tabItem { Label("教务网", systemImage: "graduationcap") }
            DeepSeekSettingsTab()
                .tabItem { Label("DeepSeek", systemImage: "brain") }
        }
        .frame(width: 480, height: 340)
    }
}

// MARK: - 教务网

struct ZJUSettingsTab: View {
    @EnvironmentObject private var viewModel: ZJUViewModel
    @State private var isSecured = true

    var body: some View {
        Form {
            Section("账号状态") {
                LabeledContent("登录状态") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isLoggedIn ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isLoggedIn ? "已登录" : "未登录")
                            .foregroundStyle(viewModel.isLoggedIn ? .green : .secondary)
                    }
                }
                if viewModel.isLoggedIn {
                    LabeledContent("账号") {
                        Text(viewModel.username.isEmpty ? "—" : viewModel.username)
                            .textSelection(.enabled)
                    }
                    Button("退出登录", role: .destructive) {
                        viewModel.logout()
                    }
                }
            }

            if !viewModel.isLoggedIn {
                Section("登录学在浙大") {
                    TextField("学号", text: $viewModel.username)
                    HStack {
                        Group {
                            if isSecured {
                                SecureField("统一身份认证密码", text: $viewModel.password)
                            } else {
                                TextField("统一身份认证密码", text: $viewModel.password)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button {
                            isSecured.toggle()
                        } label: {
                            Image(systemName: isSecured ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                    }
                    if let error = viewModel.loginError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await viewModel.login() }
                    } label: {
                        if viewModel.isLoggingIn {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("登录")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoggingIn
                        || viewModel.username.isEmpty
                        || viewModel.password.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - DeepSeek

struct DeepSeekSettingsTab: View {
    @EnvironmentObject private var viewModel: DeepSeekViewModel

    var body: some View {
        Form {
            Section("API Key") {
                LabeledContent("状态") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.hasAPIKey ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(viewModel.hasAPIKey ? "已配置" : "未配置")
                            .foregroundStyle(viewModel.hasAPIKey ? .green : .secondary)
                    }
                }
                if viewModel.hasAPIKey {
                    LabeledContent("当前 Key") {
                        Text(maskedKey)
                            .textSelection(.enabled)
                    }
                    Button("清除 API Key", role: .destructive) {
                        viewModel.clearAPIKey()
                    }
                }
            }

            Section(viewModel.hasAPIKey ? "更新 API Key" : "配置 API Key") {
                SecureField("sk-…", text: $viewModel.apiKeyInput)
                Text("API Key 仅保存在本机钥匙串中，用于查询 DeepSeek 官方余额与用量接口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    viewModel.saveAPIKey()
                } label: {
                    Text("保存")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private var maskedKey: String {
        // 只展示前缀与末四位
        guard let stored = KeychainStore.load(account: "deepseek_api_key"), stored.count > 8 else {
            return "—"
        }
        let prefix = stored.prefix(6)
        let suffix = stored.suffix(4)
        return "\(prefix)••••••\(suffix)"
    }
}
