import SwiftUI

struct CloudConsoleView: View {
    @ObservedObject var controller: CloudController
    @ObservedObject private var settingsNavigator = SystemSettingsNavigator.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var guide: DeviceCheck?
    @State private var pendingExample: CloudTaskExample?
    @State private var launchingExample = false
    @State private var resultScroll = 0
    @State private var modelSettings = false
    @State private var showAllExamples = false
    @FocusState private var editingGoal: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            Form {
                Section {
                    if let s = controller.currentStatus {
                        Label("ESP32 已连接 · 实时状态", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let ssid = s.wifi_ssid, !ssid.isEmpty { LabeledContent("Wi-Fi", value: ssid) }
                        LabeledContent("设备 IP", value: s.ip)
                        if let date = controller.statusDate {
                            LabeledContent("最近更新") { Text(date, style: .time).monospacedDigit() }
                        }
                    } else {
                        Label("设备连接中断", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                        Text(controller.connectionError.isEmpty ? "正在重新读取设备状态…" : controller.connectionError)
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("实时状态暂不可用，恢复连接后自动更新。").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("实时连接") }
                Section {
                    DeviceStatusView(readiness: controller.readiness) { item in
                        pendingExample = nil
                        openSetup(item)
                    }
                    Button {
                        guide = .usb
                        Task { await settingsNavigator.open(.assistiveTouch) }
                    } label: {
                        Label(settingsNavigator.assistiveTouchEnabled ? "辅助触控已开启 · 查看设置" : "开启辅助触控", systemImage: "hand.point.up.left")
                    }.accessibilityIdentifier("open-assistive-touch")
                } header: { Text("设备状态") }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("任务示例 · 12 个").font(.headline)
                        Text("点一下立即启动，缺少配置时会带你完成设置。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    ForEach(Array(CloudTaskExample.phoneExamples.prefix(showAllExamples ? 12 : 3))) { example in
                        Button { launch(example) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: example.symbol).font(.title3)
                                    .frame(width: 38, height: 38)
                                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(example.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(example.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.circle.fill").font(.title2)
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }
                        .disabled(!controller.connected || launchingExample || controller.busy || controller.boardWorking || controller.calibrating)
                        .accessibilityHint("立即启动示例；设备未就绪时打开配置指引")
                        .accessibilityIdentifier("task-example-\(example.rawValue)")
                    }
                    Button(showAllExamples ? "收起任务示例" : "查看全部 12 个任务示例") { showAllExamples.toggle() }
                        .accessibilityIdentifier("toggle-task-examples")
                    if launchingExample { Label("正在检查设备并启动…", systemImage: "hourglass").font(.footnote) }
                    TextField("也可以输入自己的任务…", text: $controller.goal, axis: .vertical)
                        .lineLimit(2...6).focused($editingGoal).accessibilityLabel("自定义任务")
                    Button {
                        editingGoal = false
                        pendingExample = nil
                        if let next = controller.readiness.firstMissing { guide = next }
                        else { Task { await controller.start() } }
                    } label: {
                        Label(controller.readiness.firstMissing == nil ? "发送任务给 ESP32" : "配置设备后发送任务",
                              systemImage: "paperplane.fill")
                    }
                    .disabled(!controller.connected || controller.busy || controller.boardWorking || controller.calibrating || launchingExample ||
                              controller.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: { Text("任务") } footer: {
                    Text("任务发送后，请离开此 App 并保持手机解锁。ESP32 会继续执行，可在 Mac 网页查看实时画面和进展。")
                }

                Section {
                    if let s = controller.status, controller.connected {
                        HStack {
                            if s.isWorking { ProgressView().padding(.trailing, 4) }
                            Text(s.title).font(.subheadline.weight(.medium))
                            Spacer()
                            if s.running || s.steps > 0 { Text("\(s.steps) 步").font(.caption).foregroundStyle(.secondary) }
                        }
                        if !s.detail.isEmpty { Text(s.detail).font(.footnote).textSelection(.enabled) }
                    } else {
                        Text("连接设备后，可在这里查看任务结果。").font(.footnote).foregroundStyle(.secondary)
                    }
                    if !controller.notice.isEmpty {
                        Text(controller.notice).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Button(role: .destructive) { Task { await controller.stop() } } label: {
                        Label(controller.stopping ? "正在停止…" : "停止任务", systemImage: "stop.circle.fill")
                    }.disabled(controller.stopping || controller.token.isEmpty)
                } header: { Text("任务进展") }
                    .id("task-progress")

                Section {
                    Button { modelSettings = true } label: {
                        Label("云端模型配置", systemImage: "cloud")
                    }.disabled(!controller.connected)
                    Button("检测云端连接") { Task { await controller.testCloud() } }
                        .disabled(!controller.connected || controller.busy || controller.boardWorking || controller.calibrating)
                } header: { Text("云端模型") }
            }
            .onChange(of: resultScroll) {
                withAnimation { scroll.scrollTo("task-progress", anchor: .top) }
            }
            }
            .navigationTitle("ESP32 Agent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("设备连接", systemImage: "wifi") { pendingExample = nil; guide = .connection }
                        Button("云端模型配置", systemImage: "cloud") { modelSettings = true }.disabled(!controller.connected)
                        Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { controller.logout() }
                    } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
                if controller.boardWorking {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("停止", role: .destructive) { Task { await controller.stop() } }
                            .disabled(controller.stopping)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editingGoal = false } }
            }
            .refreshable { await controller.refresh() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    settingsNavigator.refresh()
                    await controller.refresh()
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    controller.expireStatus()
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .sheet(item: $guide) { step in
                CloudSetupView(controller: controller, step: step, pendingExample: pendingExample) {
                    pendingExample = nil
                    resultScroll += 1
                }
            }
            .sheet(isPresented: $modelSettings) { CloudModelSettingsView(controller: controller) }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.assistiveTouchStatusDidChangeNotification)) { _ in
                settingsNavigator.refresh()
            }
        }
    }

    private func openSetup(_ item: DeviceCheck) {
        settingsNavigator.refresh()
        guide = item == .picture && controller.status?.airplay != 2 ? .mirroring : item
        let destination = DeviceSettingsDestination.destination(for: item, connected: controller.connected,
                                                                assistiveTouchEnabled: settingsNavigator.assistiveTouchEnabled)
        Task { await settingsNavigator.open(destination) }
    }

    private func launch(_ example: CloudTaskExample) {
        editingGoal = false
        launchingExample = true
        Task {
            await controller.refresh()
            if let next = controller.readiness.firstMissing(for: example) {
                pendingExample = example
                controller.goal = example.goal
                guide = next
            } else {
                pendingExample = nil
                await controller.startExample(example)
                resultScroll += 1
            }
            launchingExample = false
        }
    }
}
