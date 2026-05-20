# AINewsBar

macOS 菜单栏 AI 资讯阅读器。自动抓取主流 AI 资讯，通过阿里云百炼（默认 qwen3.6-plus）生成中文摘要，并提供 AI 每日推荐。

## 功能

- **菜单栏常驻** — 点击图标展开文章列表，不干扰工作流
- **11 个内置精选源** — OpenAI、DeepMind、Hugging Face、TechCrunch AI 等
- **自定义 RSS** — 支持添加任意 RSS / Atom 源，可单独开关；添加时自动验证可用性
- **AI 单篇摘要** — 后台自动为每篇文章生成一句话中文简介（无论原文语言）；悬停展开完整摘要
- **今日资讯摘要** — AI 生成当日整体概述，悬停临时展开 / 点击固定展开；每 3 小时有新文章时重新生成；跨重启持久化
- **AI 今日推荐** — AI 基于标题+摘要挑选 3 篇必读；有新文章或列表为空时才调用 API；显示最后更新时间
- **已读/未读分层** — 已读文章显示在列表底部（"已读 (n)" 分隔），Header 显示 [未读/总数]
- **智能刷新** — 每小时自动后台刷新，只保留当天文章
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
│   ├── RSSService.swift         # FeedKit 封装
│   ├── ClaudeService.swift      # DashScope 摘要/推荐生成（类名 BailianService）
│   ├── RefreshService.swift     # 定时 + 按需刷新调度，@MainActor；含 AIAvailability
│   └── KeychainService.swift    # API Key / 模型 / 日报持久化（实为 UserDefaults）
└── Views/
    ├── MenuBarView.swift         # 主界面（文章列表 + AI 推荐 + 今日摘要 + AI Banner）
    ├── ArticleRowView.swift      # 文章行（onTapGesture，非 Button）；悬停展开摘要
    └── SettingsView.swift        # 三 Tab 设置：订阅源检测 / 模型选择 + API 检测 / 通用
```

## 构建 & 运行

```bash
cd /Users/hyf042/Projects/AINewsBar
swift build
pkill -x AINewsBar; sleep 1
cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

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
