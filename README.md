# Bako

Bako 是一款面向 macOS 12 及以上版本的本机 Agent Skills 集中管理工具。它把分散在各 Agent 用户目录中的 Skills 迁移到中央存储，再通过软链接挂载回原目录；用户可以用分组一次切换多个 Agent 的 Skill 组合。

> 当前状态：已有可运行的 Swift Package 和 Xcode macOS App target。核心迁移、分组、恢复和持久化流程已实现；正式分发仍需配置开发者签名、更新源并执行公证。

## 当前能力

- 自动检测已内置规则的 Agent，并允许逐个启用或停用其专属目录管理。
- 扫描 Agent 用户级目录、`~/.agents/skills` 和用户添加的自定义目录。
- 识别目录型 `<name>/SKILL.md`；DeepSeek Harness 和显式开启该选项的自定义源也支持 `<name>.md`。
- 根据稳定 SHA-256 内容指纹迁移、去重并保留同名不同内容的变体。
- 将真实 Skill 移入 `~/Library/Application Support/Bako/Skills/`，在来源位置留下软链接。
- 使用可恢复事务日志处理迁移，并在跨磁盘时执行“复制、校验、提交”。
- 创建包含 Skills 和目标 Agent 的分组；多个启用分组按并集对账挂载状态。
- 通过 SwiftUI 主窗口管理 Skills、Groups、Activity 和 Settings，并通过菜单栏快速切换分组。
- 使用 SQLite/WAL 保存状态，并兼容导入旧版 `catalog.json`。
- 将中央 Skills 恢复到 `~/.agents/skills`，同时重定向 Bako 已知的 Agent 链接。
- 提供英文和简体中文界面，以及 Sparkle 2 更新接入。

完整的行为、数据模型、安全边界和当前缺口见 [设计文档](docs/DESIGN.md)。独立分发的签名、公证和 appcast 流程见 [更新发布文档](docs/UPDATES.md)。

## 已内置的 Agent 规则

| 状态 | Agent |
|---|---|
| 可管理 | OpenAI Codex、Claude Code、Qoder、Qoder CN IDE、DeepSeek Harness、ZCode、OpenClaw、Kilo Code、Zoo Code（兼容 Roo 目录） |
| 实验性检测 | Cursor；当前没有已验证的专属用户级挂载目录 |
| 仅检测 | Devin Desktop；当前只支持项目级 Skills |

共享端点 `~/.agents/skills` 始终作为独立目标处理。选择它可能同时影响 Codex、DeepSeek Harness、OpenClaw、Kilo Code 和 Zoo Code，Bako 不会把它伪装成某个 Agent 的专属目录。

## 开发环境

- macOS 12+
- Xcode 15+ / Swift 5.9+
- Swift Package Manager
- Sparkle 2.9.6
- 系统 SQLite 3

## 运行

推荐用 Xcode 打开 `Bako.xcodeproj`，选择共享的 `Bako` scheme 后运行。该工程会构建完整的 `Bako.app`，包含图标、本地化资源和 Sparkle.framework。

`Package.swift` 继续作为轻量开发与测试入口，也可以使用完整 Xcode 工具链：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run Bako
```

首次扫描前，请先在 Skills 页确认要由 Bako 管理的 Agent。扫描会移动识别到的真实 Skill，并在原位置创建指向中央存储的软链接；外部链接和损坏链接只会被报告，不会被接管或删除。

## 测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

测试覆盖 Agent Catalog 契约、路径解析、元数据解析、内容指纹、挂载规划、扫描源校验、迁移与恢复、链接对账、状态存储和本地化一致性。

## 项目结构

```text
Sources/BakoApp/
├── AgentCatalog/   # Agent 定义、检测和路径模板解析
├── AppUI/          # SwiftUI 主窗口、状态模型、菜单栏与更新控制器
├── Domain/         # 核心模型、元数据解析和挂载规划
├── FileSystem/     # 扫描、指纹、迁移、恢复、还原与链接对账
├── Localization/   # 本地化入口
├── Persistence/    # SQLite/WAL 状态存储
└── Resources/      # 图标和本地化资源

Tests/BakoAppTests/ # 单元测试与契约夹具
Bako.xcodeproj/      # macOS App、单元测试 targets 与共享 Bako scheme
Config/              # Info.plist、xcconfig、签名与 Hardened Runtime entitlements
Design/Icons/       # 图标源文件、导出和预览
docs/               # 设计与发布文档
```

## 当前限制

- Agent Catalog 当前随代码编译，并非运行时加载的 JSON Catalog。
- 同名变体会按最近启用分组和稳定 ID 自动选择，尚无 UI 或持久化设置指定首选变体。
- 尚未实现数据库损坏后的中央目录索引重建，也不会持续监控中央 Skill 的外部修改。
- “恢复”当前统一迁回 `~/.agents/skills`，不支持按原来源逐项还原。
- 未填写更新 feed 和 EdDSA 公钥时，Sparkle 会安全保持关闭；正式分发还需要 Developer ID 签名、公证与 appcast 托管。

## 发布配置

将 `Config/Local.xcconfig.example` 复制为 `Config/Local.xcconfig`，填写 Team ID、HTTPS appcast 地址和 Sparkle EdDSA 公钥。该本地文件已加入 `.gitignore`；版本号和 build number 则统一维护在 `Config/Base.xcconfig`。
