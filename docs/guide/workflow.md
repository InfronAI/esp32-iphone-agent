# 业务流程图

[返回导航](README.md)

## 首次配置

```mermaid
flowchart TD
    Start["准备硬件与视觉 API"] --> Flash["填写本地 secrets.h / 烧录 --cloud 固件"]
    Flash --> WiFi["ESP32 开机自动连接 2.4 GHz 路由器"]
    WiFi --> Token["USB 串口读取控制令牌"]
    Token --> App["安装并登录 iPhone App"]
    App --> LAN["允许本地网络 / 手机加入同 LAN"]
    LAN --> Mirror["屏幕镜像选择 ESP32 Agent"]
    Mirror --> Frame{"镜像和解码均就绪？"}
    Frame -- 否 --> Fix["按状态卡片指引排查"] --> Mirror
    Frame -- 是 --> USB["原生 USB 从 Mac 移到手机主机转接器"]
    USB --> Touch["开启辅助触控 / 确认真实 USB 接线"]
    Touch --> Cal["网页观察真实指针并完成校准"]
    Cal --> Model["配置 API / 文本测试 / 画面识别测试"]
    Model --> Ready["提交 Goal，离开控制 App"]
```

登录令牌仅用于控制 API 鉴权，不负责触发联网。USB 枚举正常也不等于已确认手机主机。
“读懂当前屏幕”不需要 USB 或指针校准，可用于先验证视觉路径。

## Goal 主循环

```mermaid
flowchart TD
    Goal["收到原始 Goal"] --> Check{"Wi-Fi / 镜像 / 新画面 / 手机 USB / 校准就绪？"}
    Check -- 否 --> Reject["返回未满足条件，不启动动作"]
    Check -- 是 --> Init["新 epoch / 清空上次记录 / 初始化限额"]
    Init --> Observe["读取最新 JPEG 与时间戳"]
    Observe --> Context["组合 Goal + 进展摘要 + 最近动作 + 预期结果"]
    Context --> LLM["云端返回一个 JSON 决策"]
    LLM --> Valid{"结构 / 动作 / 坐标 / epoch / 画面仍有效？"}
    Valid -- 可修正错误 --> Retry{"剩余重试次数？"}
    Retry -- 有 --> Observe
    Retry -- 无 --> Pause["暂停，报告原因"]
    Valid -- 画面明显改变 --> Replan["丢弃旧决策 / 读取新图重新规划"] --> Observe
    Valid -- 有效 --> Progress["评估已取得的进展与卡住情况"]
    Progress --> Decision{"决策类型"}
    Decision -- blocked --> Pause
    Decision -- done --> Candidate["候选完成：记录可见证据"]
    Candidate --> Fresh["等待另一张新的稳定画面"]
    Fresh --> Verify{"再次评估全部 Goal"}
    Verify -- 已满足 --> Done["确认完成 / 返回结果"]
    Verify -- 未满足且能继续 --> Observe
    Verify -- 无法判断或需要帮助 --> Pause
    Decision -- 动作 --> Guard{"动作预算与无进展检查通过？"}
    Guard -- 需要换策略 --> Replan
    Guard -- 达到限制 --> Pause
    Guard -- 是 --> HID["loop 执行一个 USB HID 动作"]
    HID --> Ack{"执行结果确定？"}
    Ack -- 否 --> Pause
    Ack -- 是 --> Wait["等待动作结束 500 ms 后的新帧"] --> Observe
    Stop["用户停止 / 任务 epoch 改变"] --> Cancel["撤销旧动作与旧响应的执行资格"]
```

## 进展、异常与结束

| 情况 | 当前行为 |
|---|---|
| HID 返回 ok | 只记录“命令已确认”；继续等待新截图验证实际变化 |
| 模型暂时超时、HTTP 408 / 429 / 5xx | 有限重试，重新观察；不重放上一条 HID 动作 |
| JSON 错误或字段缺失 | 将格式问题作为反馈重新请求，最多重试 2 次 |
| 同一动作连续无进展 | 拦截重复动作，要求换策略；反复提出同样无效方案则暂停 |
| 4 次动作仍无已确认视觉进展 | 暂停并要求用户检查 |
| 模型推理期间画面明显变化 | 丢弃旧提案，重新读取截图 |
| 动作部分执行 / 确认超时 | 暂停，避免重复输入或重复提交 |
| 无新画面 / 镜像重建 / 手机断开 USB | 暂停，不继续使用旧画面 |
| 20 动作 / 40 模型调用 / 10 分钟 | 达到限额后暂停；最后动作后仍可在总限额内完成复核 |
| 模型第一次说 done | 尚未完成；必须等待新图并再次评估 |
| 用户停止 | 立即禁止后续动作；迟到的模型响应丢弃 |
| 断电或新 Goal | 任务记忆和执行记录清空；配置继续保存在 NVS |

## 一个示例

Goal：**打开设置的 Wi-Fi 页面，告诉我当前网络，只查看，不修改。**

可能的路径：观察主屏幕 → 打开设置 → 观察设置页 → 进入 Wi-Fi → 读取当前网络 → 提出完成 → 新画面复核 → 返回结果。
如果手机已经在 Wi-Fi 页，模型可以直接提出完成并复核，不必机械重复上述路径；如果某一步没有达到预期，则按实际画面改选下一步。
