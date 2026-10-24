# 安装方法

[返回导航](README.md) · [硬件与接线](hardware.md) · [使用手册](manual.md)

## 1. 准备开发环境

本次验证环境：MacBook Pro M1 Pro / 16 GB、Xcode 27.1、Arduino ESP32 Core **3.3.8**、
NimBLE-Arduino **2.5.1**、OpenH264 **2.6.0（源码 commit 固定）**。
App 最低部署目标为 iOS 18；构建当前系统设置跳转代码需使用包含相关 API 的新 SDK，需要带 iOS 26.4 或更新 SDK 的 Xcode，实测为 27.1。
这不代表所有 iOS 18+ 设备都完成了兼容实测。

安装 Xcode 并打开一次完成组件安装、登录自己的 Apple 开发账号，然后安装 Arduino CLI、XcodeGen、Git、Python 3 和 Node.js。
macOS 使用 Homebrew 时可执行：

```bash
brew install arduino-cli xcodegen git python node
```

CLI 官方入口：[安装](https://docs.arduino.cc/arduino-cli/installation)与[入门](https://docs.arduino.cc/arduino-cli/getting-started/)。

```bash
git clone https://github.com/InfronAI/esp32-iphone-agent.git
cd esp32-iphone-agent
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32@3.3.8 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli lib install "NimBLE-Arduino@2.5.1"
```

## 2. 配置本机固件参数

```bash
cp hardware/hid_bridge/secrets.example.h hardware/hid_bridge/secrets.h
chmod 600 hardware/hid_bridge/secrets.h
```

编辑 `secrets.h`，填写自己的值：

```cpp
#define WIFI_SSID "YOUR_2G_WIFI"
#define WIFI_PASS "YOUR_WIFI_PASSWORD"
#define CLOUD_LLM_URL "https://your-provider.example/v1/chat/completions"
#define CLOUD_LLM_MODEL "your-vision-model"
#define CLOUD_LLM_KEY "your-api-key"
```

- Wi-Fi 必须允许 ESP32 接入 2.4 GHz，并可访问互联网和局域网客户端。
- Endpoint 是**完整的 Chat Completions HTTPS 地址**，不是只填服务商首页或 `/v1`。
- 模型必须实际支持 `image_url`。文本连接成功不代表能够识图。
- 这些值会进入你的本地固件；不要把个人 `.bin` 当作通用安装包公开。
- 首次启动后的模型配置可在网页或 App 修改；NVS 中有效的模型配置优先于构建默认值。

## 3. 构建与烧录 ESP32

先只构建，验证工具链：

```bash
hardware/flash.sh --cloud --debug --build-only
```

脚本下载固定版本的 OpenH264 源码、校验 SHA-256、应用 ESP32 和参考帧补丁，再构建解码静态库。
首次需要互联网，之后会复用校验通过的缓存。

把板子**原生 USB/OTG 口**通过数据线接到 Mac。接口不足可以使用可靠的数据型集线器：

```bash
arduino-cli board list
hardware/flash.sh /dev/cu.usbmodemYOUR_BOARD --cloud --debug
```

将端口替换成自己的板子端口。正常脚本使用 1200-baud 触发下载模式，并跟随该板重新枚举的端口。
不要随便选择“第一个串口”覆盖另一台设备。

当前构建参数：

```text
esp32:esp32:esp32s3:USBMode=default,CDCOnBoot=cdc,FlashSize=8M,PSRAM=opi,PartitionScheme=default_8MB
```

如果你的板卡 PSRAM 类型或 USB 接法不同，先核对硬件，而不是直接沿用以上参数。

### 自动下载失败时

1. 拔下额外电源和 USB，等几秒。
2. 按住 BOOT，接回原生 USB；或按住 BOOT、按一下 RESET/EN、再松开 BOOT。
3. 确认新的 ROM 下载端口；完成上面的 build-only 后，可从 `hardware/` 手动上传已有构建：

```bash
cd hardware
arduino-cli upload \
  -b 'esp32:esp32:esp32s3:USBMode=default,CDCOnBoot=cdc,FlashSize=8M,PSRAM=opi,PartitionScheme=default_8MB' \
  -p /dev/cu.usbmodemYOUR_BOOT_PORT --input-dir build hid_bridge
cd ..
```

运行中板子若在软复位时消失，可先通过串口发送 `0 net {"mode":"off"}` 并等待，再触发下载模式；
这会临时断开网页与镜像。不要为了重试而先擦除整片 Flash，以免清空控制令牌和 NVS 配置。

## 4. 获取控制台地址与令牌

```bash
arduino-cli monitor -p /dev/cu.usbmodemYOUR_BOARD -c baudrate=115200
```

固件启动日志显示控制 URL；输入以下串口命令，每条以换行结束：

```text
1 agent status
2 agent token
```

保存自己的控制令牌。它不是云端 API Key，通常也不是 Wi-Fi 密码。
板子开机自动加入配置的网络，不需要先登录控制台。

优先访问 `http://iphone-agent.local/`。若当前路由器或浏览器无法解析 `.local`，使用串口/路由器 DHCP 列表中的 IP。
IP 来自 DHCP，重启后可能改变；需要固定 IP 时在路由器做 DHCP 保留，不要假设仓库固定为某个地址。

## 5. 构建并安装 iPhone App

```bash
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
open ios/IPhoneAgent.xcodeproj
```

在忽略 Git 的 `Local.xcconfig` 设置自己的 `DEVELOPMENT_TEAM` 和唯一 `IA_BUNDLE_ID`。
在 Xcode 选 `IPhoneAgent` Scheme、自己的解锁 iPhone，按 Run。
手机按系统提示信任 Mac、启用 Developer Mode；签名与个人账号限制以 Xcode/Apple 当时提示为准。

- 本模式不依赖旧热点一键加入能力。使用个人签名遇到相关 entitlement 问题时，按配置注释保持可选 entitlement 为空。
- 不要使用仓库中的示例 Team ID 代替自己的账号，也不要上传 `Local.xcconfig`、证书或 provisioning profile。
- 工程文件已提交，可直接打开；修改 `ios/project.yml` 后在 `ios/` 执行 `xcodegen generate` 再更新工程。
- App 当前默认打开 Wi-Fi 控制台，无需为使用板上 Harness 再启用旧 BLE Agent。

## 6. 首次联调

1. 手机、板子、Mac 进入互通的同一 LAN。
2. App 允许“本地网络”，输入 `iphone-agent.local` 和控制令牌登录。
3. 在手机控制中心开启屏幕镜像 → **ESP32 Agent**，确认“镜像”和“画面解码”都就绪。
4. 网页“读懂当前屏幕”可先验证视觉 API；此测试不要求 USB HID。
5. 按[运行接线](hardware.md)把板子从 Mac 移到手机 USB 主机转接器，开启辅助触控，再在 App 确认接线。
6. 网页进行指针校准，然后从 App 或网页提交一个只读 Goal。

## 7. 测试与 Demo 工具

```bash
make -C hardware/tests
make -C hardware/tests cloud
make -C hardware/tests harness
npm ci --prefix tools/demo
cd tools/demo
npx playwright install chromium
cd ../..
node tools/demo/test-web.cjs
```

本机已有 Google Chrome 时可设置 `CHROME_PATH`，跳过浏览器下载。`make ... harness` 只访问固定测试依赖源码，不调用收费模型或真实 HID。

在 Xcode 里运行测试，或选择本机存在的模拟器：

```bash
xcodebuild test -project ios/IPhoneAgent.xcodeproj -scheme IPhoneAgent \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR_NAME' \
  -derivedDataPath build/ios-tests CODE_SIGNING_ALLOWED=NO
```

H.264 像素对照测试需要你自己的本地捕获，见 `hardware/tests/test_cloud_decoder.py`。不把私人屏幕视频放进 Git。
Demo 录制方法见 [Demo 文档](../demo/README.md)。

## 8. 启用 GitHub Actions（可选）

[CI 模板和启用说明](../../tools/ci/README.md)包含固件、iOS、Harness、网页和 Python 测试。
需要具备工作流写入权限的 GitHub 授权后再复制到 `.github/workflows/ci.yml`；当前发布没有启用远程 Actions。
