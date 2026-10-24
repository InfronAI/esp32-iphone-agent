import SwiftUI

struct CloudRootView: View {
    @ObservedObject var controller: CloudController
    var body: some View {
        if controller.authenticated {
            CloudConsoleView(controller: controller)
        } else {
            CloudLoginView(controller: controller)
        }
    }
}

struct CloudLoginView: View {
    @ObservedObject var controller: CloudController
    @ObservedObject private var settingsNavigator = SystemSettingsNavigator.shared
    @State private var address: String
    @State private var token = ""
    @FocusState private var editingToken: Bool

    init(controller: CloudController) {
        self.controller = controller
        _address = State(initialValue: controller.address)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Image("Logo").resizable().scaledToFit().frame(width: 88, height: 88)
                        Text("登录 ESP32").font(.title2.bold())
                        Text("验证控制令牌后，查看设备实时状态并发送任务。")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                }.listRowBackground(Color.clear)
                Section {
                    TextField("iphone-agent.local", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityLabel("ESP32 地址").accessibilityIdentifier("login-address")
                    SecureField("输入本地控制令牌", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editingToken).submitLabel(.go).onSubmit(login)
                        .accessibilityLabel("控制令牌").accessibilityIdentifier("login-token")
                } header: { Text("设备与凭据") } footer: {
                    Text("默认通过 iphone-agent.local 自动解析板子的地址；无法访问时可填写 IP。控制令牌与 Wi-Fi 密码、云端 API Key 不同。")
                }.disabled(controller.signingIn)
                Section {
                    Button(action: login) {
                        HStack {
                            Spacer()
                            if controller.signingIn { ProgressView() }
                            Text(controller.signingIn ? "正在验证 ESP32…" : "登录控制台").fontWeight(.semibold)
                            Spacer()
                        }.padding(.vertical, 5)
                    }.disabled(controller.signingIn || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || token.isEmpty)
                        .accessibilityIdentifier("login-submit")
                    if !controller.loginError.isEmpty {
                        Text(controller.loginError).font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("login-error")
                    }
                } footer: { Text("ESP32 通电后会自行连接 Wi-Fi。登录仅用于授权控制，不影响板子联网。") }
                Section {
                    Button("本地网络权限设置", systemImage: "arrow.up.forward.app") {
                        Task { await settingsNavigator.open(.appPermissions) }
                    }
                    if !settingsNavigator.message.isEmpty { Text(settingsNavigator.message).font(.footnote).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("ESP32 Agent").navigationBarTitleDisplayMode(.inline)
            .onDisappear { token = "" }
        }
    }

    private func login() {
        guard !controller.signingIn else { return }
        editingToken = false
        Task { await controller.connect(address: address, token: token) }
    }
}
