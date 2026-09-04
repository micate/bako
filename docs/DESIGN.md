# Bako 设计文档

> 状态：与当前实现同步（2026-09-03）  
> 目标平台：macOS 12+  
> 技术栈：Swift 5.9、SwiftUI、AppKit、SQLite 3、Sparkle 2

本文记录 Bako 当前已经实现的产品行为和技术边界。“后续工作”一节是明确尚未实现的内容，不应被理解为现有能力。影响数据模型、存储路径、文件系统行为或用户可见规则的代码变更，应在同一次变更中同步本文。

## 1. 产品定位

Bako 将本机多个 Agent 用户目录中的 Skills 集中到一个存储目录，并用软链接向各 Agent 暴露所需内容。用户通过分组声明“哪些 Skills 应该挂载到哪些 Agent 或共享端点”，Bako 将所有已启用分组合并后对账文件系统。

Bako 当前不做以下事情：

- 创建或编辑 `SKILL.md`。
- 提供在线 Skill 市场、Git 同步或云同步。
- 自动管理仓库/项目级 Skill 目录。
- 执行 Skill 中的脚本或安装器。
- 接受任意自定义 Agent 挂载目录；自定义目录只作为扫描来源。

## 2. 当前用户流程

### 2.1 扫描和导入

1. 启动时根据内置检测路径列出本机已发现的 Agent。
2. 用户在 Skills 页勾选要由 Bako 管理的 Agent，然后确认扫描。
3. Bako 扫描已启用 Agent 的专属端点、共享端点 `~/.agents/skills`，以及已启用的自定义扫描源。
4. 对真实 Skill 计算指纹，迁移到中央存储，并在来源位置创建软链接。
5. Agent 端点中的导入项自动进入对应的“已导入 · …”系统分组；自定义源只保留来源链接，不自动加入分组。
6. 外部有效链接和损坏链接只计入扫描摘要，不接管、不改写。

扫描是显式操作，不是后台目录监控。单项失败不会停止其他候选项，错误会进入扫描摘要和 Activity。

### 2.2 分组和挂载

一个分组包含：

- `skillIDs`：分组中的 Skills。
- `targets`：Agent 专属目标或共享 Endpoint。
- `isEnabled`：是否参与当前期望状态。
- `lastEnabledAt`：同名变体自动选择的时间依据。

用户可以创建、重命名、排序、删除和启停分组。Groups 编辑器采用草稿式保存；菜单栏可以直接切换已有分组。

### 2.3 自定义扫描源

Settings 可以通过 `NSOpenPanel` 添加目录。目录可以是：

- 直接包含多个 Skill 子目录的根目录；或
- 自身直接包含 `SKILL.md` 的单个 Skill 目录。

默认只识别目录型 Skill。用户可以为某个扫描源开启独立 Markdown 文件支持。扫描源可暂停和移除；移除只删除配置，不删除已迁移内容或来源软链接。

添加前会拒绝不可读目录、Home、文件系统根目录、中央存储及与已有源重叠的目录。位于 Git 工作树中的目录会显示额外确认。安全书签用于在可能的情况下恢复目录访问，失败时回退到保存的绝对路径。

### 2.4 恢复集中管理的 Skills

Settings 中的恢复操作会尝试将所有中央 Skill 移到 `~/.agents/skills`：

- 目标名称优先沿用首次来源的文件名，否则使用 Skill 名或稳定 ID。
- 已知且仍指向中央副本的 Agent 链接会重定向到恢复后的共享副本。
- 目标被真实文件或其他链接占用时，该 Skill 保持不变并报告失败。
- 成功恢复的 Skill 会从 Bako 状态和所有分组成员关系中移除。

这是统一恢复到共享目录，不是逐项恢复到每个原始来源。

## 3. Skill 与链接语义

### 3.1 支持的条目

```swift
enum SkillEntryKind {
    case directoryBundle // <name>/SKILL.md
    case flatMarkdown    // <name>.md
}
```

目录型 Skill 必须直接包含 `SKILL.md`。`flatMarkdown` 只在端点声明支持时扫描；当前 DeepSeek Harness 原生端点支持两种类型，自定义扫描源需要用户显式开启 Markdown。

YAML frontmatter 仅解析顶层 `name` 和 `description`，不修改原文。缺少名称时使用文件或目录名，缺少描述时使用空字符串。

### 3.2 内容指纹和去重

指纹使用 SHA-256：

- 目录内容按相对路径排序。
- 普通文件计入路径、类型和原始字节。
- 内部软链接计入路径、类型和链接文本。
- 修改时间、所有者等文件系统元数据不参与计算。

相同名称且相同指纹复用同一个中央 Skill；名称相同但指纹不同则保存为独立变体。迁移前会再次计算来源指纹，避免扫描后内容变化造成错误提交。

### 3.3 链接所有权

Bako 只会在以下条件下删除不再需要的挂载链接：

- 路径本身是软链接；且
- 解析后的目标位于 Bako 的 `Skills/` 中；且
- 该挂载不在当前期望集合中。

