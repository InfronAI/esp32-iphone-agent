# GitHub Actions 模板

`github-actions.yml` 包含 iOS、ESP32 两种固件、原生 Harness、网页和旧 Python 服务端测试。
当前发布以模板形式保存，仓库不会自动运行此工作流；本次本地执行结果见
[验证记录](../../docs/guide/validation.md)。

启用方法：使用具备 workflow 写入权限的 GitHub 授权，然后执行：

```bash
mkdir -p .github/workflows
cp tools/ci/github-actions.yml .github/workflows/ci.yml
git add .github/workflows/ci.yml
git commit -m "Enable project CI"
git push
```

经典 PAT 需要 `workflow` scope；其他凭据需要对应的 Actions 工作流写入权限。
iOS job 使用 GitHub 的 macOS runner，需选择安装了 iOS 26.4 或更新 SDK 的 Xcode。
云端固件构建使用 `secrets.example.h` 中的占位值；不要为编译测试添加真实模型或 Wi-Fi 凭据。
