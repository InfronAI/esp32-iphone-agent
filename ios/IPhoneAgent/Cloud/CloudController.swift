import SwiftUI
import WidgetKit

@MainActor final class CloudController: ObservableObject {
    static let shared = CloudController()
    @Published private(set) var address: String
    @Published private(set) var status: CloudBoardStatus?
    @Published private(set) var connected = false
    @Published private(set) var authenticated = false
    @Published private(set) var signingIn = false
    @Published private(set) var loginError = ""
    @Published private(set) var statusDate: Date?
    private var sessionToken = ""
    private let configuration: URLSessionConfiguration
    @Published private(set) var connectionError = ""
    @Published var notice = ""
    @Published var goal: String { didSet { UserDefaults.standard.set(goal, forKey: "cloud.goal") } }
    @Published private(set) var busy = false
    @Published private(set) var stopping = false
    @Published private(set) var image: UIImage?
    @Published private(set) var imageDate: Date?
    @Published private(set) var calibrating = false
    @Published private(set) var calibrationImageReady = false
    @Published private var phoneUSB = PhoneUSBConfirmation()
    private var api: BoardAPI?
    private var generation = 0
    private var refreshing = false

    var token: String { sessionToken }
    var currentStatus: CloudBoardStatus? {
        guard authenticated, connected, var value = status, let statusDate,
              Date().timeIntervalSince(statusDate) < 8 else { return nil }
        if value.frame_age_ms >= 0 { value.frame_age_ms += max(0, Date().timeIntervalSince(statusDate) * 1000) }
        return value
    }
    var phoneUSBConfirmed: Bool { currentStatus?.phone_usb_confirmed ?? phoneUSB.confirmed }
    var readiness: DeviceReadiness {
        DeviceReadiness(connected: currentStatus != nil, status: currentStatus, phoneUSBConfirmed: phoneUSBConfirmed)
    }
    var readyToStart: Bool { currentStatus?.canStart == true && phoneUSBConfirmed && !busy && !calibrating }
    var readyToCalibrate: Bool { currentStatus?.canCalibrate == true && phoneUSBConfirmed && !busy }
    var boardWorking: Bool { currentStatus?.isWorking == true }
    var readyToInspect: Bool {
        currentStatus?.hasFrame == true && status?.time_synced != false && !busy && !boardWorking && !calibrating
    }

    func confirmPhoneUSB() async {
        await perform("phone-host", body: ["confirmed": true], message: "已向 ESP32 确认 USB 接到 iPhone，网页将同步此状态。")
    }
    func clearPhoneUSBConfirmation() async {
        await perform("phone-host", body: ["confirmed": false], message: "已清除手机接线确认。")
    }

    init(defaultAddress: String = "iphone-agent.local", configuration: URLSessionConfiguration = .ephemeral,
         registerHandlers: Bool = true) {
        self.configuration = configuration
        address = registerHandlers ? (UserDefaults.standard.string(forKey: "cloud.login.address") ?? defaultAddress) : defaultAddress
        goal = UserDefaults.standard.string(forKey: "cloud.goal") ?? ""
        // A cold launch always starts at login. A preset or old Keychain entry is not a session.
        guard registerHandlers else { return }
        AgentRequests.handle = { [weak self] request in
            guard let self else { return AgentRequests.unavailable }
            guard self.authenticated else { return "请先打开 ESP32 Agent，输入控制令牌登录。" }
            switch request {
            case .status:
                await self.refresh()
                return self.connected ? (self.status?.title ?? "已连接") : self.connectionError
            case .runTask(let text):
                self.goal = text
                await self.refresh()
                await self.start()
                return self.notice
            case .runSaved, .calibrate:
                return "请打开 ESP32 Agent，在 Wi-Fi 控制台中下发任务或校准指针。"
            }
        }
        AgentControl.handle = { [weak self] command in
            if command == .stop { await self?.stop() }
        }
        // Old BLE run widgets must not claim the new board controller is ready.
        SharedState.save(AgentSnapshot(status: .offline))
        WidgetCenter.shared.reloadAllTimelines()
        saveDiagnostics()
    }

