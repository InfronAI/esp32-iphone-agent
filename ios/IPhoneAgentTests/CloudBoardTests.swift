import XCTest
@testable import IPhoneAgent

private final class BoardURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class CloudBoardTests: XCTestCase {
    private let fixture = #"{"state":"idle","detail":"","running":false,"steps":0,"ip":"10.10.18.150","usb":"ok","airplay":2,"video":"","frame_age_ms":200,"calibrated":true,"time_synced":true,"phone_usb_confirmed":true}"#

    func testLocalAddressesAndCredentialBoundaries() throws {
        for host in ["10.10.18.150", "http://192.168.4.1", "https://172.16.1.2:8080", "iphone-agent.local"] {
            XCTAssertNotNil(try BoardAPI.localURL(host))
        }
        for host in ["https://example.com", "http://10.0.0.1@example.com", "10.foo.0.0.1", "10.0.0.1/path", "10.0.0.1?x=1", "8.8.8.8", "172.32.0.1", "file:///tmp"] {
            XCTAssertThrowsError(try BoardAPI.localURL(host), host)
        }
    }

    func testStartRequiresFreshDecodedFrameUSBAndCalibration() throws {
        let data = Data(fixture.utf8)
        XCTAssertTrue(try JSONDecoder().decode(CloudBoardStatus.self, from: data).canStart)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (field, value) in [("frame_age_ms", -1 as Any), ("frame_age_ms", 5000), ("usb", "off"),
                               ("calibrated", false), ("running", true), ("airplay", 0),
                               ("video", "H.264 decode failed"), ("time_synced", false),
                               ("state", "testing"), ("state", "vision_testing")] {
            let old = json[field]
            json[field] = value
            let status = try JSONDecoder().decode(CloudBoardStatus.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertFalse(status.canStart, field)
            json[field] = old
        }
    }

    private func status(_ changes: [String: Any] = [:]) throws -> CloudBoardStatus {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any])
        changes.forEach { json[$0.key] = $0.value }
        return try JSONDecoder().decode(CloudBoardStatus.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testUSBHostDetectionDoesNotClaimPhoneReady() throws {
        let s = try status(["calibrated": false])
        let readiness = DeviceReadiness(connected: true, status: s, phoneUSBConfirmed: false)
        XCTAssertEqual(readiness.completedCount, 3)
        XCTAssertEqual(readiness.check(.usb).level, .pending)
        XCTAssertEqual(readiness.firstMissing(for: .checkWiFi), .usb)
        // The first-use vision example works even while USB is connected to the Mac.
        XCTAssertNil(readiness.firstMissing(for: .describeScreen))
        let unplugged = DeviceReadiness(connected: true, status: try status(["usb": "off", "calibrated": false]), phoneUSBConfirmed: false)
        XCTAssertNil(unplugged.firstMissing(for: .describeScreen))
    }

    func testExamplesRouteToTheFirstMissingPrerequisite() throws {
        let offline = DeviceReadiness(connected: false, status: try status(), phoneUSBConfirmed: true)
        XCTAssertEqual(offline.completedCount, 0)
        XCTAssertEqual(offline.firstMissing(for: .describeScreen), .connection)
        for (changes, expected) in [(["airplay": 0], DeviceCheck.mirroring),
                                    (["frame_age_ms": 5000], .picture),
                                    (["time_synced": false], .connection)] as [([String: Any], DeviceCheck)] {
            let readiness = DeviceReadiness(connected: true, status: try status(changes), phoneUSBConfirmed: true)
            XCTAssertEqual(readiness.firstMissing(for: .describeScreen), expected)
        }
        let needsCalibration = DeviceReadiness(connected: true, status: try status(["calibrated": false]), phoneUSBConfirmed: true)
        XCTAssertEqual(needsCalibration.firstMissing(for: .checkWiFi), .calibration)
        let ready = DeviceReadiness(connected: true, status: try status(), phoneUSBConfirmed: true)
        XCTAssertEqual(ready.completedCount, 5)
        XCTAssertNil(ready.firstMissing(for: .checkWiFi))
    }

    func testUSBConfirmationExpiresOnDisconnectOrBoardRestart() throws {
        var confirmation = PhoneUSBConfirmation()
        let initial = try status(["uptime_ms": 1000])
        confirmation.observe(connected: true, status: initial)
        confirmation.confirm(connected: true, status: initial)
        XCTAssertTrue(confirmation.confirmed)
        confirmation.observe(connected: true, status: try status(["uptime_ms": 2000]))
        XCTAssertTrue(confirmation.confirmed)
        confirmation.observe(connected: true, status: try status(["uptime_ms": 100]))
        XCTAssertFalse(confirmation.confirmed)
        confirmation.confirm(connected: true, status: initial)
        confirmation.observe(connected: true, status: try status(["usb": "off"]))
        XCTAssertFalse(confirmation.confirmed)
        confirmation.confirm(connected: true, status: initial)
        confirmation.observe(connected: false, status: nil)
        XCTAssertFalse(confirmation.confirmed)
        confirmation.confirm(connected: false, status: initial)
        XCTAssertFalse(confirmation.confirmed)
    }

    func testAuthenticatedStatusAndRejectedToken() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [BoardURLProtocol.self]
        let api = try BoardAPI(address: "10.10.18.150", token: "local-test-token", configuration: cfg)
        defer { api.close(); BoardURLProtocol.handler = nil }
        let body = Data(fixture.utf8)
        BoardURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/status")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-test-token")
            return (200, body)
        }
        let status = try await api.status()
        XCTAssertTrue(status.canStart)
        BoardURLProtocol.handler = { _ in (401, Data("Control token required".utf8)) }
        do { _ = try await api.status(); XCTFail("Should reject authentication failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("控制令牌")) }
    }

    func testCommandsUseJSONAndPropagateBoardFailure() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [BoardURLProtocol.self]
        let api = try BoardAPI(address: "10.10.18.150", token: "local-test-token", configuration: cfg)
        defer { api.close(); BoardURLProtocol.handler = nil }
        BoardURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/start")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (409, Data("err No fresh decoded frame".utf8))
        }
        do { try await api.command("start", body: ["goal": "打开设置"]); XCTFail("Should reject an unready board") }
        catch { XCTAssertTrue(error.localizedDescription.contains("No fresh decoded frame")) }
    }

    func testCloudConfigurationPreservesBlankKeyAndAcceptsReplacement() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [BoardURLProtocol.self]
        let api = try BoardAPI(address: "10.10.18.150", token: "local-test-token", configuration: cfg)
        defer { api.close(); BoardURLProtocol.handler = nil }
        let response = Data(#"{"endpoint":"https://example.com/v1/chat/completions","model":"vision-model","key_set":true}"#.utf8)
        BoardURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/config")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-test-token")
            return (200, response)
        }
        let config = try await api.cloudConfig()
        XCTAssertTrue(config.key_set)
        XCTAssertEqual(config.model, "vision-model")
        for key in ["", "new-test-key"] {
            BoardURLProtocol.handler = { request in
                XCTAssertEqual(request.url?.path, "/api/config")
                XCTAssertEqual(request.httpMethod, "POST")
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 2048)
                let length = stream.read(&buffer, maxLength: buffer.count)
                XCTAssertGreaterThan(length, 0)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(buffer.prefix(max(0, length)))) as? [String: String])
                XCTAssertEqual(body["endpoint"], "https://example.com/v1/chat/completions")
                XCTAssertEqual(body["model"], "vision-model")
                XCTAssertEqual(body["api_key"], key.isEmpty ? nil : key)
                return (200, response)
            }
            let saved = try await api.saveCloudConfig(endpoint: " https://example.com/v1/chat/completions ", model: " vision-model ", key: key)
            XCTAssertTrue(saved.key_set)
        }
        BoardURLProtocol.handler = { _ in (409, Data("请先等待当前任务结束".utf8)) }
        do { _ = try await api.saveCloudConfig(endpoint: config.endpoint, model: config.model, key: ""); XCTFail("Busy config should be rejected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("请先等待当前任务结束")) }
    }

    func testTaskCatalogHasAtLeastTenPhoneExamplesAndBoundedReadOnlyGoals() {
        XCTAssertGreaterThanOrEqual(CloudTaskExample.phoneExamples.count, 10)
        XCTAssertEqual(Set(CloudTaskExample.allCases.map(\.id)).count, CloudTaskExample.allCases.count)
        XCTAssertFalse(CloudTaskExample.phoneExamples.contains(.describeScreen))
        for example in CloudTaskExample.phoneExamples {
            XCTAssertLessThanOrEqual(example.goal.utf8.count, 1024)
            XCTAssertTrue(example.goal.contains("只查看"))
            XCTAssertFalse(example.title.isEmpty)
        }
    }

    func testSetupRoutesOnlySupportedSystemSettingsAndKeepsCalibrationInApp() {
        XCTAssertEqual(DeviceSettingsDestination.destination(for: .connection, connected: false, assistiveTouchEnabled: false), .appPermissions)
        XCTAssertEqual(DeviceSettingsDestination.destination(for: .connection, connected: true, assistiveTouchEnabled: false), .guide)
        XCTAssertEqual(DeviceSettingsDestination.destination(for: .usb, connected: true, assistiveTouchEnabled: false), .assistiveTouch)
        XCTAssertEqual(DeviceSettingsDestination.destination(for: .usb, connected: true, assistiveTouchEnabled: true), .assistiveTouchDevices)
        for check in [DeviceCheck.mirroring, .picture, .calibration] {
            XCTAssertEqual(DeviceSettingsDestination.destination(for: check, connected: true, assistiveTouchEnabled: true), .guide)
        }
    }

    @MainActor func testControllerLoginRequiresSuccessfulBoardAuthentication() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [BoardURLProtocol.self]
        let controller = CloudController(defaultAddress: "iphone-agent.local", configuration: cfg, registerHandlers: false)
        defer { controller.logout(); BoardURLProtocol.handler = nil }
        var requests = 0
        BoardURLProtocol.handler = { _ in requests += 1; return (401, Data()) }
        await controller.refresh()
        XCTAssertEqual(requests, 0)
        XCTAssertFalse(controller.authenticated)
        XCTAssertNil(controller.status)
        await controller.connect(address: "iphone-agent.local", token: "incorrect-token")
        XCTAssertFalse(controller.authenticated)
        XCTAssertFalse(controller.connected)
        XCTAssertTrue(controller.token.isEmpty)
        XCTAssertTrue(controller.loginError.contains("控制令牌"))
        let body = Data(fixture.utf8)
        BoardURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "iphone-agent.local")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer correct-token")
            return (200, body)
        }
        await controller.connect(address: "iphone-agent.local", token: "correct-token")
        XCTAssertTrue(controller.authenticated)
        XCTAssertTrue(controller.connected)
        XCTAssertEqual(controller.status?.ip, "10.10.18.150")
        controller.logout()
        XCTAssertFalse(controller.authenticated)
        XCTAssertNil(controller.status)
        XCTAssertTrue(controller.token.isEmpty)
        let coldLaunch = CloudController(configuration: cfg, registerHandlers: false)
        XCTAssertFalse(coldLaunch.authenticated)
        XCTAssertTrue(coldLaunch.token.isEmpty)
        XCTAssertEqual(coldLaunch.address, "iphone-agent.local")
    }

    @MainActor func testPhoneHostConfirmationUsesBoardAcknowledgementAndSharedStatus() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [BoardURLProtocol.self]
        let controller = CloudController(configuration: cfg, registerHandlers: false)
        defer { controller.logout(); BoardURLProtocol.handler = nil }
        var board = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any])
        board["phone_usb_confirmed"] = false
        var rejectConfirmation = true
        var confirmations: [Bool] = []
        BoardURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            if request.url?.path == "/api/phone-host" {
                XCTAssertEqual(request.httpMethod, "POST")
                let stream = try XCTUnwrap(request.httpBodyStream)
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 256)
                let length = stream.read(&buffer, maxLength: buffer.count)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(buffer.prefix(max(0, length)))) as? [String: Bool])
                let confirmed = try XCTUnwrap(body["confirmed"])
                confirmations.append(confirmed)
                if rejectConfirmation { return (409, Data("USB host is not connected".utf8)) }
                board["phone_usb_confirmed"] = confirmed
                return (200, Data("ok".utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/status")
            return (200, try JSONSerialization.data(withJSONObject: board))
        }
        await controller.connect(address: "iphone-agent.local", token: "test-token")
        XCTAssertFalse(controller.phoneUSBConfirmed)
        await controller.confirmPhoneUSB()
        XCTAssertFalse(controller.phoneUSBConfirmed, "A failed confirmation must not enable HID")
        rejectConfirmation = false
        await controller.confirmPhoneUSB()
        XCTAssertTrue(controller.phoneUSBConfirmed)
        XCTAssertTrue(controller.readyToStart)
        await controller.clearPhoneUSBConfirmation()
        XCTAssertFalse(controller.phoneUSBConfirmed)
        XCTAssertFalse(controller.readyToStart)
        XCTAssertEqual(confirmations, [true, true, false])
        board["phone_usb_confirmed"] = true
        await controller.refresh()
        XCTAssertTrue(controller.phoneUSBConfirmed, "The board remains the shared source of confirmation")
    }

    @MainActor func testControllerClearsStaleStatusAndReturnsToLoginFor401() async throws {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [BoardURLProtocol.self]
        let controller = CloudController(configuration: cfg, registerHandlers: false)
        defer { controller.logout(); BoardURLProtocol.handler = nil }
        let body = Data(fixture.utf8)
        BoardURLProtocol.handler = { _ in (200, body) }
        await controller.connect(address: "iphone-agent.local", token: "test-token")
        await controller.confirmPhoneUSB()
        XCTAssertTrue(controller.readyToStart)
        controller.expireStatus(now: Date().addingTimeInterval(9))
        XCTAssertTrue(controller.authenticated)
        XCTAssertFalse(controller.connected)
        XCTAssertNil(controller.status)
        XCTAssertFalse(controller.readyToStart)
        await controller.refresh()
        XCTAssertTrue(controller.connected)
        BoardURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await controller.refresh()
        XCTAssertTrue(controller.authenticated)
        XCTAssertFalse(controller.connected)
        XCTAssertNil(controller.status)
        XCTAssertEqual(controller.readiness.completedCount, 0)
        BoardURLProtocol.handler = { _ in (200, body) }
        await controller.refresh()
        XCTAssertTrue(controller.connected)
        BoardURLProtocol.handler = { _ in (401, Data()) }
        await controller.refresh()
        XCTAssertFalse(controller.authenticated)
        XCTAssertNil(controller.status)
        XCTAssertTrue(controller.token.isEmpty)
        XCTAssertTrue(controller.loginError.contains("控制令牌"))
    }
}
