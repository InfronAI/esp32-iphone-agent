import SwiftUI

struct CloudSetupView: View {
    @ObservedObject var controller: CloudController
    @ObservedObject private var settingsNavigator = SystemSettingsNavigator.shared
    let pendingExample: CloudTaskExample?
    let onExampleStarted: () -> Void
    @State private var step: DeviceCheck
    @State private var launching = false
    @Environment(\.dismiss) private var dismiss

    init(controller: CloudController, step: DeviceCheck, pendingExample: CloudTaskExample?,
         onExampleStarted: @escaping () -> Void) {
        self.controller = controller
        self.pendingExample = pendingExample
        self.onExampleStarted = onExampleStarted
        _step = State(initialValue: step)
    }

    private var next: DeviceCheck? {
        if let pendingExample { return controller.readiness.firstMissing(for: pendingExample) }
        return controller.readiness.firstMissing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let state = controller.readiness.check(step)
                    HStack(spacing: 12) {
                        Image(systemName: state.level.symbol).font(.title).foregroundStyle(state.level.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.badge).font(.headline)
                            Text(state.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                    if let pendingExample {
                        Label("正在准备：\(pendingExample.title)", systemImage: pendingExample.symbol).font(.subheadline)
                    }
                }
                switch step {
                case .connection: connectionGuide
                case .mirroring: mirroringGuide
                case .picture: pictureGuide
                case .usb: usbGuide
                case .calibration: calibrationGuide
                }
                if !settingsNavigator.message.isEmpty {
                    Section { Text(settingsNavigator.message).font(.footnote).foregroundStyle(.orange) }
                }
                Section {
                    Button { Task { await controller.refresh() } } label: {
                        Label("重新检测状态", systemImage: "arrow.clockwise")
                    }.disabled(controller.busy || launching)
                    if let next, next != step {
                        Button("下一项：\(next.title)") { navigate(next) }
                    } else if next == nil, let example = pendingExample {
                        Button {
                            launching = true
                            Task {
                                await controller.refresh()
                                if let missing = controller.readiness.firstMissing(for: example) {
                                    step = missing
                                } else {
                                    await controller.startExample(example)
                                    onExampleStarted()
                                    dismiss()
                                }
                                launching = false
                            }
                        } label: { Label("启动「\(example.title)」", systemImage: "play.fill") }
                        .disabled(launching || controller.busy || controller.boardWorking || controller.calibrating)
                    } else if next == nil {
                        Label("配置已完成，可以开始任务", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    if !controller.notice.isEmpty {
                        Text(controller.notice).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(step.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private var connectionGuide: some View {
        Group {
            Section("连接方法") {
                instruction(1, "连接同一 Wi-Fi", "ESP32 使用 2.4 GHz；让 iPhone 连接同一路由器，并允许设备相互访问。")
                instruction(2, "允许本地网络访问", "在 iOS 设置中的 ESP32 Agent 页面开启“本地网络”。")
                Button("打开本地网络权限设置", systemImage: "arrow.up.forward.app") {
                    Task { await settingsNavigator.open(.appPermissions) }
                }
                if controller.status?.time_synced == false {
                    Text("ESP32 已连接，但仍在校时。请确认 Wi-Fi 可以访问互联网，稍后重新检测。")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            Section("当前设备") {
                Text(controller.address).font(.footnote).textSelection(.enabled)
                Text("连接恢复后会自动读取状态。切换设备或更换令牌，请退出登录后重新登录。")
                    .font(.footnote).foregroundStyle(.secondary)
                if !controller.connectionError.isEmpty {
                    Text(controller.connectionError).font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private var mirroringGuide: some View {
        Section("两步开启屏幕镜像") {
            instruction(1, "从屏幕右上角向下滑", "在控制中心点击两个重叠矩形的“屏幕镜像”。")
            instruction(2, "选择 ESP32 Agent", "出现勾选后收起控制中心；App 会自动重新检测，无需再点确认。")
            Text("找不到设备时，检查两台设备是否在同一路由器；已连接但没有画面时，先停止镜像再重新选择。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("打开本地网络权限设置", systemImage: "arrow.up.forward.app") {
                Task { await settingsNavigator.open(.appPermissions) }
            }
        }
    }

    private var pictureGuide: some View {
        Section("画面传输检测") {
            Text(controller.status?.hasFrame == true ? "ESP32 正在接收并解码手机画面。" : "尚未收到可用画面，请检查屏幕镜像。")
            Button("重新配置屏幕镜像") { step = .mirroring }
            Text("实时监控画面仅在网页控制台展示。发送任务后可以离开此 App。")
                .font(.footnote).foregroundStyle(.secondary)
            if let error = controller.status?.video, !error.isEmpty {
                DisclosureGroup("检测详情") { Text(error).font(.caption) }
            }
        }
    }

    private var usbGuide: some View {
        Group {
            Section("iPhone 13 接线方法") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("iPhone · Lightning 接口", systemImage: "iphone")
                    Label("Lightning 转 USB 主机／相机转接器", systemImage: "arrow.down")
                    Label("USB 数据线 → ESP32 原生 USB / OTG 口", systemImage: "cable.connector")
                }.font(.subheadline).padding(.vertical, 8)
                Text("普通充电数据线不能代替主机转接器。供电不足时，可使用带供电口的 Lightning 转 USB 3 相机转接器。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("让手机显示指针") {
                Label(settingsNavigator.assistiveTouchEnabled ? "已检测到辅助触控开启" : "辅助触控尚未开启",
                      systemImage: settingsNavigator.assistiveTouchEnabled ? "checkmark.circle.fill" : "hand.point.up.left")
                    .foregroundStyle(settingsNavigator.assistiveTouchEnabled ? .green : .orange)
                Button("打开辅助触控设置", systemImage: "arrow.up.forward.app") {
                    Task { await settingsNavigator.open(.assistiveTouch) }
                }.accessibilityIdentifier("setup-assistive-touch")
                Button("查看鼠标／键盘设备", systemImage: "computermouse") {
                    Task { await settingsNavigator.open(.assistiveTouchDevices) }
                }.accessibilityIdentifier("setup-assistive-devices")
                instruction(1, "将 USB 从 Mac 改接到 iPhone", "ESP32 的 USB / OTG 数据口需要通过上述转接器连接手机。")
                instruction(2, "开启辅助触控", "设置 → 辅助功能 → 触控 → 辅助触控。开启后观察手机上是否出现鼠标指针。")
                instruction(3, "确认实际接线", "“已检测到 USB”只表示连接了一个主机，App 无法自动区分 Mac 和 iPhone。")
                Button(controller.phoneUSBConfirmed ? "已确认接到 iPhone" : "我已按图接到 iPhone") {
                    Task { await controller.confirmPhoneUSB() }
                }.disabled(!controller.connected || controller.status?.usb != "ok" || controller.phoneUSBConfirmed)
                if controller.phoneUSBConfirmed {
                    Button("接线已改变，重新检测") { Task { await controller.clearPhoneUSBConfirmation() } }
                }
                Link("查看 Apple 辅助触控接线说明", destination: URL(string: "https://support.apple.com/zh-cn/111775")!)
            }
        }
    }

    private var calibrationGuide: some View {
        Section("在 Mac 网页完成校准") {
            instruction(1, "在 Mac 打开 iphone-agent.local", "登录后，在手机监控区点击“指针校准”。")
            instruction(2, "按监控画面完成校准", "等待指针停稳，再点击网页画面中的指针中心。校准完成后，本 App 会自动同步状态。")
            Text("手机保持解锁和镜像开启即可，无需留在此 App 中。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("打开辅助触控与指针设置", systemImage: "arrow.up.forward.app") {
                Task { await settingsNavigator.open(.assistiveTouch) }
            }
        }
    }

    private func navigate(_ item: DeviceCheck) {
        step = item
        settingsNavigator.refresh()
        let target = DeviceSettingsDestination.destination(for: item, connected: controller.connected,
                                                           assistiveTouchEnabled: settingsNavigator.assistiveTouchEnabled)
        Task { await settingsNavigator.open(target) }
    }

    private func instruction(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.caption.bold()).foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26).background(Color.accentColor.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 5)
    }
}