    func connect(address: String, token: String) async {
        guard !signingIn, !authenticated else { return }
        signingIn = true; loginError = ""
        let version = generation
        var candidate: BoardAPI?
        defer {
            if version == generation { signingIn = false }
            candidate?.close()
        }
        do {
            let client = try BoardAPI(address: address, token: token, configuration: configuration)
            candidate = client
            // Enter the dashboard only after an authenticated response from this board.
            let value = try await client.status()
            guard version == generation else { return }
            self.address = client.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            UserDefaults.standard.set(self.address, forKey: "cloud.login.address")
            sessionToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            api = client; candidate = nil
            authenticated = true
            notice = ""
            accept(value)
        } catch {
            guard version == generation else { return }
            loginError = (error as? CloudBoardError)?.statusCode == 401 ? error.localizedDescription :
                "登录失败：" + error.localizedDescription + "\n请确认同一局域网和本地网络权限；若 .local 无法解析，可改填板子 IP。"
        }
    }

    func logout(message: String = "") {
        generation += 1
        api?.close(); api = nil; sessionToken = ""
        authenticated = false; signingIn = false; refreshing = false
        busy = false; stopping = false
        invalidateStatus()
        statusDate = nil; notice = ""; connectionError = ""; loginError = message
        saveDiagnostics()
    }

    private func invalidateStatus() {
        connected = false; status = nil; image = nil; imageDate = nil
        phoneUSB = PhoneUSBConfirmation()
        calibrating = false; calibrationImageReady = false
        SharedState.save(AgentSnapshot(status: .offline))
    }

    func expireStatus(now: Date = Date()) {
        guard authenticated, connected, let statusDate, now.timeIntervalSince(statusDate) >= 8 else { return }
        invalidateStatus()
        connectionError = "状态已过期，正在重新读取 ESP32。"
        saveDiagnostics()
    }

