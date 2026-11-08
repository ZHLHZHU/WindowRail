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
| `WINDOWRAIL_SIGNING_MODE` | `persistent`（默认）、`adhoc`、`pinned`、`identity` |
| `WINDOWRAIL_SIGNING_IDENTITY` | `pinned` / `identity` 模式的签名身份 |
| `WINDOWRAIL_KEYCHAIN` | 可选的签名钥匙串路径 |

`./tools/package.sh` 将应用打包到 `dist/` 并生成 SHA-256 校验文件。

## 发布签名

本仓库 master、tag 与手动构建复用独立的发布证书，以证书指纹和 Bundle ID 固定 designated requirement。PR 构建使用 `adhoc`，不读取签名 Secrets。

GitHub 仓库配置：

- Actions variable `WINDOWRAIL_SIGNED_RELEASE=true`。
- Actions variable `WINDOWRAIL_RELEASE_SIGNING_MODE=pinned`。
- Secret `APPLE_CERTIFICATE_P12_BASE64`：发布证书及私钥 P12 的 Base64 内容。
- Secret `APPLE_CERTIFICATE_PASSWORD`：P12 密码。
- Secret `APPLE_SIGNING_IDENTITY`：证书的 40 位 SHA-1 指纹，必须与 `Resources/release-signing.sha1` 一致。

证书应只生成一次，后续复用同一份备份；不要在每次 CI 中生成证书。签名资料缺失、指纹不符或导入失败时构建失败，不会静默降级。仅公开证书指纹，私钥和密码不得提交。本机开发签名与发布签名分开保存。

从 v1.0.0 的 ad-hoc 包或本机开发包首次换到固定发布签名时，需要重新授权一次。之后应保持应用路径、Bundle ID 与签名身份不变；系统重置权限或更换证书仍可能需要重新授权。固定签名不等于 Developer ID 或 Apple 公证，当前流程不包含公证。

若以后使用 Developer ID，设置 `WINDOWRAIL_RELEASE_SIGNING_MODE=identity` 并配置对应证书；这种身份迁移需单独验证权限行为。

## master 与 tag

只有指向 `master` 历史提交的版本 tag 才能发布。支持 `v0.1.0` 与 `v0.1.0-rc.1`，后者生成 prerelease。tag 发布前，需先将对应提交推送到 `master`。

本地测试覆盖窗口分组、未知归属降级、方向键事件路由、当前窗口标记、收起延迟和偏好持久化。辅助功能授权、真实窗口激活、多显示器、Dock 交互和实际登录启动仍需在有桌面会话的 Mac 上验收，CI 单元测试不替代这些检查。

## 本地化

文案源文件位于 `Sources/WindowRail/Resources/<语言>.lproj/Localizable.strings`。修改文案后重新构建；不要直接编辑已签名 `.app` 内的资源。

- 新增文案时，向 `L10n.Key` 添加类型化 key，并在所有语言表中添加翻译。
- 新增语言时，添加对应的 `.lproj/Localizable.strings`，并更新 `Info.plist` 的 `CFBundleLocalizations`；设置页从资源自动发现语言，无需维护另一份 Swift 语言列表。
- 格式化文案保持占位符类型一致，例如 `%@` 与 `%d`；调整语序时可以使用 `%1$@`、`%2$d`。
- `./tools/test.sh` 会检查缺失、重复、空文案、类型化 key、格式占位符和语言元数据，并用错误翻译样本验证检查器确实阻止这些问题。

运行时单条翻译缺失时回退到英文；不支持的语言选择回退为跟随系统。设置页语言选择保存于 `appLanguage`，即时刷新设置页、菜单、侧栏分组和窗口切换面板。窗口标题与第三方应用名称保留原始内容。