真实文件、外部软链接和无法确认归属的链接不会被覆盖或删除。目标路径被占用时对账失败并保留现场。

迁移产生的来源链接与分组产生的激活链接在当前数据模型中没有单独的持久化角色字段。安全性依靠目标必须位于中央存储，以及期望挂载集合来保证；自定义来源不是 Endpoint，因此不会被普通分组对账删除。

## 4. 分组期望状态

对每个启用分组，候选挂载是 Skills 与 Targets 的笛卡尔积：

```text
Candidate Mounts(group) = group.skills × group.targets
Desired Candidates = Union(Candidate Mounts of enabled groups)
```

`GroupTarget.agent(id)` 解析为该 Agent 的专属 Endpoint；`GroupTarget.shared(id)` 直接指向共享 Endpoint。选择多个 Agent 不会自动合并成共享目录。

同一物理端点的同一挂载名只能选择一个变体。当前选择顺序为：

1. `MountPlanner` 调用方提供的首选变体（现有 UI 尚未提供或持久化该设置）。
2. 候选中 `lastEnabledAt` 最新的分组。
3. Skill UUID 字符串排序，作为确定性兜底。

所选变体的所有引用分组 ID 会合并到同一个 `DesiredMount`。停用一个分组时，只要其他启用分组仍需要该挂载，链接就会保留。

对账执行以下动作：创建缺少的 Endpoint 和链接、保留目标正确的链接、报告被占用或目标不同的链接、删除不再期望且确认指向中央存储的链接。当前实现不会自动替换“指向错误中央 Skill”的既有链接，而是将其报告为占用。

## 5. Agent Catalog

Catalog 当前由 `AgentCatalog.swift` 中的 Swift 值随应用编译，JSON 文件只作为测试契约夹具，不是运行时数据源。

| Agent | 状态 | 专属 Endpoint | 兼容共享端点 |
|---|---|---|---|
| OpenAI Codex | `managed` | `~/.codex/skills` | `~/.agents/skills` |
| Claude Code | `managed` | `~/.claude/skills` | — |
| Cursor | `experimental` | — | 声明兼容 `~/.agents/skills`，但不作为独立管理目标 |
| Qoder | `managed` | `~/.qoder/skills` | — |
| Qoder CN IDE | `managed` | `~/.lingma/skills` | — |
| DeepSeek Harness | `managed` | `${DSH_HOME:-~/.dsh}/skills` | `~/.agents/skills` |
| ZCode | `managed` | `~/.zcode/skills` | — |
| OpenClaw | `managed` | `~/.openclaw/skills` | `~/.agents/skills` |
| Kilo Code | `managed` | `~/.kilo/skills` | `~/.agents/skills` |
| Zoo Code | `managed` | `~/.roo/skills` | `~/.agents/skills` |
| Devin Desktop | `detectOnly` | — | — |

`managed` Agent 只有在检测路径存在且未被用户停用时，才会扫描和对账专属 Endpoint。共享端点独立存在并始终保留为扫描和分组目标；停用单个 Agent 不会改变共享目录对其他消费者的影响。

路径模板由 `PathResolver` 统一展开，支持 `~` 和 `${NAME:-fallback}`。当前没有命令行可执行文件检测、App bundle 检测或临时 CLI 参数发现，检测依据仅为 Catalog 中配置路径是否存在。

## 6. 中央存储和持久化

默认目录：

```text
~/Library/Application Support/Bako/
├── Skills/
│   └── <skill-uuid>/
└── State/
    ├── bako.sqlite
    ├── bako.sqlite-wal
    ├── bako.sqlite-shm
    ├── catalog.json       # 仅作为旧版首次迁移输入
    └── transactions/
        └── <transaction-uuid>.json
```

中央目录使用 UUID，不使用显示名称，因此可以保存同名变体。SQLite 以 WAL 模式和 `synchronous=FULL` 运行；当前 schema 只有单行 `app_state` 表，整个 `PersistedState` 编码为 JSON BLOB，`PRAGMA user_version=1`。

持久化内容包括：

- Skills 及其来源、指纹、中央路径和健康状态。
- 分组、成员、目标、顺序和启用时间。
- 最近最多 200 条 Activity。
- 自定义扫描源和安全书签。
- 已停用管理的 Agent ID。

如果数据库尚无状态且旧 `State/catalog.json` 存在，会导入一次旧 JSON；之后只写 SQLite。

## 7. 迁移事务和恢复

每个 Skill 使用独立 JSON 事务日志，主要阶段为 `prepared`、`sourceStaged`、`centralCommitted`、`linkCommitted` 和 `committed`。

同卷迁移的核心顺序：

1. 写入事务意图。
2. 将来源移动到中央临时路径。
3. 校验临时内容指纹。
4. 提交为最终 UUID 路径。
5. 在来源位置创建指向中央副本的软链接。
6. 标记事务提交。