    private func accept(_ value: CloudBoardStatus) {
        status = value; statusDate = Date(); connected = true; connectionError = ""
        phoneUSB.observe(connected: true, status: value)
        if !phoneUSBConfirmed { calibrating = false; calibrationImageReady = false }
        if !value.hasFrame { image = nil; imageDate = nil; calibrationImageReady = false }
        var snapshot = AgentSnapshot(status: value.running ? .running : (value.canStart && phoneUSBConfirmed ? .ready : .needsSetup))
        snapshot.step = value.steps
        if SharedState.load() != snapshot {
            SharedState.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
        saveDiagnostics()
    }

    @discardableResult private func handleUnauthorized(_ error: Error) -> Bool {
        guard (error as? CloudBoardError)?.statusCode == 401 else { return false }
        logout(message: error.localizedDescription)
        return true
    }

    func refresh() async {
        guard authenticated, let api, !refreshing else { return }
        let version = generation
        refreshing = true
        defer { if version == generation { refreshing = false } }
        do {
            let value = try await api.status()
            guard version == generation else { return }
            accept(value)
        } catch {
            guard version == generation, !handleUnauthorized(error) else { return }
            invalidateStatus()
            connectionError = "连接已中断，正在重试。\n" + error.localizedDescription
            saveDiagnostics()
        }
    }

    private func saveDiagnostics() {
        // No tokens, screenshots, goals or cloud credentials in diagnostics.
        let values: [String: Any] = ["connected": connected, "authenticated": authenticated, "address": address,
            "state": status?.state ?? "", "video": status?.video ?? "", "error": connectionError,
            "updated": ISO8601DateFormatter().string(from: Date())]
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? JSONSerialization.data(withJSONObject: values, options: .prettyPrinted) {
            try? data.write(to: dir.appendingPathComponent("board-connection.json"), options: .atomic)
        }
    }

    func start() async {
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 1024 else { notice = "任务不能为空，且不能超过 1024 字节。"; return }
        guard readyToStart else { notice = "请先完成镜像、USB 连接和指针校准。"; return }
        await perform("start", body: ["goal": text], message: "任务已交给 ESP32。可以切换到目标 App；请保持屏幕解锁和镜像开启。")
    }

    func stop() async {
        guard authenticated, let api, !stopping else { return }
        let version = generation
        stopping = true
        defer { if version == generation { stopping = false } }
        do {
            try await api.command("stop")
            guard version == generation else { return }
            calibrating = false; calibrationImageReady = false
            notice = "ESP32 已确认停止。"
        } catch { if version == generation, !handleUnauthorized(error) { notice = "停止未确认：" + error.localizedDescription } }
        await refresh()
    }

    func testCloud() async {
        guard connected, !boardWorking, !calibrating else { return }
        await perform("test", message: "正在检查云端连接，结果会显示在任务进展中。")
    }
    func loadCloudConfig() async throws -> CloudLLMConfig {
        guard connected, let api else { throw CloudBoardError(message: "请先连接 ESP32。") }
        let version = generation
        let config: CloudLLMConfig
        do { config = try await api.cloudConfig() }
        catch { if version == generation { handleUnauthorized(error) }; throw error }
        guard version == generation else { throw CloudBoardError(message: "设备连接已改变，请重新读取配置。") }
        return config
    }
    func saveCloudConfig(endpoint: String, model: String, key: String) async throws -> CloudLLMConfig {
        guard connected, let api else { throw CloudBoardError(message: "请先连接 ESP32。") }
        guard !busy, !boardWorking, !calibrating else { throw CloudBoardError(message: "请先等待任务或校准结束。") }
        let version = generation
        busy = true
        defer { if version == generation { busy = false } }
        let config: CloudLLMConfig
        do { config = try await api.saveCloudConfig(endpoint: endpoint, model: model, key: key) }
        catch { if version == generation { handleUnauthorized(error) }; throw error }
        guard version == generation else { throw CloudBoardError(message: "设备连接已改变，请检查当前板子的配置。") }
        notice = "云端配置已保存到 ESP32，重启后仍然有效。"
        return config
    }
    func testVision() async {
        guard readyToInspect else { notice = "请先连接 ESP32 并开启屏幕镜像，等待当前任务结束。"; return }
        await perform("vision-test", message: "已启动「读懂当前屏幕」，识别结果会自动显示在下方。")
    }

    func startExample(_ example: CloudTaskExample) async {
        if example == .describeScreen { await testVision() }
        else { goal = example.goal; await start() }
    }

    private func perform(_ command: String, body: [String: Any] = [:], message: String) async {
        guard authenticated, connected, let api, !busy else { return }
        let version = generation
        busy = true
        defer { if version == generation { busy = false } }
        do {
            try await api.command(command, body: body)
            guard version == generation else { return }
            notice = message
        } catch { if version == generation, !handleUnauthorized(error) { notice = error.localizedDescription } }
        await refresh()
    }

    func snapshot() async {
        guard authenticated, connected, let api, !busy else { return }
        let version = generation
        busy = true
        defer { if version == generation { busy = false } }
        do {
            let data = try await api.snapshot()
            guard version == generation else { return }
            guard let photo = UIImage(data: data) else { throw CloudBoardError(message: "板子返回的截图无法读取。") }
            image = photo; imageDate = Date(); calibrationImageReady = calibrating
        } catch {
            if version == generation, !handleUnauthorized(error) { image = nil; imageDate = nil; calibrationImageReady = false; notice = error.localizedDescription }
        }
    }

    func beginCalibration() async {
        guard let api, readyToCalibrate else { return }
        let version = generation
        busy = true
        defer { if version == generation { busy = false } }
        do {
            try await api.command("calibration-begin")
            guard version == generation else { return }
            calibrating = true; calibrationImageReady = false; image = nil; imageDate = nil
            notice = "等待手机指针停止后，点击「刷新截图」，再在截图中点一下指针中心。"
        } catch { if version == generation, !handleUnauthorized(error) { notice = error.localizedDescription } }
    }

    func finishCalibration(x: Double, y: Double) async {
        guard calibrating, calibrationImageReady, connected, phoneUSBConfirmed, let date = imageDate,
              Date().timeIntervalSince(date) < 15 else { notice = "请刷新截图后重新点击指针。"; return }
        await perform("calibration-finish", body: ["x": x, "y": y], message: "指针校准已保存到 ESP32。")
        if status?.calibrated == true && notice == "指针校准已保存到 ESP32。" {
            calibrating = false; calibrationImageReady = false
        }
    }
}
