import Foundation

enum DeviceCheck: String, CaseIterable, Identifiable {
    case connection, mirroring, picture, usb, calibration
    var id: Self { self }
    var title: String {
        switch self {
        case .connection: return "设备连接"
        case .mirroring: return "屏幕镜像"
        case .picture: return "画面解码"
        case .usb: return "USB 接线"
        case .calibration: return "指针校准"
        }
    }
    var symbol: String {
        switch self {
        case .connection: return "wifi"
        case .mirroring: return "rectangle.on.rectangle"
        case .picture: return "photo"
        case .usb: return "cable.connector"
        case .calibration: return "cursorarrow.rays"
        }
    }
}

enum CheckLevel { case ready, pending, attention }

struct DeviceCheckState: Identifiable {
    let id: DeviceCheck
    let level: CheckLevel
    let badge: String
    let detail: String
}

/// Readiness is shared by status cards, setup routing and one-tap examples.
/// A USB enumeration alone cannot identify whether the host is a Mac or iPhone.
struct DeviceReadiness {
    let connected: Bool
    let status: CloudBoardStatus?
    let phoneUSBConfirmed: Bool

    var checks: [DeviceCheckState] { DeviceCheck.allCases.map(check) }
    var completedCount: Int { checks.filter { $0.level == .ready }.count }
    var firstMissing: DeviceCheck? { checks.first { $0.level != .ready }?.id }

    func firstMissing(for example: CloudTaskExample) -> DeviceCheck? {
        let required: [DeviceCheck] = example == .describeScreen ? [.connection, .mirroring, .picture] : DeviceCheck.allCases
        return required.first { check($0).level != .ready }
    }

    func check(_ item: DeviceCheck) -> DeviceCheckState {
        func result(_ level: CheckLevel, _ badge: String, _ detail: String) -> DeviceCheckState {
            DeviceCheckState(id: item, level: level, badge: badge, detail: detail)
        }
        guard connected, let s = status else {
            return result(.pending, item == .connection ? "已中断" : "未知",
                          item == .connection ? "正在重新连接 ESP32" : "恢复连接后自动检测")
        }
        switch item {
        case .connection:
            return s.time_synced == false ? result(.pending, "校时中", "已连接，等待联网校时") :
                result(.ready, "已连接", "iPhone 与 ESP32 已连通")
        case .mirroring:
            return s.airplay == 2 ? result(.ready, "已开启", "正在接收手机画面") :
                result(.pending, s.airplay == 1 ? "连接中" : "待开启", "选择 ESP32 Agent 镜像")
        case .picture:
            if s.hasFrame { return result(.ready, "可用", "实时画面已就绪") }
            if s.airplay != 2 { return result(.pending, "待检测", "先开启屏幕镜像") }
            return result(.attention, "需检查", s.video.isEmpty ? "等待新的手机画面" : "暂时无法读取画面")
        case .usb:
            guard s.usb == "ok" else { return result(.pending, "待接线", "通过转接器连接 iPhone") }
            return phoneUSBConfirmed ? result(.ready, "已确认", "已确认连接到 iPhone") :
                result(.pending, "待确认", "已检测到 USB，请确认接线")
        case .calibration:
            return s.calibrated ? result(.ready, "已保存", "指针位置已校准") :
                result(.pending, "待校准", "在网页监控画面中校准")
        }
    }
}

/// Confirmation lasts only for the current app/board connection, never across a reboot.
struct PhoneUSBConfirmation {
    private(set) var confirmed = false
    private var uptime: Double?

    mutating func confirm(connected: Bool, status: CloudBoardStatus?) {
        confirmed = connected && status?.usb == "ok"
    }

    mutating func observe(connected: Bool, status: CloudBoardStatus?) {
        if !connected || status?.usb != "ok" { confirmed = false }
        if let current = status?.uptime_ms, let previous = uptime, current < previous { confirmed = false }
        uptime = status?.uptime_ms
    }
}