跨卷时先复制到中央临时路径并校验，再提交中央副本，然后把来源移动到同目录备份、创建链接并删除备份。发现重复内容时复用已有中央副本，只暂存和替换来源。

应用加载状态前先扫描未完成日志。恢复器根据来源、临时路径、备份、目标和指纹决定继续提交或回滚；无法安全判断时保留日志并报告错误。已完成日志也会在下次启动恢复阶段清理。

当前迁移引擎没有显式调用 `fsync`，持久性主要依赖文件系统操作、原子 rename 和同步写入事务日志。

## 8. 应用架构

```text
BakoApplication / BakoAppDelegate
        │
        ├── MainWindowView ── UpdateController (Sparkle)
        ├── MenuBarController (NSStatusItem / NSMenu)
        └── BakoModel (@MainActor, UI 状态与工作流编排)
                  │
                  ├── AgentCatalog + PathResolver
                  ├── SkillScanner + Fingerprinter
                  ├── MigrationEngine + RecoveryEngine
                  ├── SkillRestoreEngine + LinkReconciler
                  ├── MountPlanner
                  └── StateStore (SQLite)
```

文件系统写入组件使用 actor 串行化各自操作，UI 模型固定在 MainActor。`BakoModel` 目前承担扫描、导入、分组对账、恢复和持久化编排，是应用层入口。

## 9. UI 和本地化

主窗口为四个页面：

- **Skills**：检测 Agent、管理扫描范围、执行扫描、搜索 Skills 和在 Finder 中定位中央副本。
- **Groups**：编辑分组、目标和成员，启停并拖拽排序。
- **Activity**：展示扫描、迁移、挂载、恢复和错误记录，可清空。
- **Settings**：显示中央目录、管理自定义扫描源、执行统一恢复。

macOS 12 没有 `MenuBarExtra`，因此菜单栏使用 `NSStatusItem`。关闭主窗口时实际隐藏并保留 SwiftUI scene，同时切换为 accessory 激活策略，从 Dock 和 `Command-Tab` 中隐藏。通过菜单栏再次打开时，先恢复 regular 激活策略，再唤起同一窗口。

界面通过 `L10n.string` 使用 `en.lproj` 和 `zh-Hans.lproj` 的同名键。测试校验两种语言的键集合和格式占位符一致。

## 10. 更新与分发

Sparkle 只有在主 Bundle 同时存在 HTTPS `SUFeedURL` 和非空 `SUPublicEDKey` 时才启动。普通 `swift run` 构建配置不完整，更新功能保持禁用且不访问网络。

仓库同时维护 Swift Package 入口和 `Bako.xcodeproj`。Xcode 工程提供 macOS App、单元测试 targets 与共享 Scheme，并复用 `Sources/`、`Tests/` 和 Sparkle 依赖；`Config/` 集中维护 Bundle ID、版本、Info.plist、Hardened Runtime、entitlements 和 Debug/Release 配置。正式分发仍需配置 Developer ID 签名、公证和 appcast；具体流程见 [UPDATES.md](UPDATES.md)。

## 11. 测试现状

当前测试覆盖：

- Agent Catalog 与 JSON 契约夹具一致性。
- 路径模板、危险目录和重叠扫描源校验。
- frontmatter 解析和稳定指纹。
- 多分组挂载规划及同名变体选择。
- 迁移、去重、跨卷复制及多个中断阶段的恢复。
- Bako 链接对账和外部链接保护。
- 自定义扫描源、Git 工作树识别和书签回退。
- Skills 恢复到共享目录及已知链接重定向。
- SQLite 状态读写、WAL 和旧 JSON 导入。
- 英文与简体中文资源一致性。

测试主要使用临时目录和 FileManager 夹具。尚没有真实 Agent 版本端到端兼容测试、签名 App UI 自动化或 Sparkle 发布链路测试。

## 12. 当前已知缺口与后续工作

按当前实现，优先缺口是：

1. 数据库损坏后根据中央目录、来源链接和事务日志重建最小索引。
2. 为同名变体提供按 Endpoint 设置首选版本的 UI 和持久化；必要时保留当前已挂载候选，减少无意义切换。
3. 重新扫描或监控中央 Skill 的外部修改，更新指纹和健康状态。
4. 把 Agent Catalog 从编译期 Swift 定义演进为带 schema 版本的运行时资源，并扩展真实版本契约测试。
5. 改进对账：在确认链接属于 Bako 时，可安全修复指向错误中央变体的链接，而不只报告占用。
6. 明确来源链接与激活链接的持久化角色，进一步收紧删除和恢复语义。
7. 让恢复操作支持选择 Skill 和目标，或按原来源恢复，而不只统一迁回共享目录。
8. 基于现有 `Config/` 补齐正式 App target、签名、公证、更新 feed 和发布验证。
9. 评估迁移关键步骤的显式 `fsync`，并增加进程崩溃/断电级故障注入测试。

这些缺口不改变当前最重要的安全原则：无法确认所有权时不覆盖、不删除；单项失败时优先保留或恢复用户原始内容。
