# 项目文档导航

本指南面向 **ESP32 自主云端模式（`--cloud`）**，更新时间：2026-10-24。

1. [硬件清单与接线](hardware.md)：设备规格、兼容条件、开发与运行接法。
2. [项目架构](architecture.md)：模块职责、任务并发、内存和运行模式。
3. [业务流程图](workflow.md)：首次配置、Goal 闭环、异常与终止。
4. [数据流图与 API](data-flow.md)：视频、模型请求、HID、状态、凭据与持久化。
5. [代码目录结构](code-map.md)：完整模块地图与常见修改入口。
6. [安装方法](install.md)：固件、App、首次登录、测试与下载模式恢复。
7. [使用手册](manual.md)：日常操作、示例、模型设置、排障。
8. [验证与已知限制](validation.md)：已测结果和未完成的真机验证。
9. [Demo](../demo/README.md)：演示视频和可重复录制的方法。

[上游旧版英文说明](upstream-readme.en.md)和[中文版](upstream-readme.zh-CN.md)属于历史资料。
`docs/ble-protocol.md`、早期运行记录与导出指南也主要描述旧版；当前 App 不执行旧的 BLE / iPhone AgentLoop。
