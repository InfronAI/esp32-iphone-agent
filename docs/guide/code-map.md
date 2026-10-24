# 代码目录结构

[返回导航](README.md)

```text
esp32-iphone-agent/
├── README.md / README.zh-CN.md          项目入口与当前方案
├── NOTICE.md / LICENSE                 来源与许可
├── .github/workflows/ci.yml             iOS、固件、主机测试与旧 server CI
├── hardware/
│   ├── flash.sh                        Arduino CLI 构建/烧录，--cloud 选择当前模式
│   ├── hid_bridge/
│   │   ├── hid_bridge.ino              初始化、串口分发、USB HID 命令
│   │   ├── cloud_agent.cpp/.h          HTTP API、HTTPS、任务调度、动作队列
│   │   ├── secrets.example.h           可公开的配置模板
│   │   ├── secrets.h                   本机私有配置，Git 忽略
│   │   ├── netcfg.cpp/.h               Wi-Fi、DHCP、NVS、重连
│   │   ├── ble_link.cpp/.h             旧 BLE 桥接模式
│   │   ├── video_link.cpp/.h           旧视频转发路径 / 共用接口
│   │   ├── nimble_cfg.h                BLE 构建参数
│   │   └── src/
│   │       ├── cloud/
│   │       │   ├── harness.cpp/.h      决策结构、进展、记忆、重试、复核、限额
│   │       │   ├── action.c/.h         动作枚举、坐标、按键、ASCII 边界校验
│   │       │   ├── vision.cpp/.h       H.264 队列、JPEG、时间戳、画面签名
│   │       │   ├── h264_live.h         I/P 流检查和低等待解码
│   │       │   ├── trace.cpp/.h        PSRAM 环形事件记录与 HTTP 输出
│   │       │   ├── control_page.h     嵌入式网页 HTML/CSS/JS
│   │       │   ├── control_icons.h    本地静态图标字节
│   │       │   └── openh264/          API 头文件及许可
│   │       ├── airplay/               AirPlay、RTSP、配对、mDNS、解密
│   │       │   └── playfair/          FairPlay 相关上游代码与许可
│   │       ├── bplist/                二进制 plist
│   │       └── video/                 旧 GOP 缓冲工具
│   ├── tools/
│   │   ├── cloud_deps.py              固定 OpenH264 版本、校验、移植补丁、编译
│   │   ├── task_examples.cjs          从共享 JSON 生成网页/Swift 示例
│   │   ├── embed_web_icons.cjs        从 App 图标生成网页资源
│   │   └── board_test.py              历史 BLE 调试工具
│   └── tests/                         C/C++ ASan/UBSan、网页交互、解码对照测试
├── ios/
│   ├── project.yml                    XcodeGen 项目源
│   ├── IPhoneAgent.xcodeproj/          可直接打开的 Xcode 工程
│   ├── Config/                        通用构建配置和私有 Local.xcconfig 模板
│   ├── IPhoneAgent/
│   │   ├── App/IPhoneAgentApp.swift   默认进入 Wi-Fi 控制台
│   │   ├── Cloud/
│   │   │   ├── BoardAPI.swift         LAN 地址、HTTP、鉴权、状态模型
│   │   │   ├── CloudController.swift  登录与状态轮询、任务和设置
│   │   │   ├── CloudConsoleView.swift 任务入口与手机控制台
│   │   │   ├── DeviceReadiness.swift  配置检查与任务前提
│   │   │   ├── DeviceStatusView.swift 设备状态卡片
│   │   │   ├── CloudSetupView.swift   配置引导
│   │   │   ├── SystemSettingsNavigator.swift 系统设置跳转/手动回退
│   │   │   ├── CloudModelSettingsView.swift API 配置
│   │   │   ├── CloudLoginView.swift   令牌登录
│   │   │   └── TaskExamples.swift     生成的 12 个示例
│   │   ├── Board/、Agent/、Video/等    保留的旧 BLE / iPhone Agent 实现
│   │   ├── Review/、Services/         旧回放/日志与共用服务
│   │   └── Assets.xcassets/           品牌、启动和 App 图标
│   ├── AgentActivity/、Shared/         历史活动/Widget 与共用类型
│   ├── IPhoneAgentTests/              Swift 测试，包括 CloudBoardTests
│   ├── fastlane/                      可选分发配置，非个人安装必要条件
│   └── CLOUD_CONTROLLER.md            App 控制台实现说明
├── shared/task-examples.json           两端任务示例的唯一源
├── prompts/                           旧 iPhone Agent 的提示词
├── server/                            历史 Python 电脑端服务与测试
├── tools/demo/                        可重复生成 Demo 的脚本与 Node 依赖锁
├── docs/guide/                        当前完整指南与历史 README
├── docs/demo/                         公开 MP4、海报、字幕/章节、演示说明
└── build/                             本地编译、测试、私有诊断产物，Git 忽略
```

## 按功能找代码

| 想修改 | 从这里开始 |
|---|---|
| Goal 输入、状态机、HTTP 路由、TLS 请求 | `hardware/hid_bridge/cloud_agent.cpp` |
| 模型结构化响应、卡住检测、完成验证、执行限额 | `src/cloud/harness.cpp/.h` |
| 当前 ESP32 系统提示词 | `cloud_agent.cpp` 的 `SYSTEM`，不是旧 `prompts/` |
| 新增动作类型 | `action.h/.c`、Harness 解析、`perform()`；同步测试和提示词 |
| 网页布局、监控刷新、时间线 | `src/cloud/control_page.h` |
| App 连接、任务/状态、配置引导 | `ios/IPhoneAgent/Cloud/` |
| 镜像分辨率宣告 | `hid_bridge.ino` 的 `startAirplay()`；实际流尺寸仍由发送端决定 |
| 解码与参考帧修复 | `vision.cpp`、`h264_live.h`、`hardware/tools/cloud_deps.py` |
| 模型配置持久化 | `cloud_agent.cpp` 的 `loadConfig/saveConfig` |
| mDNS 主机名和服务 | `netcfg.cpp`、`src/airplay/mdns.c` |
| 两端示例任务 | 修改 `shared/task-examples.json` 后运行生成脚本 |
| 演示内容 | `tools/demo/record-demo.cjs`；它只使用模拟 HTTP，不连真实板子 |

生成文件应由源文件和脚本维护。不要在网页和 Swift 中分别手改同一个示例任务，然后忘记同步另一端。

`tools/ci/` 提供 GitHub Actions 工作流模板与启用说明，当前不在 `.github/workflows/` 中自动执行。
