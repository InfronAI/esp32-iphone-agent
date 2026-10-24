import SwiftUI

struct CloudModelSettingsView: View {
    @ObservedObject var controller: CloudController
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var model = ""
    @State private var key = ""
    @State private var keySet = false
    @State private var loaded = false
    @State private var loading = false
    @State private var saving = false
    @State private var message = ""
    @State private var failed = false
    @State private var showTest = false

    private var disabled: Bool {
        !loaded || loading || saving || !controller.connected || controller.busy || controller.boardWorking || controller.calibrating ||
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (!keySet && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("由 ESP32 直接连接云端模型", systemImage: "cloud")
                    Text("网页和 App 共用板子上的同一份配置。保存后立即生效，重启后仍然保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if loading { Section { ProgressView("正在读取 ESP32 配置…") } }
                Section {
                    LabeledContent("API 地址") {
                        TextField("https://…/v1/chat/completions", text: $endpoint, axis: .vertical)
                            .multilineTextAlignment(.trailing).keyboardType(.URL).accessibilityLabel("云端 API 地址")
                    }
                    TextField("模型名称", text: $model).accessibilityLabel("模型名称")
                    SecureField(keySet ? "API Key（留空保留现有密钥）" : "填写 API Key", text: $key)
                        .accessibilityLabel("云端 API Key")
                    Label(keySet ? "API Key 已保存在板子上" : "尚未配置 API Key",
                          systemImage: keySet ? "checkmark.shield" : "key")
                        .font(.footnote).foregroundStyle(keySet ? Color.green : .secondary)
                } header: { Text("云端模型") } footer: {
                    Text("填写兼容 Chat Completions 的完整 HTTPS 地址。视觉任务需要支持图片输入的模型。密钥保存后不回显；留空会保留现有密钥。")
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!loaded || saving)
                Section {
                    Button(saving ? "正在保存…" : "保存到 ESP32") { Task { await save(test: false) } }.disabled(disabled)
                    Button("保存并测试连接") { Task { await save(test: true) } }.disabled(disabled)
                    if controller.boardWorking { Text("正在执行任务，结束后可修改配置。").font(.footnote).foregroundStyle(.secondary) }
                    if !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(failed ? Color.red : .green).textSelection(.enabled)
                    }
                    if !loaded && !loading {
                        Button("重新读取配置") { Task { await load() } }
                    }
                }
                if showTest, let status = controller.status {
                    Section("连接测试") {
                        if status.isWorking { ProgressView("ESP32 正在请求云端…") }
                        else { Text(status.title) }
                        if !status.detail.isEmpty { Text(status.detail).font(.footnote).textSelection(.enabled) }
                        Text("连接测试验证文本请求；回到任务区选择“读懂当前屏幕”可验证图片输入。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("云端模型配置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(saving) } }
            .task { await load() }
            .onDisappear { key = "" }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let config = try await controller.loadCloudConfig()
            endpoint = config.endpoint; model = config.model; keySet = config.key_set
            loaded = true; message = ""; failed = false
        } catch { message = error.localizedDescription; failed = true }
    }

    private func save(test: Bool) async {
        saving = true; showTest = false
        defer { saving = false }
        do {
            let config = try await controller.saveCloudConfig(endpoint: endpoint, model: model, key: key)
            endpoint = config.endpoint; model = config.model; keySet = config.key_set; key = ""
            message = "已保存到 ESP32，网页和 App 将使用此配置。"; failed = false
            if test { showTest = true; await controller.testCloud() }
        } catch { message = error.localizedDescription; failed = true }
    }
}
