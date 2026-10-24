import Foundation

struct CloudBoardStatus: Decodable {
    let state: String
    let detail: String
    let running: Bool
    let steps: Int
    let ip: String
    let usb: String
    let airplay: Int
    let video: String
    var frame_age_ms: Double
    let calibrated: Bool
    let time_synced: Bool?
    let uptime_ms: Double?
    let wifi_connected: Bool?
    let wifi_ssid: String?
    let wifi_rssi: Int?
    let phone_usb_confirmed: Bool?

    var isWorking: Bool { running || ["starting", "testing", "vision_testing"].contains(state) }
    var hasFrame: Bool { airplay == 2 && video.isEmpty && frame_age_ms >= 0 && frame_age_ms < 5000 }
    var canCalibrate: Bool { !isWorking && usb == "ok" && hasFrame }
    var canStart: Bool { canCalibrate && calibrated && time_synced != false }
    var title: String {
        switch state {
        case "idle": return "等待任务"
        case "starting": return "任务已接收"
        case "thinking": return "云端模型正在分析"
        case "acting": return "正在操作手机"
        case "done": return "任务已结束"
        case "stopped": return "已停止"
        case "test_ok": return "云端连接测试通过"
        case "testing": return "正在测试云端连接"
        case "vision_testing": return "云端正在识别画面"
        case "vision_ok": return "画面识别测试通过"
        case "paused": return "任务已暂停"
        case "error", "test_failed": return "需要处理"
        default: return state
        }
    }
}

struct CloudBoardError: LocalizedError {
    let message: String
    var statusCode: Int? = nil
    var errorDescription: String? { message }
}

struct CloudLLMConfig: Decodable {
    let endpoint: String
    let model: String
    let key_set: Bool
}

/// Only local destinations are accepted, and credentials never follow HTTP redirects.
final class BoardAPI: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let baseURL: URL
    private let token: String
    private var session: URLSession!

    static func localURL(_ address: String) throws -> URL {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = text.contains("://") ? text : "http://" + text
        guard let c = URLComponents(string: value), c.scheme == "http" || c.scheme == "https",
              let host = c.host?.lowercased(), !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", c.port == nil || (1...65535).contains(c.port!)
        else { throw CloudBoardError(message: "请输入板子的局域网地址，例如 10.10.18.150。") }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let parts = labels.compactMap { UInt8($0) }
        let privateIP = labels.count == 4 && parts.count == 4 && (parts[0] == 10 ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 169 && parts[1] == 254))
        guard privateIP || (host.hasSuffix(".local") && host.count > 6), let url = c.url else {
            throw CloudBoardError(message: "仅支持局域网 IPv4 地址或 .local 主机名。")
        }
        return url
    }

    init(address: String, token: String, configuration: URLSessionConfiguration = .ephemeral) throws {
        baseURL = try Self.localURL(address)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw CloudBoardError(message: "请输入 ESP32 的控制令牌。")
        }
        self.token = token
        super.init()
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func close() { session.invalidateAndCancel() }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    private func request(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/" + path))
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CloudBoardError(message: "板子没有返回 HTTP 响应。")
        }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 { throw CloudBoardError(message: "控制令牌不正确或已失效，请重新登录。", statusCode: 401) }
            let text = String(data: data.prefix(1024), encoding: .utf8) ?? ""
            throw CloudBoardError(message: "ESP32（\(response.statusCode)）：\(text)", statusCode: response.statusCode)
        }
        return data
    }

    func status() async throws -> CloudBoardStatus { try JSONDecoder().decode(CloudBoardStatus.self, from: await request("status")) }
    func cloudConfig() async throws -> CloudLLMConfig { try JSONDecoder().decode(CloudLLMConfig.self, from: await request("config")) }
    func saveCloudConfig(endpoint: String, model: String, key: String) async throws -> CloudLLMConfig {
        var body = ["endpoint": endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                    "model": model.trimmingCharacters(in: .whitespacesAndNewlines)]
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { body["api_key"] = key }
        return try JSONDecoder().decode(CloudLLMConfig.self, from: await request("config", body: body))
    }
    func snapshot() async throws -> Data { try await request("snapshot") }
    func command(_ name: String, body: [String: Any] = [:]) async throws { _ = try await request(name, body: body) }
}
