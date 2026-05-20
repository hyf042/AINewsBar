# AINewsBar

macOS 菜单栏 AI 资讯阅读器。自动抓取主流 AI 资讯，通过阿里云百炼（默认 qwen3.6-plus）生成中文摘要，并提供 AI 每日推荐。

## 功能

- **菜单栏常驻** — 点击图标展开文章列表，不干扰工作流
- **11 个内置精选源** — OpenAI、DeepMind、Hugging Face、TechCrunch AI 等
- **自定义 RSS** — 支持添加任意 RSS / Atom 源，可单独开关；添加时自动验证可用性
- **AI 单篇摘要** — 后台最多 5 并发为每篇文章生成一句话中文简介（无论原文语言）；悬停展开完整摘要
- **今日资讯摘要** — AI 基于标题+摘要生成当日整体概述，悬停临时展开 / 点击固定展开；每 3 小时有新文章时重新生成；支持手动刷新；跨重启持久化
- **AI 今日推荐** — AI 基于标题+摘要挑选 3 篇必读；有新文章或列表为空时才调用 API；支持手动刷新；显示最后更新时间
- **智能增量刷新** — 新增摘要 ≥3 篇时自动触发推荐/日报重新生成（Plan A），避免 API 浪费
- **已读/未读分层** — 已读文章显示在列表底部（"已读 (n)" 分隔），Header 显示 [未读/总数]
- **自适应列表高度** — 文章少时不留空白，文章多时可滚动，最大 460px
- **智能刷新** — 11 个 RSS 源全并发抓取，每小时自动刷新，只保留当天文章
- **Feed 失败提示** — footer 显示抓取失败源数（⚠ N 个源失败），点击跳转设置页排查
- **AI 不可用提示** — API Key 未配置或请求失败时 Header 下方显示橙色 Banner，含"去设置"快捷按钮

## 技术栈

| 模块 | 技术 |
|------|------|
| UI | Swift + SwiftUI（MenuBarExtra） |
| 数据持久化 | SwiftData |
| RSS 解析 | FeedKit |
| AI 摘要/推荐 | 阿里云百炼 DashScope，默认模型 qwen3.6-plus；支持千问/智谱/Kimi/MiniMax 共 9 个预设 + 自定义 |
| 密钥存储 | UserDefaults |

**最低系统要求：macOS 14 Sonoma**

## 项目结构

```
Sources/AINewsBar/
├── App/
│   ├── AINewsBarApp.swift       # @main，ModelContainer，SwiftData 迁移容错
│   └── AppDelegate.swift        # 隐藏 Dock 图标
├── Models/
│   ├── Feed.swift               # SwiftData 模型：订阅源
│   └── Article.swift            # SwiftData 模型：文章（含 AI 摘要字段）
├── Services/
│   ├── BuiltInFeeds.swift       # 11 个内置 AI 资讯源
│   ├── RSSService.swift         # FeedKit 封装；conform RSSFetching
│   ├── BailianService.swift     # DashScope 摘要/推荐生成；conform AISummarizing；含 BailianError 自定义错误
│   ├── PreferencesService.swift # API Key / 模型 / 日报 / 生成摘要数持久化（基于 UserDefaults）；conform PreferencesStoring
│   ├── ServiceProtocols.swift   # DI 协议：RSSFetching / AISummarizing / PreferencesStoring
│   ├── RefreshDecision.swift    # 触发决策纯函数集（completionRate / shouldRegenerate* / withinRegenerationWindow）
│   └── RefreshService.swift     # 定时+按需刷新调度，@MainActor；构造函数注入三 Service；并发控制；手动刷新
└── Views/
    ├── MenuBarView.swift         # 主界面（文章列表 + AI 推荐 + 今日摘要 + AI Banner）
    ├── ArticleRowView.swift      # 文章行（onTapGesture，非 Button）；悬停展开摘要
    └── SettingsView.swift        # 三 Tab 设置：订阅源检测 / 模型选择 + API 检测 / 通用
```

## 安装（直接使用预构建包）

1. 下载最新 `AINewsBar-x.y.z.zip`，解压得到 `AINewsBar.app`
2. 将 `AINewsBar.app` 拖入 `/Applications`
3. 首次打开时，macOS Gatekeeper 会提示"无法验证开发者"（ad-hoc 签名，非 App Store 分发）

**解决方法（二选一）：**

- **右键打开**：在 Finder 中右键 `AINewsBar.app` → 打开 → 仍要打开
- **命令行解除隔离**：
  ```bash
  xattr -cr /Applications/AINewsBar.app
  open /Applications/AINewsBar.app
  ```

## 从源码构建

**要求：** macOS 14+，Xcode Command Line Tools（`xcode-select --install`）

```bash
git clone <repo-url>
cd AINewsBar
./scripts/build.sh
```

脚本会自动完成：停止已运行实例 → release 构建 → 签名 → 打包为 `build/AINewsBar-x.y.z.zip`。

构建完成后启动：

```bash
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

> **注意：** 不要用 `open build/AINewsBar.app`（某些状态下会静默失败）。不要直接运行裸二进制（MenuBarExtra 依赖 bundle 上下文）。

## 运行测试

```bash
swift test
```

单元测试覆盖：
- `PreferencesServiceTests` — UserDefaults 隔离实例，验证 API Key / 模型 / 日报持久化
- `BailianServiceTests` — 推荐序号解析（含去重 / 越界过滤 / 中英文分隔符）+ 三类 prompt 构造
- `RefreshDecisionTests` — 推荐/日报触发条件矩阵 + 时间窗口判断
- `RefreshServiceTests` — Mock RSS/AI + 内存 ModelContainer，覆盖刷新主流程、跨批次去重、AI 错误、强制刷新
- `ModelsTests` / `BuiltInFeedsTests` — 模型默认值与内置源健康度

## 配置 API Key

启动后点击菜单栏图标 → **设置（Cmd+,）** → **API** Tab → 填入阿里云百炼 API Key → 选择模型 → **保存**（保存时自动检测可用性）。

- Key 存储在 UserDefaults（`com.ainewsbar.claude-api-key`）
- 支持 9 个预设模型（千问 / 智谱 / Kimi / MiniMax）或自定义模型名称
- 如需验证 RSS 源可用性，进入 **订阅源** Tab 点击行内"检测"或"检测全部"

## 内置订阅源

| 名称 | 说明 |
|------|------|
| OpenAI News | OpenAI 官方博客 |
| Google DeepMind | DeepMind 研究动态 |
| Hugging Face Blog | HF 技术博客 |
| TechCrunch AI | TC AI 频道 |
| The Verge AI | The Verge AI 频道 |
| Ars Technica AI | Ars Technica AI 频道 |
| The Decoder | AI 专注媒体 |
| MIT Technology Review | MIT 技术评论 |
| VentureBeat AI | VB AI 频道 |
| TLDR AI | TLDR AI 日报 |
| 量子位 | 中文 AI 媒体 |
