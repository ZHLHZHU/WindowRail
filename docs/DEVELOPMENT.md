# 开发与发布

## 项目结构

```text
Sources/WindowRail/
  Models/       窗口列表、选择状态与通用设置
  Services/     窗口激活、桌面归属与贴边状态
  Views/        侧栏、切换面板、设置页与动画
  AppDelegate.swift
  main.swift
Resources/Info.plist
Tests/WindowRailChecks/
tools/          签名与打包脚本
.github/workflows/build.yml
```

通过 `swift build` / `./tools/test.sh` 编译和测试代码；日常运行请用 `./build.sh` 生成完整 `.app`，这样辅助功能与登录启动才会关联到应用 Bundle。

## 本机固定签名

首次运行 `python3 tools/signing.py init`，在 `~/Library/Application Support/WindowRail/Signing` 创建本机签名资料。以后直接运行 `./build.sh` 复用该身份。

已有签名资料可通过 `WINDOWRAIL_SIGNING_DIR` 指定，或在未跟踪的 `signing.local.json` 中配置：

```json
{"directory": "/absolute/path/to/your/signing-directory"}
```

不要提交证书、钥匙串、密码文件或该配置文件。签名资料缺失时构建失败；不会自动重建身份或退回临时签名。改变证书或从临时签名迁移时，仍需重新授权一次。

## 构建选项

| 环境变量 | 用途 |
| --- | --- |
| `WINDOWRAIL_ARCHS` | `arm64`、`x86_64`，或 `arm64 x86_64` |
| `WINDOWRAIL_OUTPUT_APP` | 输出 `.app` 的完整路径 |
| `WINDOWRAIL_VERSION` | `0.1.0` 格式的应用版本 |
| `WINDOWRAIL_SIGNING_MODE` | `persistent`（默认）、`adhoc`、`identity` |
| `WINDOWRAIL_SIGNING_IDENTITY` | `identity` 模式的签名身份 |
| `WINDOWRAIL_KEYCHAIN` | 可选的签名钥匙串路径 |

`./tools/package.sh` 将应用打包到 `dist/` 并生成 SHA-256 校验文件。

## 发布签名

CI 默认显式使用 `adhoc`，不访问本机签名目录。因此未配置发布证书时，CI 构建的不同版本可能触发重新授权；这与本机构建复用固定身份的行为不同。

如需签名发布，在 GitHub 仓库配置：

- Actions variable：`WINDOWRAIL_SIGNED_RELEASE=true`。
- Secret `APPLE_CERTIFICATE_P12_BASE64`：导出的发布证书及私钥 P12 文件的 Base64 内容。
- Secret `APPLE_CERTIFICATE_PASSWORD`：P12 密码。
- Secret `APPLE_SIGNING_IDENTITY`：证书的 40 位 SHA-1 指纹。

请使用专门的分发证书，不要上传本机 WindowRail 的开发签名资料。CI 在临时钥匙串中导入证书，构建完成后清理。启用签名但缺少证书时会失败，不会静默降级。当前流程不包含 Apple 公证；Developer ID 签名本身不等于完成公证。

## master 与 tag

只有指向 `master` 历史提交的版本 tag 才能发布。支持 `v0.1.0` 与 `v0.1.0-rc.1`，后者生成 prerelease。tag 发布前，需先将对应提交推送到 `master`。

本地测试覆盖窗口分组、未知归属降级、方向键事件路由、当前窗口标记、收起延迟和偏好持久化。辅助功能授权、真实窗口激活、多显示器、Dock 交互和实际登录启动仍需在有桌面会话的 Mac 上验收，CI 单元测试不替代这些检查。
