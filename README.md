# AINewsBar

macOS 菜单栏 AI 资讯阅读器。自动抓取主流 AI 资讯，通过阿里云百炼 qwen-plus 生成中文摘要，并提供 AI 每日推荐。

## 功能

- **菜单栏常驻** — 点击图标展开文章列表，不干扰工作流
- **11 个内置精选源** — OpenAI、DeepMind、Hugging Face、TechCrunch AI 等
- **自定义 RSS** — 支持添加任意 RSS / Atom 源，可单独开关
- **AI 单篇摘要** — 后台自动为每篇文章生成一句话中文简介（无论原文语言）
- **今日资讯摘要** — AI 生成当日整体概述，可展开/收起
- **AI 今日推荐** — 每次刷新 AI 自动挑选 3 篇必读，附中文摘要
- **已读过滤** — 点击文章即标为已读并从列表移除
- **智能刷新** — 每小时自动后台刷新，只保留当天文章

## 技术栈

| 模块 | 技术 |
|------|------|
| UI | Swift + SwiftUI（MenuBarExtra） |
| 数据持久化 | SwiftData |
| RSS 解析 | FeedKit |
| AI 摘要 | 阿里云百炼 DashScope，模型 qwen-plus |
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
│   ├── ClaudeService.swift      # DashScope qwen-plus 摘要/推荐生成
│   ├── RefreshService.swift     # 定时 + 按需刷新调度，@MainActor
│   └── KeychainService.swift    # API Key 读写（实为 UserDefaults）
└── Views/
    ├── MenuBarView.swift         # 主界面（文章列表 + 摘要区 + 推荐区）
    ├── ArticleRowView.swift      # 文章行（onTapGesture，非 Button）
    └── SettingsView.swift        # 设置窗口（订阅源 / API Key）
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

启动后点击菜单栏图标 → **设置（Cmd+,）** → 填入阿里云百炼 API Key → 保存。

Key 存储在 UserDefaults（`com.ainewsbar.claude-api-key`）。

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
