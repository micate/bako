# Bako 更新发布

Bako 使用 Sparkle 2 检测、下载并安装 macOS 独立分发版本。开发构建缺少正式更新配置时，更新控制器保持关闭，不会请求占位地址或影响应用启动。

## 应用包配置

正式发布必须是带稳定 Bundle ID 和版本信息的 `.app`，不能直接发布 `swift run` 生成的开发可执行文件。仓库中的 Xcode App target 使用 `Config/Bako-Info.plist`，版本和更新字段由 `Config/*.xcconfig` 注入：

```xml
<key>CFBundleIdentifier</key>
<string>你的 Bundle ID</string>
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
<key>SUFeedURL</key>
<string>https://你的更新域名/bako/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>由 Sparkle generate_keys 生成的公钥</string>
```

`CFBundleVersion` 必须在每次发布时严格递增。`SUFeedURL` 只接受 HTTPS；缺少 feed 或公钥时，Bako 不启动 Sparkle，“检查更新…”菜单保持禁用。

首次本地配置：

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

在忽略提交的 `Local.xcconfig` 中填写 `DEVELOPMENT_TEAM`、`BAKO_UPDATE_FEED_URL` 和 `BAKO_UPDATE_PUBLIC_ED_KEY`。版本号与 build number 提交到 `Config/Base.xcconfig`，确保每个发布版本可追踪。

## 首次准备

1. 使用 Sparkle 分发包中的 `generate_keys` 生成 EdDSA 密钥。
2. 将公钥写入 `SUPublicEDKey`。
3. 将私钥保存在发布机器的钥匙串或 CI Secret 中，不提交到仓库。
4. 为正式 App 配置 Developer ID Application 签名与 Hardened Runtime。

## 发布顺序

1. 更新 `CFBundleShortVersionString` 和递增的 `CFBundleVersion`。
2. 构建 Release App，并使用 Developer ID 签名。
3. 使用 `notarytool` 公证，并用 `stapler` 装订公证票据。
4. 将 App 打包成 ZIP、DMG 或 Sparkle 支持的其他归档。
5. 把归档和同名 Markdown 更新说明放入更新目录。
6. 运行 Sparkle 的 `generate_appcast`，生成签名后的 `appcast.xml` 和可选增量包。
7. 先上传归档、更新说明和增量包，确认可下载后最后上传 `appcast.xml`。

发布后必须从安装在 `/Applications` 中的上一正式版本执行一次完整升级测试，验证发现版本、签名校验、安装、退出和重启。

## 本机覆盖安装

不要把 `CODE_SIGNING_ALLOWED=NO` 的构建直接复制到 `/Applications`。Bako 内嵌
Sparkle；当本机没有可用的 Apple 代码签名证书时，主程序和 Sparkle 使用临时签名，
Hardened Runtime 的 Library Validation 无法匹配 Team ID，应用会在 `dyld` 加载
`Sparkle.framework` 时崩溃。

本机临时安装可以保留 Hardened Runtime，并使用
`Config/Bako-Debug.entitlements` 中的
`com.apple.security.cs.disable-library-validation` 权限重新签名外层 App。该方案仅供
本机开发验证，不替代 Developer ID 签名和公证。

覆盖安装完成后必须执行三项验证：

1. 使用 `codesign --verify --deep --strict` 校验整个 App bundle；
2. 从 `/Applications/Bako.app` 实际启动并确认进程持续运行；
3. 确认 `~/Library/Logs/DiagnosticReports` 中没有产生新的 Bako 崩溃报告。

## 应用内行为

- Sparkle 按自己的调度策略执行后台检查。
- 发现有效版本后，左侧栏底部显示可点击的“vX.Y.Z 可更新”。
- 点击提示或应用菜单中的“检查更新…”后，使用 Sparkle 标准界面展示更新说明并完成安装。
- feed、公钥或 HTTPS 配置无效时，开发版仍可正常运行，但更新入口不可用。
