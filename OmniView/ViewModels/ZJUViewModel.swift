import Combine
import Foundation

/// 浙大在线视图模型：登录、作业、课件
final class ZJUViewModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var isLoggingIn = false
    @Published var loginError: String?
    @Published var username: String = ""
    @Published var password: String = ""

    @Published var homeworks: [ZJUHomework] = []
    @Published var courseMaterials: [ZJUCourseMaterials] = []
    @Published var isLoadingHomework = false
    @Published var isLoadingMaterials = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    // 下载状态
    @Published var downloadProgress: [Int: Double] = [:]
    @Published var downloadErrors: [Int: String] = [:]

    private let service = ZJUService.shared

    var hasSavedAccount: Bool { service.hasSavedAccount }

    /// 启动时检查登录状态
    func checkLoginState() async {
        let loggedIn = await service.checkLogin()
        await MainActor.run {
            isLoggedIn = loggedIn
            username = service.savedUsername ?? ""
            if loggedIn {
                lastUpdated = nil
            }
        }
    }

    func login() async {
        await MainActor.run {
            isLoggingIn = true
            loginError = nil
        }
        do {
            try await service.login(username: username, password: password)
            await MainActor.run {
                isLoggedIn = true
                loginError = nil
            }
        } catch {
            await MainActor.run {
                loginError = error.localizedDescription
            }
        }
        await MainActor.run { isLoggingIn = false }
    }

    func loginWithSavedAccount() async {
        do {
            try await service.loginWithSavedAccount()
            await MainActor.run {
                isLoggedIn = true
                loginError = nil
            }
        } catch {
            await MainActor.run {
                isLoggedIn = false
            }
        }
    }

    func logout() {
        service.logout()
        isLoggedIn = false
        homeworks = []
        courseMaterials = []
    }

    func refreshHomework() async {
        guard isLoggedIn else { return }
        await MainActor.run {
            isLoadingHomework = true
            errorMessage = nil
        }
        do {
            let result = try await service.fetchAllHomeworks()
            await MainActor.run {
                homeworks = result
                lastUpdated = Date()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        await MainActor.run { isLoadingHomework = false }
    }

    func refreshMaterials() async {
        guard isLoggedIn else { return }
        await MainActor.run {
            isLoadingMaterials = true
            errorMessage = nil
        }
        do {
            let result = try await service.fetchAllMaterials()
            await MainActor.run {
                courseMaterials = result
                lastUpdated = Date()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        await MainActor.run { isLoadingMaterials = false }
    }

    /// 下载课件附件
    func download(upload: ZJUUpload, to destination: URL) async {
        await MainActor.run {
            downloadProgress[upload.id] = 0
            downloadErrors[upload.id] = nil
        }
        do {
            try await service.download(upload: upload, to: destination) { progress in
                DispatchQueue.main.async {
                    self.downloadProgress[upload.id] = progress
                }
            }
            await MainActor.run {
                downloadProgress[upload.id] = 1.0
            }
        } catch {
            await MainActor.run {
                downloadErrors[upload.id] = error.localizedDescription
            }
        }
    }
}
