// Generated from shared/task-examples.json by hardware/tools/task_examples.cjs.
import Foundation

enum CloudTaskExample: String, CaseIterable, Identifiable {
    case describeScreen, checkWiFi, checkBattery, checkStorage, checkSystem, checkAlarms, checkWorldClock, checkCalendar, checkWeather, checkDisplay, checkLanguage, checkBluetooth, checkScreenTime
    var id: Self { self }
    static var phoneExamples: [Self] { allCases.filter { $0 != .describeScreen } }
    private var metadata: (title: String, symbol: String, detail: String, goal: String) {
        switch self {
        case .describeScreen: return ("读懂当前屏幕", "sparkles", "识别当前画面，无需 USB 控制", "描述当前手机屏幕的内容。")
        case .checkWiFi: return ("查看 Wi-Fi 名称", "wifi", "打开设置，读取当前网络", "打开系统设置的 Wi-Fi 页面，告诉我当前连接的 Wi-Fi 名称。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkBattery: return ("查看电池状态", "battery.75percent", "查看电量与低电量模式", "打开系统设置的电池页面，读取可见的电池电量和低电量模式状态。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkStorage: return ("查看存储空间", "internaldrive", "查看手机空间占用", "打开设置 → 通用 → iPhone 储存空间，告诉我已用空间和总容量。不要卸载或删除内容。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkSystem: return ("查看系统版本", "info.circle", "读取机型与 iOS 版本", "打开设置 → 通用 → 关于本机，只读取机型名称和 iOS 版本，不读取或报告序列号、IMEI 等标识。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkAlarms: return ("查看已有闹钟", "alarm", "列出当前启用的闹钟", "打开时钟 App 的闹钟页面，列出可见的已启用闹钟及时间，不新增或修改闹钟。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkWorldClock: return ("查看世界时钟", "globe", "查看已添加城市的时间", "打开时钟 App 的世界时钟，读取已添加城市及当前时间，不添加或删除城市。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkCalendar: return ("查看今日日程", "calendar", "读取今天的日历安排", "打开日历 App，定位今天并概括可见日程，不添加、修改或删除日程。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkWeather: return ("查看今日天气", "cloud.sun", "查看已有城市的天气", "打开天气 App，读取默认已添加城市的今日天气、温度与降雨提示；如出现权限请求则停止并报告。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkDisplay: return ("查看显示设置", "sun.max", "查看亮度和深浅色模式", "打开设置 → 显示与亮度，读取当前外观模式和可见亮度设置，不拖动滑块或切换选项。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkLanguage: return ("查看语言与地区", "character.bubble", "读取当前语言和地区", "打开设置 → 通用 → 语言与地区，告诉我当前语言和地区，不修改。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkBluetooth: return ("查看蓝牙设备", "headphones", "查看已有设备连接状态", "打开设置的蓝牙页面，只读取已记录设备的名称与连接状态，不配对、连接或断开设备。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        case .checkScreenTime: return ("查看屏幕使用时间", "hourglass", "读取已有使用时间统计", "打开设置 → 屏幕使用时间，概括可见的今日统计；如果功能未启用则报告未启用并停止。只查看，不修改任何设置，不发送信息或进行购买；完成后停止。")
        }
    }
    var title: String { metadata.title }
    var symbol: String { metadata.symbol }
    var detail: String { metadata.detail }
    var goal: String { metadata.goal }
}
