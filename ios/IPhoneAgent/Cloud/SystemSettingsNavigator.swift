import SwiftUI
import Accessibility

enum DeviceSettingsDestination: Equatable {
    case guide, appPermissions, assistiveTouch, assistiveTouchDevices
    static func destination(for check: DeviceCheck, connected: Bool, assistiveTouchEnabled: Bool) -> Self {
        switch check {
        case .connection: return connected ? .guide : .appPermissions
        case .usb: return assistiveTouchEnabled ? .assistiveTouchDevices : .assistiveTouch
        case .mirroring, .picture, .calibration: return .guide
        }
    }
}

@MainActor final class SystemSettingsNavigator: ObservableObject {
    static let shared = SystemSettingsNavigator()
    @Published private(set) var assistiveTouchEnabled = UIAccessibility.isAssistiveTouchRunning
    @Published private(set) var message = ""
    func refresh() { assistiveTouchEnabled = UIAccessibility.isAssistiveTouchRunning }
    func open(_ destination: DeviceSettingsDestination) async {
        message = ""
        switch destination {
        case .guide: return
        case .appPermissions:
            guard let url = URL(string: UIApplication.openSettingsURLString),
                  await UIApplication.shared.open(url) else {
                message = "请打开设置 → App → ESP32 Agent，允许本地网络访问。"
                return
            }
        case .assistiveTouch, .assistiveTouchDevices:
            let path = destination == .assistiveTouchDevices ? "设置 → 辅助功能 → 触控 → 辅助触控 → 设备" :
                "设置 → 辅助功能 → 触控 → 辅助触控"
            guard #available(iOS 26.0, *) else { message = "请手动打开：" + path; return }
            let feature: AccessibilitySettings.Feature = destination == .assistiveTouchDevices ? .assistiveTouchDevices : .assistiveTouch
            if #available(iOS 26.4, *), !AccessibilitySettings.canOpenSettings(for: feature) {
                message = "当前设备无法直接打开，请前往：" + path
                return
            }
            do { try await AccessibilitySettings.openSettings(for: feature) }
            catch { message = "未能打开设置，请前往：" + path }
        }
    }
}
