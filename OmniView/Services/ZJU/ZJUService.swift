import Foundation

// MARK: - 模型

struct ZJUSemester: Codable, Identifiable {
    let id: Int
    let name: String
    let isActive: Bool
}

struct ZJUCourse: Codable, Identifiable {
    let id: Int
    let name: String
    let isActive: Bool
    let semesterId: Int
    let time: String
}

struct ZJUUpload: Codable, Identifiable {
    let id: Int
    let referenceId: Int
    let name: String
}

struct ZJUHomework: Codable, Identifiable {
    let id: Int
    let title: String
    let course: String
    let ddl: Date
    let submitted: Bool
    let description: String
    let uploads: [ZJUUpload]
}

struct ZJUMaterial: Codable, Identifiable {
    let id: Int
    let title: String
    let uploads: [ZJUUpload]
}

struct ZJUCourseMaterials: Identifiable {
    let course: ZJUCourse
    let materials: [ZJUMaterial]

    var id: Int { course.id }
}

enum ZJUError: LocalizedError {
    case loginPageUnavailable
    case executionNotFound
    case publicKeyUnavailable
    case rsaEncryptFailed
    case loginFailed(String)
    case notLoggedIn
    case network(String)
    case decoding(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .loginPageUnavailable: return "无法访问统一身份认证页面，请检查网络连接"
        case .executionNotFound: return "登录页面解析失败（execution 缺失）：登录页可能被防火墙拦截或网络异常，请重试"
        case .publicKeyUnavailable: return "获取公钥失败"
        case .rsaEncryptFailed: return "密码加密失败"
        case .loginFailed(let msg): return "登录失败：\(msg)"
        case .notLoggedIn: return "未登录或登录已过期，请先登录"
        case .network(let msg): return "网络错误：\(msg)"
        case .decoding(let msg): return "数据解析错误：\(msg)"
        case .server(let msg): return msg
        }
    }
}

// MARK: - 服务

/// 浙大在线（学在浙大）服务：CAS 登录、课程、作业、课件
/// 登录与数据接口参考 fiz (https://github.com/CrazySpottedDove/fiz)
final class ZJUService {
    static let shared = ZJUService()

    private let homeURL = URL(string: "https://courses.zju.edu.cn")!
    private let loginPageURL = URL(string: "https://zjuam.zju.edu.cn/cas/login")!
    private let publicKeyURL = URL(string: "https://zjuam.zju.edu.cn/cas/v2/getPubKey")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        let headers = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        ]
        config.httpAdditionalHeaders = headers
        session = URLSession(configuration: config)
    }

    var hasSavedAccount: Bool {
        KeychainStore.load(account: "zju_username") != nil
    }

    var savedUsername: String? {
        KeychainStore.load(account: "zju_username")
    }

    // MARK: - 登录

    /// 检查是否已登录（访问首页，若被重定向到 CAS 登录页则未登录）
    func checkLogin() async -> Bool {
        do {
            let (_, response) = try await session.data(from: homeURL)
            guard let http = response as? HTTPURLResponse else { return false }
            let redirected = http.url?.absoluteString.contains("cas/login") ?? false
            return http.statusCode == 200 && !redirected
        } catch {
            return false
        }
    }

    /// 使用已保存的账号静默登录
    func loginWithSavedAccount() async throws {
        guard let username = KeychainStore.load(account: "zju_username"),
              let password = KeychainStore.load(account: "zju_password")
        else {
            throw ZJUError.notLoggedIn
        }
        try await login(username: username, password: password)
    }

    /// CAS 登录（带 execution 解析重试，兼容防火墙挑战页/瞬时故障）
    func login(username: String, password: String) async throws {
        // 1. 获取登录页 execution（失败时自动重试 3 次）
        var execution: String?
        for attempt in 1...3 {
            execution = try? await fetchExecution()
            if execution != nil { break }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        guard let execution else {
            throw ZJUError.executionNotFound
        }

        // 2. 获取 RSA 公钥
        let (keyData, keyResponse) = try await session.data(from: publicKeyURL)
        guard let keyHTTP = keyResponse as? HTTPURLResponse, keyHTTP.statusCode == 200,
              let keyJSON = try? JSONSerialization.jsonObject(with: keyData) as? [String: Any],
              let modulus = keyJSON["modulus"] as? String,
              let exponent = keyJSON["exponent"] as? String
        else {
            throw ZJUError.publicKeyUnavailable
        }

        // 3. 裸 RSA 加密密码
        guard let encrypted = RawRSA.encrypt(password, modulusHex: modulus, exponentHex: exponent) else {
            throw ZJUError.rsaEncryptFailed
        }

        // 4. 提交登录表单
        var request = URLRequest(url: loginPageURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: encrypted),
            URLQueryItem(name: "execution", value: execution),
            URLQueryItem(name: "_eventId", value: "submit"),
            URLQueryItem(name: "authcode", value: ""),
            URLQueryItem(name: "rememberMe", value: "true"),
        ]
        request.httpBody = components.query?.data(using: .utf8)

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ZJUError.loginFailed("未知响应")
            }
            // CAS 成功后会重定向回 service；失败则停留在登录页
            if let finalURL = http.url, finalURL.absoluteString.contains("cas/login") {
                throw ZJUError.loginFailed("请检查学号密码是否正确")
            }
        } catch let error as ZJUError {
            throw error
        } catch {
            throw ZJUError.loginFailed(error.localizedDescription)
        }

        // 5. 保存账号到钥匙串
        try? KeychainStore.save(username, account: "zju_username")
        try? KeychainStore.save(password, account: "zju_password")
    }

    func logout() {
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        try? KeychainStore.delete(account: "zju_password")
    }

    /// 获取登录页并解析 execution（解析失败时附带页面摘要便于排查）
    private func fetchExecution() async throws -> String? {
        let (loginData, loginResponse) = try await session.data(from: loginPageURL)
        guard let loginHTTP = loginResponse as? HTTPURLResponse, loginHTTP.statusCode == 200,
              let html = String(data: loginData, encoding: .utf8)
        else {
            throw ZJUError.loginPageUnavailable
        }
        guard let execution = Self.extractExecution(from: html) else {
            throw ZJUError.executionNotFound
        }
        return execution
    }

    private static func extractExecution(from html: String) -> String? {
        // 兼容多种 HTML 形态：双引号/单引号、属性顺序、属性间空白
        let patterns = [
            #"name=["']execution["'][^>]*value=["']([^"']+)["']"#,
            #"value=["']([^"']+)["'][^>]*name=["']execution["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: html, range: NSRange(html.startIndex..., in: html)
                  ),
                  let range = Range(match.range(at: 1), in: html)
            else {
                continue
            }
            return String(html[range])
        }
        return nil
    }

    // MARK: - 数据请求

    private func getJSON(_ url: URL) async throws -> Any {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw ZJUError.network("无效响应")
            }
            if let finalURL = http.url, finalURL.absoluteString.contains("cas/login") {
                throw ZJUError.notLoggedIn
            }
            guard http.statusCode == 200 else {
                throw ZJUError.server("HTTP \(http.statusCode)")
            }
            do {
                return try JSONSerialization.jsonObject(with: data)
            } catch {
                throw ZJUError.decoding(error.localizedDescription)
            }
        } catch let error as ZJUError {
            throw error
        } catch {
            throw ZJUError.network(error.localizedDescription)
        }
    }

    // MARK: - 学期

    func fetchSemesters() async throws -> [ZJUSemester] {
        guard let url = URL(string: "https://courses.zju.edu.cn/api/my-semesters?") else {
            throw ZJUError.network("无效 URL")
        }
        let json = try await getJSON(url)
        guard let dict = json as? [String: Any],
              let array = dict["semesters"] as? [[String: Any]]
        else {
            throw ZJUError.decoding("semesters 缺失")
        }
        return array.compactMap { item in
            guard let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }
            return ZJUSemester(id: id, name: name, isActive: (item["is_active"] as? Bool) ?? false)
        }
    }

    // MARK: - 课程

    func fetchCourses() async throws -> [ZJUCourse] {
        let urlString = "https://courses.zju.edu.cn/api/my-courses?conditions=%7B%22status%22:%5B%22ongoing%22,%22notStarted%22%5D,%22keyword%22:%22%22,%22classify_type%22:%22recently_started%22,%22display_studio_list%22:false%7D&fields=id,name,semester_id,course_attributes&page=1&page_size=1000"
        guard let url = URL(string: urlString) else {
            throw ZJUError.network("无效 URL")
        }
        let json = try await getJSON(url)
        guard let dict = json as? [String: Any],
              let array = dict["courses"] as? [[String: Any]]
        else {
            throw ZJUError.decoding("courses 缺失")
        }
        return array.compactMap { item in
            guard let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }
            let attributes = item["course_attributes"] as? [String: Any]
            let time = attributes?["time"] as? String ?? ""
            return ZJUCourse(
                id: id, name: name,
                isActive: (item["is_active"] as? Bool) ?? true,
                semesterId: (item["semester_id"] as? Int) ?? 0,
                time: time
            )
        }
    }

    // MARK: - 作业

    func fetchHomeworks(for course: ZJUCourse) async throws -> [ZJUHomework] {
        let urlString = "https://courses.zju.edu.cn/api/courses/\(course.id)/homework-activities?page=1&page_size=1000"
        guard let url = URL(string: urlString) else {
            throw ZJUError.network("无效 URL")
        }
        let json = try await getJSON(url)
        guard let dict = json as? [String: Any],
              let array = dict["homework_activities"] as? [[String: Any]]
        else {
            throw ZJUError.decoding("homework_activities 缺失")
        }
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return array.compactMap { item in
            if (item["is_closed"] as? Bool) == true { return nil }
            guard let id = item["id"] as? Int,
                  let title = item["title"] as? String,
                  let deadlineString = item["deadline"] as? String,
                  let ddl = dateFormatter.date(from: deadlineString)
                      ?? ISO8601DateFormatter().date(from: deadlineString)
            else {
                return nil
            }
            let submitted = (item["submitted"] as? Bool) ?? false
            let description = (item["data"] as? [String: Any])?["description"] as? String ?? ""
            let uploads: [ZJUUpload] = (item["uploads"] as? [[String: Any]])?.compactMap { upload in
                guard let uploadID = upload["id"] as? Int,
                      let name = upload["name"] as? String
                else { return nil }
                return ZJUUpload(
                    id: uploadID,
                    referenceId: (upload["reference_id"] as? Int) ?? 0,
                    name: name
                )
            } ?? []
            return ZJUHomework(
                id: id, title: title, course: course.name, ddl: ddl,
                submitted: submitted, description: description, uploads: uploads
            )
        }
    }

    /// 获取所有课程（进行中）的作业
    func fetchAllHomeworks() async throws -> [ZJUHomework] {
        let courses = try await fetchCourses()
        var result: [ZJUHomework] = []
        for course in courses where course.isActive {
            if let homeworks = try? await fetchHomeworks(for: course) {
                result.append(contentsOf: homeworks)
            }
        }
        return result.sorted { $0.ddl < $1.ddl }
    }

    // MARK: - 课件

    func fetchMaterials(for course: ZJUCourse) async throws -> [ZJUMaterial] {
        let conditions = "%7B%22category%22:null,%22itemsSortBy%22:%7B%22predicate%22:%22chapter%22,%22reverse%22:false%7D,%22ignore_activity_types%22:%5B%22lesson%22%5D%7D"
        let urlString = "https://courses.zju.edu.cn/api/course/\(course.id)/coursewares?conditions=\(conditions)&page=1&page_size=1000"
        guard let url = URL(string: urlString) else {
            throw ZJUError.network("无效 URL")
        }
        let json = try await getJSON(url)
        guard let dict = json as? [String: Any],
              let array = dict["activities"] as? [[String: Any]]
        else {
            throw ZJUError.decoding("activities 缺失")
        }
        return array.compactMap { item in
            guard let id = item["id"] as? Int,
                  let title = item["title"] as? String
            else { return nil }
            let uploads: [ZJUUpload] = (item["uploads"] as? [[String: Any]])?.compactMap { upload in
                guard let uploadID = upload["id"] as? Int,
                      let name = upload["name"] as? String
                else { return nil }
                return ZJUUpload(
                    id: uploadID,
                    referenceId: (upload["reference_id"] as? Int) ?? 0,
                    name: name
                )
            } ?? []
            return ZJUMaterial(id: id, title: title, uploads: uploads)
        }
    }

    func fetchAllMaterials() async throws -> [ZJUCourseMaterials] {
        let courses = try await fetchCourses()
        var result: [ZJUCourseMaterials] = []
        for course in courses where course.isActive {
            if let materials = try? await fetchMaterials(for: course) {
                result.append(ZJUCourseMaterials(course: course, materials: materials))
            }
        }
        return result
    }

    // MARK: - 下载

    func downloadURL(for upload: ZJUUpload, previewOffice: Bool = true) -> URL? {
        let isOffice = upload.name.lowercased().hasSuffix(".docx")
            || upload.name.lowercased().hasSuffix(".doc")
            || upload.name.lowercased().hasSuffix(".pptx")
            || upload.name.lowercased().hasSuffix(".ppt")
            || upload.name.lowercased().hasSuffix(".xlsx")
            || upload.name.lowercased().hasSuffix(".xls")
        if previewOffice && isOffice {
            return URL(string: "https://courses.zju.edu.cn/api/uploads/document/\(upload.id)/url?preview=true")
        }
        return URL(string: "https://courses.zju.edu.cn/api/uploads/\(upload.id)/blob")
    }

    /// 下载附件到目标位置（带进度回调）
    func download(upload: ZJUUpload, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard let url = downloadURL(for: upload) else {
            throw ZJUError.network("无效下载地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZJUError.network("无效响应")
        }
        if let finalURL = http.url, finalURL.absoluteString.contains("cas/login") {
            throw ZJUError.notLoggedIn
        }
        guard http.statusCode == 200 else {
            throw ZJUError.server("下载失败：HTTP \(http.statusCode)")
        }
        try data.write(to: destination, options: .atomic)
        progress(1.0)
    }
}
